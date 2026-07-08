// Package converter translates between Markdown and Confluence Storage
// Format. mermaid.go is the subsystem that handles ```mermaid code blocks:
// it asks Kroki to render SVG, uploads the SVG as a Confluence attachment,
// and emits the ac:image tag that references it.
package converter

import (
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/mahsanamin/mdcf/internal/confluence"
)

// MermaidRenderer holds the Kroki endpoint and the Confluence client used
// to upload attachments. The Client may be nil during dry-run / pre-flight
// conversion — in that case we return the fallback (code block + warning).
type MermaidRenderer struct {
	KrokiURL   string // e.g. https://kroki.io
	HTTPClient *http.Client
	Confluence *confluence.Client // nil during dry-run or when pageID unknown
}

// NewMermaidRenderer builds the default renderer pointed at kroki.io with
// a 10 second timeout.
func NewMermaidRenderer(client *confluence.Client) *MermaidRenderer {
	return &MermaidRenderer{
		KrokiURL:   "https://kroki.io",
		HTTPClient: &http.Client{Timeout: 10 * time.Second},
		Confluence: client,
	}
}

// RenderSVG asks Kroki to turn Mermaid source into SVG bytes.
func (r *MermaidRenderer) RenderSVG(source string) ([]byte, error) {
	encoded := base64.URLEncoding.EncodeToString([]byte(source))
	// Kroki also supports deflate-then-base64url, but plain base64url works
	// for all but very large diagrams and keeps the client code simple.
	url := r.KrokiURL + "/mermaid/svg/" + encoded
	resp, err := r.HTTPClient.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		msg := string(body)
		if len(msg) > 300 {
			msg = msg[:300] + "…"
		}
		return nil, fmt.Errorf("kroki %d: %s", resp.StatusCode, msg)
	}
	return io.ReadAll(resp.Body)
}

// Upload uploads the svg bytes as diagram-{index}.svg to the given page,
// returning the filename used.
func (r *MermaidRenderer) Upload(pageID string, index int, svg []byte) (string, error) {
	if r.Confluence == nil {
		return "", fmt.Errorf("no confluence client (dry run?)")
	}
	filename := fmt.Sprintf("diagram-%d.svg", index)
	_, err := r.Confluence.UploadAttachment(pageID, filename, "image/svg+xml", svg)
	if err != nil {
		return "", err
	}
	return filename, nil
}

// FallbackMacro returns the Confluence Storage Format snippet used when
// Kroki is unreachable: a warning macro followed by the raw source as a
// code block so editors can still see what the author wrote.
func FallbackMacro(source, errMsg string) string {
	// Note the spec: do not fail push; emit warning + code block.
	return fmt.Sprintf(
		`<ac:structured-macro ac:name="warning"><ac:rich-text-body><p>Mermaid diagram could not be rendered: %s</p></ac:rich-text-body></ac:structured-macro>`+
			`<ac:structured-macro ac:name="code"><ac:parameter ac:name="language">text</ac:parameter><ac:plain-text-body><![CDATA[%s]]></ac:plain-text-body></ac:structured-macro>`,
		escapeXML(errMsg), source,
	)
}

// AttachmentImageMacro returns the ac:image tag referencing a file already
// attached to the page.
func AttachmentImageMacro(filename string) string {
	return fmt.Sprintf(`<ac:image><ri:attachment ri:filename="%s" /></ac:image>`, filename)
}

// GithubSourceLink returns a markdown-rendered-as-HTML link to the Mermaid
// source on GitHub, appended under the image. repoURL is the .git-less
// https URL, relPath is the path to the .md inside the repo. Empty string
// if repoURL is unset.
func GithubSourceLink(repoURL, relPath string) string {
	if repoURL == "" {
		return ""
	}
	path := relPath
	if path == "" {
		return fmt.Sprintf(`<p><em>📎 <a href="%s">View Mermaid source on GitHub</a></em></p>`, repoURL)
	}
	return fmt.Sprintf(`<p><em>📎 <a href="%s/blob/main/%s">View Mermaid source on GitHub</a></em></p>`, repoURL, path)
}
