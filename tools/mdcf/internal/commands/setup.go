// Package commands holds the implementations of each cobra subcommand.
// Each file defines a NewXxxCmd() constructor returning a *cobra.Command.
package commands

import (
	"errors"
	"fmt"
	"os/exec"
	"runtime"
	"strings"

	"github.com/charmbracelet/huh"
	"github.com/spf13/cobra"

	"github.com/mahsanamin/mdcf/internal/config"
	"github.com/mahsanamin/mdcf/internal/confluence"
	"github.com/mahsanamin/mdcf/internal/ui"
)

const tokenPageURL = "https://id.atlassian.com/manage-profile/security/api-tokens"

// setupFlags carries the parsed CLI flag values for runSetup.
type setupFlags struct {
	force  bool
	open   bool // --open  (force yes, skip the confirm prompt)
	noOpen bool // --no-open (force no, skip the confirm prompt)
}

// NewSetupCmd returns the `mdcf setup` command — an interactive wizard
// that writes ~/.mdcf/config.yaml after probing the provided credentials.
func NewSetupCmd() *cobra.Command {
	var flags setupFlags
	cmd := &cobra.Command{
		Use:   "setup",
		Short: "Interactive wizard to configure global credentials",
		Long: `Walks through the three values needed to talk to Confluence Cloud:
  base_url (your *.atlassian.net root), email, and API token.

Offers to open the Atlassian token page in your browser, then stores the
token in ~/.mdcf/config.yaml with mode 0600. If you prefer env-based secret
management, type ${MDCF_API_TOKEN} instead of the raw token.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runSetup(flags)
		},
	}
	cmd.Flags().BoolVar(&flags.force, "force", false, "overwrite any existing global config")
	cmd.Flags().BoolVar(&flags.open, "open", false, "always open the token page in your browser (skip the prompt)")
	cmd.Flags().BoolVar(&flags.noOpen, "no-open", false, "never open a browser (skip the prompt)")
	return cmd
}

func runSetup(flags setupFlags) error {
	if flags.open && flags.noOpen {
		return errors.New("--open and --no-open are mutually exclusive")
	}

	path, err := config.GlobalPath()
	if err != nil {
		return err
	}
	if !flags.force {
		if existing, err := config.LoadGlobal(); err == nil && existing != nil {
			return fmt.Errorf("global config already exists at %s (use --force to overwrite)", path)
		}
	}

	// Step 1: base URL + email (plain inputs).
	var baseURL, email string
	if err := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Confluence base URL").
				Description("Root only — https://your-org.atlassian.net (no /wiki, no space)").
				Value(&baseURL).
				Validate(validateBaseURL),
			huh.NewInput().
				Title("Email").
				Description("Your Atlassian account email").
				Value(&email).
				Validate(nonEmpty("email")),
		),
	).Run(); err != nil {
		return err
	}

	// Step 2: offer to open the token page. Skip the prompt if --open or
	// --no-open was passed explicitly.
	openBrowser := flags.open
	if !flags.open && !flags.noOpen {
		var confirm bool
		if err := huh.NewConfirm().
			Title("Open the Atlassian API token page in your browser?").
			Description(tokenPageURL).
			Affirmative("Open it").
			Negative("I'll handle it").
			Value(&confirm).
			Run(); err != nil {
			return err
		}
		openBrowser = confirm
	}
	if openBrowser {
		if err := openInBrowser(tokenPageURL); err != nil {
			ui.PrintWarning("could not open browser: %v", err)
			ui.PrintDim("Open manually: %s", tokenPageURL)
		} else {
			ui.PrintDim("Opened %s", tokenPageURL)
		}
	}

	// Step 3: token prompt (password-masked).
	var token string
	if err := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("API token").
				Description("Paste the token you just created, or type ${MDCF_API_TOKEN} to read from env").
				Value(&token).
				EchoMode(huh.EchoModePassword).
				Validate(nonEmpty("api_token")),
		),
	).Run(); err != nil {
		return err
	}

	// Verify the credentials work before touching disk.
	client := confluence.New(baseURL, email, resolveIfEnvRef(token), "")
	if err := ui.WithSpinner("Testing connection to Confluence…", client.Ping); err != nil {
		ui.PrintError("connection failed: %v", err)
		return err
	}
	ui.PrintSuccess("Connected.")

	if err := config.SaveGlobal(&config.Global{
		BaseURL:  baseURL,
		Email:    email,
		APIToken: token,
	}); err != nil {
		return err
	}
	ui.PrintSuccess("Saved %s (mode 0600)", path)
	ui.PrintDim("Rotate anytime with `mdcf setup --force`.")
	return nil
}

// validateBaseURL ensures the URL looks like an Atlassian Cloud root.
func validateBaseURL(s string) error {
	s = strings.TrimSpace(s)
	if s == "" {
		return errors.New("base_url is required")
	}
	if !strings.HasPrefix(s, "https://") {
		return errors.New("must start with https://")
	}
	if !strings.Contains(s, ".atlassian.net") {
		return errors.New("must be an *.atlassian.net URL")
	}
	if strings.Contains(s, "/wiki") || strings.Count(s, "/") > 2 {
		return errors.New("use the root URL only — drop /wiki and any path")
	}
	return nil
}

// nonEmpty returns a validator that rejects empty/whitespace-only values.
func nonEmpty(field string) func(string) error {
	return func(s string) error {
		if strings.TrimSpace(s) == "" {
			return fmt.Errorf("%s is required", field)
		}
		return nil
	}
}

// resolveIfEnvRef expands ${VAR} style references for the live ping call.
// The unexpanded form is still what ultimately gets written to disk.
func resolveIfEnvRef(s string) string {
	if strings.HasPrefix(s, "${") && strings.HasSuffix(s, "}") {
		return expandEnv(s)
	}
	return s
}

// openInBrowser launches the user's default browser to url. macOS uses the
// native `open` command, Linux uses `xdg-open`, Windows uses `rundll32`.
func openInBrowser(url string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "linux":
		cmd = exec.Command("xdg-open", url)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	default:
		return fmt.Errorf("unsupported OS: %s", runtime.GOOS)
	}
	return cmd.Start()
}
