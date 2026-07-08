package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// ErrGlobalMissing is returned when ~/.mdcf/config.yaml does not exist.
var ErrGlobalMissing = errors.New("global config missing (run `mdcf setup` first)")

// LoadGlobal reads ~/.mdcf/config.yaml, expanding ${VAR} in values via env.
// Returns ErrGlobalMissing if the file does not exist.
func LoadGlobal() (*Global, error) {
	path, err := GlobalPath()
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, ErrGlobalMissing
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var g Global
	if err := yaml.Unmarshal(data, &g); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	g.BaseURL = os.ExpandEnv(g.BaseURL)
	g.Email = os.ExpandEnv(g.Email)
	g.APIToken = os.ExpandEnv(g.APIToken)
	return &g, nil
}

// SaveGlobal writes the global config to ~/.mdcf/config.yaml with mode 0600.
func SaveGlobal(g *Global) error {
	path, err := GlobalPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("mkdir %s: %w", filepath.Dir(path), err)
	}
	data, err := yaml.Marshal(g)
	if err != nil {
		return fmt.Errorf("marshal global config: %w", err)
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}

// LoadWorkspace reads a single .mdcf.yaml file. Returns nil, nil if missing.
func LoadWorkspace(path string) (*Workspace, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var w Workspace
	if err := yaml.Unmarshal(data, &w); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	return &w, nil
}

// SaveWorkspace writes a .mdcf.yaml file (mode 0644).
func SaveWorkspace(path string, w *Workspace) error {
	data, err := yaml.Marshal(w)
	if err != nil {
		return fmt.Errorf("marshal workspace config: %w", err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}

// collectWorkspaceChain walks from startDir up to the filesystem root,
// collecting all .mdcf.yaml files. Returned slice is shallowest-first so
// the caller can merge left-to-right with deeper overriding.
func collectWorkspaceChain(startDir string) ([]*Workspace, error) {
	abs, err := filepath.Abs(startDir)
	if err != nil {
		return nil, err
	}
	var chain []*Workspace
	dir := abs
	for {
		candidate := filepath.Join(dir, WorkspaceFilename)
		w, err := LoadWorkspace(candidate)
		if err != nil {
			return nil, err
		}
		if w != nil {
			// Prepend so the outermost (shallowest) ends up first.
			chain = append([]*Workspace{w}, chain...)
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return chain, nil
}

// Resolve walks from startDir up, collecting .mdcf.yaml chain, then merges
// with the global config. Deeper workspace files override shallower ones.
func Resolve(startDir string) (*Resolved, error) {
	g, err := LoadGlobal()
	if err != nil {
		return nil, err
	}
	chain, err := collectWorkspaceChain(startDir)
	if err != nil {
		return nil, err
	}
	r := &Resolved{Global: *g}
	for _, w := range chain {
		if w.SpaceKey != nil {
			r.SpaceKey = *w.SpaceKey
		}
		if w.ParentPagePath != nil {
			r.ParentPagePath = *w.ParentPagePath
		}
		if w.GithubRepoURL != nil {
			r.GithubRepoURL = *w.GithubRepoURL
		}
		if w.ConfluencePageID != nil {
			r.ConfluencePageID = *w.ConfluencePageID
		}
	}
	return r, nil
}

// NearestWorkspacePath returns the path to the nearest .mdcf.yaml found by
// walking up from startDir, or "" if none exists.
func NearestWorkspacePath(startDir string) (string, error) {
	abs, err := filepath.Abs(startDir)
	if err != nil {
		return "", err
	}
	dir := abs
	for {
		candidate := filepath.Join(dir, WorkspaceFilename)
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", nil
		}
		dir = parent
	}
}
