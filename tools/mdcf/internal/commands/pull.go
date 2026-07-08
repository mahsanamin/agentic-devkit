package commands

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	"github.com/spf13/cobra"

	"github.com/mahsanamin/mdcf/internal/confluence"
	"github.com/mahsanamin/mdcf/internal/converter"
	"github.com/mahsanamin/mdcf/internal/frontmatter"
	"github.com/mahsanamin/mdcf/internal/ui"
)

// NewPullCmd returns the `mdcf pull` command — fetches a Confluence page by
// title or numeric ID and writes it as Markdown in the current directory.
func NewPullCmd() *cobra.Command {
	var (
		output   string
		spaceKey string
	)
	cmd := &cobra.Command{
		Use:   "pull <title-or-id>",
		Short: "Fetch a Confluence page and save it as Markdown",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return runPull(args[0], output, spaceKey)
		},
	}
	cmd.Flags().StringVarP(&output, "output", "o", "", "output file (default: <kebab-title>.md in CWD)")
	cmd.Flags().StringVar(&spaceKey, "space", "", "override space key from .mdcf.yaml")
	return cmd
}

func runPull(arg, outputArg, spaceOverride string) error {
	cwd, err := os.Getwd()
	if err != nil {
		return err
	}
	resolved, err := mustResolveConfig(cwd)
	if err != nil {
		return err
	}
	if spaceOverride != "" {
		resolved.SpaceKey = spaceOverride
	}
	client := newClient(resolved)

	var page *confluence.Page
	if _, err := strconv.Atoi(arg); err == nil {
		if err := ui.WithSpinner("Fetching page by ID…", func() error {
			p, err := client.GetPageByID(arg, "body.storage,version,space,metadata.labels,_links")
			if err != nil {
				return err
			}
			page = p
			return nil
		}); err != nil {
			return err
		}
	} else {
		if resolved.SpaceKey == "" {
			return errors.New("title-based pull requires space_key — run `mdcf init` or pass --space")
		}
		if err := ui.WithSpinner("Searching for page by title…", func() error {
			p, err := client.FindPageByTitle(arg, "")
			if err != nil {
				return err
			}
			if p == nil {
				return fmt.Errorf("no page found titled %q in space %q", arg, resolved.SpaceKey)
			}
			// Re-fetch with body expansion.
			detailed, err := client.GetPageByID(p.ID, "body.storage,version,space,metadata.labels,_links")
			if err != nil {
				return err
			}
			page = detailed
			return nil
		}); err != nil {
			return err
		}
	}

	if page.Body == nil || page.Body.Storage.Value == "" {
		return fmt.Errorf("page %s has no storage-format body", page.ID)
	}

	md, err := converter.ConvertStorageToMarkdown(page.Body.Storage.Value)
	if err != nil {
		return err
	}

	// Collect labels for frontmatter if the expand brought them back.
	var labels []string
	if page.Metadata != nil && page.Metadata.Labels != nil {
		for _, l := range page.Metadata.Labels.Results {
			labels = append(labels, l.Name)
		}
	}

	fm := map[string]any{
		"title":              page.Title,
		"confluence_page_id": page.ID,
	}
	if len(labels) > 0 {
		fm["labels"] = labels
	}

	outPath := outputArg
	if outPath == "" {
		outPath = filepath.Join(cwd, converter.KebabCase(page.Title)+".md")
	}

	rendered, err := frontmatter.Render(fm, "# "+page.Title+"\n\n"+md)
	if err != nil {
		return err
	}
	if err := os.WriteFile(outPath, []byte(rendered), 0o644); err != nil {
		return err
	}
	ui.PrintSuccess("Saved %s", outPath)
	return nil
}
