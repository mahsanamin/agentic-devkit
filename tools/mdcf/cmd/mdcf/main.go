// Command mdcf is the CLI entrypoint for the Markdown ↔ Confluence tool.
package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/mahsanamin/mdcf/internal/commands"
	"github.com/mahsanamin/mdcf/internal/ui"
)

// Version is overridden at release time via `-ldflags "-X main.Version=…"`.
var Version = "dev"

func main() {
	root := &cobra.Command{
		Use:           "mdcf",
		Short:         "Push Markdown files to Confluence and pull pages back as Markdown",
		Long:          rootLongHelp,
		Version:       Version,
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.SetHelpCommand(newHelpCmd())
	root.AddCommand(
		commands.NewSetupCmd(),
		commands.NewInitCmd(),
		commands.NewPushCmd(),
		commands.NewPullCmd(),
	)
	if err := root.Execute(); err != nil {
		ui.PrintError("%v", err)
		os.Exit(1)
	}
}

// newHelpCmd prints a lipgloss-styled overview that reads nicely in a
// terminal. Cobra's built-in --help is still available on every command.
func newHelpCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "help",
		Short: "Show a styled overview with examples",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Println(ui.Header.Render("mdcf ") + ui.Dim.Render("— Markdown ↔ Confluence"))
			fmt.Println()
			section("Commands", []string{
				"mdcf setup        Configure global credentials (interactive)",
				"mdcf init         Create .mdcf.yaml for this project",
				"mdcf push [path]  Push a .md file or every .md in a directory",
				"mdcf pull <ref>   Fetch a page by title or numeric ID",
				"mdcf help         Show this overview",
			})
			section("Examples", []string{
				"mdcf push docs/onboarding.md",
				"mdcf push docs/          # every .md except _* and README.md",
				"mdcf push -d docs/       # dry-run, no API calls",
				"mdcf pull 123456789      # by page ID",
				`mdcf pull "Runbooks/Alerts"   # by title`,
			})
			section("Config hierarchy", []string{
				"1. ~/.mdcf/config.yaml (global)",
				"2. .mdcf.yaml in any parent directory (workspace)",
				"3. .mdcf.yaml in a deeper directory (overrides)",
			})
			fmt.Println()
			fmt.Println(ui.Dim.Render("Run `mdcf <command> --help` for per-command flags."))
		},
	}
}

func section(title string, lines []string) {
	fmt.Println(ui.Bold.Render(title))
	for _, l := range lines {
		fmt.Println("  " + l)
	}
	fmt.Println()
}

const rootLongHelp = "mdcf (Markdown <-> Confluence) turns local Markdown files into Confluence pages\n" +
	"and pulls pages back into Markdown. It's designed for teams who author docs in\n" +
	"their repo and sync them to a Confluence space.\n" +
	"\n" +
	"Three-level config: ~/.mdcf/config.yaml (global) + .mdcf.yaml files in the\n" +
	"repo (deeper overrides shallower). Run `mdcf setup` once, then `mdcf init`\n" +
	"in the repo/docs root."
