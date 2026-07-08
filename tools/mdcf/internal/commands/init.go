package commands

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/charmbracelet/huh"
	"github.com/spf13/cobra"

	"github.com/mahsanamin/mdcf/internal/config"
	"github.com/mahsanamin/mdcf/internal/ui"
)

// NewInitCmd returns the `mdcf init` command — creates a .mdcf.yaml in CWD
// after verifying that the chosen space + parent page exist.
func NewInitCmd() *cobra.Command {
	var force bool
	cmd := &cobra.Command{
		Use:   "init",
		Short: "Create a .mdcf.yaml workspace config in the current directory",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runInit(force)
		},
	}
	cmd.Flags().BoolVar(&force, "force", false, "overwrite any existing .mdcf.yaml")
	return cmd
}

func runInit(force bool) error {
	if _, err := config.LoadGlobal(); err != nil {
		return fmt.Errorf("run `mdcf setup` first: %w", err)
	}

	cwd, err := os.Getwd()
	if err != nil {
		return err
	}
	target := filepath.Join(cwd, config.WorkspaceFilename)
	if _, err := os.Stat(target); err == nil && !force {
		return fmt.Errorf("%s already exists (use --force to overwrite)", target)
	}

	var spaceKey, parentPath, repoURL string
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Space key").
				Description("The 2–10 char key, e.g. ENG or DOCS").
				Value(&spaceKey).
				Validate(nonEmpty("space_key")),
			huh.NewInput().
				Title("Parent page path").
				Description(`Slash-separated, e.g. "Engineering/Backend"`).
				Value(&parentPath).
				Validate(nonEmpty("parent_page_path")),
			huh.NewInput().
				Title("GitHub repo URL (optional)").
				Description("Used to add source links under Mermaid diagrams. Leave blank to skip.").
				Value(&repoURL),
		),
	)
	if err := form.Run(); err != nil {
		return err
	}

	// Verify space + parent page exist.
	r, err := config.Resolve(cwd)
	if err != nil {
		return err
	}
	r.SpaceKey = spaceKey
	client := newClient(r)
	if err := ui.WithSpinner("Verifying space…", func() error {
		_, err := client.GetSpace()
		return err
	}); err != nil {
		return fmt.Errorf("space %q not reachable: %w", spaceKey, err)
	}
	var parentID string
	if err := ui.WithSpinner("Verifying parent page…", func() error {
		p, err := client.FindPageByPath(parentPath)
		if err != nil {
			return err
		}
		parentID = p.ID
		return nil
	}); err != nil {
		return fmt.Errorf("parent page %q not found: %w", parentPath, err)
	}
	ui.PrintSuccess("Space + parent verified (parent id %s).", parentID)

	w := &config.Workspace{
		SpaceKey:       strPtr(spaceKey),
		ParentPagePath: strPtr(parentPath),
	}
	if repoURL != "" {
		w.GithubRepoURL = strPtr(repoURL)
	}
	if err := config.SaveWorkspace(target, w); err != nil {
		return err
	}
	ui.PrintSuccess("Saved %s", target)
	return nil
}

func strPtr(s string) *string { return &s }
