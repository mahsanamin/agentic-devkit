// Package ui centralises terminal output styling (lipgloss) and progress
// feedback (spinners) so every command has a consistent look.
package ui

import (
	"fmt"
	"os"
	"time"

	"github.com/charmbracelet/huh/spinner"
	"github.com/charmbracelet/lipgloss"
)

var (
	Success = lipgloss.NewStyle().Foreground(lipgloss.Color("#10B981")).Bold(true) // green
	Error   = lipgloss.NewStyle().Foreground(lipgloss.Color("#EF4444")).Bold(true) // red
	Warning = lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Bold(true) // amber
	Dim     = lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280"))            // grey
	URL     = lipgloss.NewStyle().Foreground(lipgloss.Color("#3B82F6")).Underline(true)
	Bold    = lipgloss.NewStyle().Bold(true)
	Header  = lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true) // cyan
)

// PrintSuccess writes "✓ msg" in green to stdout.
func PrintSuccess(format string, args ...any) {
	fmt.Fprintln(os.Stdout, Success.Render("✓ ")+fmt.Sprintf(format, args...))
}

// PrintError writes "✗ msg" in red to stderr.
func PrintError(format string, args ...any) {
	fmt.Fprintln(os.Stderr, Error.Render("✗ ")+fmt.Sprintf(format, args...))
}

// PrintWarning writes "⚠ msg" in yellow to stderr.
func PrintWarning(format string, args ...any) {
	fmt.Fprintln(os.Stderr, Warning.Render("⚠ ")+fmt.Sprintf(format, args...))
}

// PrintURL writes a labelled URL line. label is dimmed, url is underlined blue.
func PrintURL(label, url string) {
	fmt.Fprintln(os.Stdout, Dim.Render(label+": ")+URL.Render(url))
}

// PrintHeader writes a bold cyan header.
func PrintHeader(format string, args ...any) {
	fmt.Fprintln(os.Stdout, Header.Render(fmt.Sprintf(format, args...)))
}

// PrintDim writes a greyed-out message to stdout.
func PrintDim(format string, args ...any) {
	fmt.Fprintln(os.Stdout, Dim.Render(fmt.Sprintf(format, args...)))
}

// PrintSummary prints a "N succeeded, M failed" line, green if no failures.
func PrintSummary(succeeded, failed int) {
	total := succeeded + failed
	if failed == 0 {
		PrintSuccess("%d/%d succeeded", succeeded, total)
		return
	}
	fmt.Fprintln(os.Stderr, Warning.Render(fmt.Sprintf("⚠ %d/%d succeeded, %d failed", succeeded, total, failed)))
}

// WithSpinner runs fn while showing a spinner with msg. If stdout is not a
// TTY or fn is fast enough, the spinner silently degrades. Any error from fn
// is returned unchanged.
func WithSpinner(msg string, fn func() error) error {
	var fnErr error
	action := func() {
		fnErr = fn()
	}
	if err := spinner.New().Title(msg).Action(action).Run(); err != nil {
		// Fall back to running the action directly if the spinner itself
		// errored (e.g. non-TTY in some environments).
		if fnErr == nil {
			action()
		}
		_ = err
	}
	return fnErr
}

// Sleep is a tiny helper that lets the caller force a short pause (used to
// flush spinner output in some flows).
func Sleep(d time.Duration) { time.Sleep(d) }
