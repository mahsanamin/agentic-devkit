// Package config holds the resolved configuration merged from the global
// ~/.mdcf/config.yaml and any .mdcf.yaml files discovered walking up from a
// target file. Deeper (closer to target) wins.
package config

import (
	"fmt"
	"os"
	"path/filepath"
)

// Global is the user-wide config stored at ~/.mdcf/config.yaml.
type Global struct {
	BaseURL  string `yaml:"base_url"`
	Email    string `yaml:"email"`
	APIToken string `yaml:"api_token"`
}

// Workspace is a per-directory config stored as .mdcf.yaml. Fields are
// pointers so we can tell "unset" (inherit from parent) from "set to empty".
type Workspace struct {
	SpaceKey         *string `yaml:"space_key,omitempty"`
	ParentPagePath   *string `yaml:"parent_page_path,omitempty"`
	GithubRepoURL    *string `yaml:"github_repo_url,omitempty"`
	ConfluencePageID *string `yaml:"confluence_page_id,omitempty"`
}

// Resolved is the final merged view used by commands.
type Resolved struct {
	Global
	SpaceKey         string
	ParentPagePath   string
	GithubRepoURL    string
	ConfluencePageID string
}

// GlobalPath returns ~/.mdcf/config.yaml.
func GlobalPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home dir: %w", err)
	}
	return filepath.Join(home, ".mdcf", "config.yaml"), nil
}

// WorkspaceFilename is the name of the per-directory config file.
const WorkspaceFilename = ".mdcf.yaml"
