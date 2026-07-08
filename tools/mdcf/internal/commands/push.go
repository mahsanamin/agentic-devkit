package commands

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/mahsanamin/mdcf/internal/config"
	"github.com/mahsanamin/mdcf/internal/confluence"
	"github.com/mahsanamin/mdcf/internal/converter"
	"github.com/mahsanamin/mdcf/internal/frontmatter"
	"github.com/mahsanamin/mdcf/internal/ui"
)

// NewPushCmd returns the `mdcf push` command — uploads one or many markdown
// files to Confluence, creating pages on first push and updating in place
// on subsequent pushes.
func NewPushCmd() *cobra.Command {
	var (
		dryRun    bool
		verbose   bool
		titleArg  string
		parentArg string
	)
	cmd := &cobra.Command{
		Use:   "push [path]",
		Short: "Push Markdown file(s) to Confluence",
		Long: `Push a single .md file or every .md under a directory.

Files prefixed with "_" and any README.md are skipped in directory mode.
The page title comes from the frontmatter "title" field, then the first
H1 in the body, then the filename stem.`,
		Args: cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			target := "."
			if len(args) == 1 {
				target = args[0]
			}
			return runPush(pushOpts{
				Target:  target,
				DryRun:  dryRun,
				Verbose: verbose,
				Title:   titleArg,
				Parent:  parentArg,
			})
		},
	}
	cmd.Flags().BoolVarP(&dryRun, "dry-run", "d", false, "convert but do not call Confluence")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "print converted storage format and progress details")
	cmd.Flags().StringVar(&titleArg, "title", "", "override title (single file only)")
	cmd.Flags().StringVar(&parentArg, "parent", "", "override parent page ID")
	return cmd
}

type pushOpts struct {
	Target  string
	DryRun  bool
	Verbose bool
	Title   string
	Parent  string
}

func runPush(opts pushOpts) error {
	info, err := os.Stat(opts.Target)
	if err != nil {
		return fmt.Errorf("target %s: %w", opts.Target, err)
	}
	var files []string
	if info.IsDir() {
		if opts.Title != "" {
			return errors.New("--title is only valid when pushing a single file")
		}
		files, err = collectMarkdown(opts.Target)
		if err != nil {
			return err
		}
		if len(files) == 0 {
			ui.PrintWarning("no Markdown files found under %s", opts.Target)
			return nil
		}
	} else {
		files = []string{opts.Target}
	}

	var succeeded, failed int
	for _, f := range files {
		if err := pushFile(f, opts); err != nil {
			ui.PrintError("%s: %v", f, err)
			failed++
			continue
		}
		succeeded++
	}
	ui.PrintSummary(succeeded, failed)
	if failed > 0 {
		return fmt.Errorf("%d file(s) failed", failed)
	}
	return nil
}

// collectMarkdown walks dir (non-recursive root + immediate subtrees) and
// returns *.md paths, skipping _-prefixed files and README.md.
func collectMarkdown(root string) ([]string, error) {
	var out []string
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			// Skip hidden directories and node_modules-like clutter.
			base := filepath.Base(path)
			if path != root && (strings.HasPrefix(base, ".") || base == "node_modules" || base == "vendor") {
				return filepath.SkipDir
			}
			return nil
		}
		name := d.Name()
		if !strings.HasSuffix(strings.ToLower(name), ".md") {
			return nil
		}
		if strings.HasPrefix(name, "_") || strings.EqualFold(name, "README.md") {
			return nil
		}
		out = append(out, path)
		return nil
	})
	return out, err
}

func pushFile(path string, opts pushOpts) error {
	absFile, err := absPath(path)
	if err != nil {
		return err
	}
	fileDir := filepath.Dir(absFile)

	resolved, err := mustResolveConfig(fileDir)
	if err != nil {
		return err
	}
	if resolved.SpaceKey == "" {
		return errors.New("space_key not set (run `mdcf init` in the project)")
	}

	doc, err := frontmatter.ReadFile(absFile)
	if err != nil {
		return err
	}

	title := pickTitle(doc, opts.Title, absFile)
	pageID := stringField(doc.Fields, "confluence_page_id")
	parentID := opts.Parent
	client := newClient(resolved)

	// Resolve parent from config if no override + no existing pageID.
	if parentID == "" && pageID == "" {
		var resolvedParent *confluence.Page
		if err := ui.WithSpinner("Looking up parent page…", func() error {
			p, err := client.FindPageByPath(resolved.ParentPagePath)
			if err != nil {
				return err
			}
			resolvedParent = p
			return nil
		}); err != nil {
			return err
		}
		parentID = resolvedParent.ID
	}

	// First pass: convert without Mermaid upload (we may not have pageID
	// yet). If the file has no Mermaid blocks, this is the only pass.
	firstOpts := converter.PushOptions{
		GithubRepoURL: resolved.GithubRepoURL,
		SourceRelPath: relToRepoRoot(absFile, resolved.GithubRepoURL),
	}
	storage, err := converter.ConvertMarkdown(doc.Body, firstOpts)
	if err != nil {
		return err
	}

	if opts.DryRun {
		if opts.Verbose {
			fmt.Println(storage)
		} else {
			ui.PrintDim("dry-run: would push %q (%d chars)", title, len(storage))
		}
		return nil
	}

	// Upsert page to obtain a pageID for Mermaid attachments.
	var page *confluence.Page
	if pageID != "" {
		if err := ui.WithSpinner("Updating page…", func() error {
			cur, err := client.GetPageByID(pageID, "version")
			if err != nil {
				var nf *confluence.NotFoundError
				if errors.As(err, &nf) {
					ui.PrintWarning("page %s not found, creating fresh", pageID)
					newPage, err := client.CreatePage(title, parentID, storage)
					if err != nil {
						return err
					}
					page = newPage
					return nil
				}
				return err
			}
			updated, err := client.UpdatePage(pageID, title, storage, cur.Version.Number)
			if err != nil {
				return err
			}
			page = updated
			return nil
		}); err != nil {
			return err
		}
	} else {
		// Search first: page may exist under parent with this title.
		if err := ui.WithSpinner("Searching for existing page…", func() error {
			found, err := client.FindPageByTitle(title, parentID)
			if err != nil {
				return err
			}
			if found != nil {
				updated, err := client.UpdatePage(found.ID, title, storage, found.Version.Number)
				if err != nil {
					return err
				}
				page = updated
				return nil
			}
			created, err := client.CreatePage(title, parentID, storage)
			if err != nil {
				return err
			}
			page = created
			return nil
		}); err != nil {
			return err
		}
	}

	// Second pass (if the body had Mermaid): re-render with the real pageID
	// so attachments land on the page we just wrote, then update.
	if containsMermaid(doc.Body) {
		secondOpts := firstOpts
		secondOpts.Mermaid = converter.NewMermaidRenderer(client)
		secondOpts.PageID = page.ID
		storage2, err := converter.ConvertMarkdown(doc.Body, secondOpts)
		if err != nil {
			return err
		}
		if storage2 != storage {
			if err := ui.WithSpinner("Uploading Mermaid diagrams…", func() error {
				refreshed, err := client.GetPageByID(page.ID, "version")
				if err != nil {
					return err
				}
				updated, err := client.UpdatePage(page.ID, title, storage2, refreshed.Version.Number)
				if err != nil {
					return err
				}
				page = updated
				return nil
			}); err != nil {
				return err
			}
		}
	}

	// Persist confluence_page_id back to frontmatter if missing or changed.
	if stringField(doc.Fields, "confluence_page_id") != page.ID {
		if err := frontmatter.WriteBack(absFile, doc, map[string]any{
			"confluence_page_id": page.ID,
			"title":              title,
		}); err != nil {
			return fmt.Errorf("write frontmatter: %w", err)
		}
	}

	// Apply labels from frontmatter, if any.
	if labels := stringSliceField(doc.Fields, "labels"); len(labels) > 0 {
		if err := client.AddLabels(page.ID, labels); err != nil {
			ui.PrintWarning("label update failed: %v", err)
		}
	}

	ui.PrintSuccess("%s", title)
	ui.PrintURL("  →", client.PageURL(page))
	return nil
}

// pickTitle resolves title precedence: --title flag → frontmatter.title →
// first H1 → filename stem.
func pickTitle(doc *frontmatter.Doc, override, path string) string {
	if strings.TrimSpace(override) != "" {
		return strings.TrimSpace(override)
	}
	if v := stringField(doc.Fields, "title"); v != "" {
		return v
	}
	if h1 := converter.FirstH1(doc.Body); h1 != "" {
		return h1
	}
	base := filepath.Base(path)
	return strings.TrimSuffix(base, filepath.Ext(base))
}

// stringField returns a string value from the frontmatter map, converting
// ints → strings for convenience (Confluence page IDs often come back as
// numbers when the file was hand-edited).
func stringField(m map[string]any, key string) string {
	if m == nil {
		return ""
	}
	switch v := m[key].(type) {
	case string:
		return v
	case int:
		return fmt.Sprintf("%d", v)
	case int64:
		return fmt.Sprintf("%d", v)
	case float64:
		return fmt.Sprintf("%.0f", v)
	default:
		return ""
	}
}

// stringSliceField returns a []string value from the frontmatter map.
func stringSliceField(m map[string]any, key string) []string {
	if m == nil {
		return nil
	}
	raw, ok := m[key]
	if !ok {
		return nil
	}
	slice, ok := raw.([]any)
	if !ok {
		return nil
	}
	var out []string
	for _, v := range slice {
		if s, ok := v.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func containsMermaid(md string) bool {
	return strings.Contains(md, "```mermaid") || strings.Contains(md, "~~~mermaid")
}

// relToRepoRoot computes the source file's path inside the repo for the
// GitHub source link. If we can't figure it out, returns empty string.
func relToRepoRoot(absFile, repoURL string) string {
	if repoURL == "" {
		return ""
	}
	// Walk up from the file looking for a .git directory.
	dir := filepath.Dir(absFile)
	for {
		if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
			rel, err := filepath.Rel(dir, absFile)
			if err != nil {
				return ""
			}
			return filepath.ToSlash(rel)
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

// ensure config package stays imported (used via mustResolveConfig).
var _ = config.WorkspaceFilename
