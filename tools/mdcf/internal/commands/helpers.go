package commands

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/mahsanamin/mdcf/internal/config"
	"github.com/mahsanamin/mdcf/internal/confluence"
)

// expandEnv is a thin wrapper around os.ExpandEnv so call sites read nicely.
func expandEnv(s string) string { return os.ExpandEnv(s) }

// mustResolveConfig loads + merges config starting from dir. If the global
// config is missing, returns an actionable error instead of the raw sentinel.
func mustResolveConfig(dir string) (*config.Resolved, error) {
	r, err := config.Resolve(dir)
	if err != nil {
		if errors.Is(err, config.ErrGlobalMissing) {
			return nil, fmt.Errorf("global config not found at ~/.mdcf/config.yaml — run `mdcf setup` first")
		}
		return nil, err
	}
	return r, nil
}

// newClient builds a Confluence client using a resolved config. The token
// is env-expanded so ${MDCF_API_TOKEN} works.
func newClient(r *config.Resolved) *confluence.Client {
	token := expandEnv(r.APIToken)
	return confluence.New(r.BaseURL, r.Email, token, r.SpaceKey)
}

// absPath returns a cleaned absolute path. Panics are avoided — errors are
// surfaced as plain strings to the caller.
func absPath(p string) (string, error) {
	abs, err := filepath.Abs(p)
	if err != nil {
		return "", err
	}
	return filepath.Clean(abs), nil
}

// isDir returns true if p exists and is a directory.
func isDir(p string) bool {
	info, err := os.Stat(p)
	return err == nil && info.IsDir()
}
