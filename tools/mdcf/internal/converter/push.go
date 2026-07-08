package converter

import (
	"fmt"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/extension"
	extAst "github.com/yuin/goldmark/extension/ast"
	"github.com/yuin/goldmark/parser"
	"github.com/yuin/goldmark/text"
)

// PushOptions tunes how Markdown is lowered to Confluence Storage Format.
// The Mermaid fields are optional; when unset, ```mermaid blocks become
// plain code blocks.
type PushOptions struct {
	// Mermaid, when non-nil, is used to render + attach Mermaid diagrams.
	// When nil (dry run / no pageID yet), Mermaid blocks fall back to the
	// warning macro + code block pattern.
	Mermaid *MermaidRenderer

	// PageID is the Confluence page ID to attach Mermaid SVGs to. Required
	// for Mermaid upload; if empty, renderer falls back.
	PageID string

	// GithubRepoURL is used to add a "View source on GitHub" link under
	// each Mermaid image, if set.
	GithubRepoURL string

	// SourceRelPath is the path of the .md file relative to the repo root,
	// used to build the GitHub source link. May be empty.
	SourceRelPath string
}

// ConvertMarkdown parses markdown, walks the AST, and returns Confluence
// Storage Format XML. It also strips the first top-level H1 (used as the
// page title upstream).
func ConvertMarkdown(md string, opts PushOptions) (string, error) {
	gm := goldmark.New(
		goldmark.WithExtensions(extension.GFM, extension.Table, extension.Strikethrough, extension.TaskList),
		goldmark.WithParserOptions(parser.WithAutoHeadingID()),
	)
	reader := text.NewReader([]byte(md))
	root := gm.Parser().Parse(reader)

	w := &storageWriter{
		src:     []byte(md),
		opts:    opts,
		mermaid: 0,
	}
	w.stripFirstH1(root)

	var buf strings.Builder
	if err := w.walkChildren(&buf, root); err != nil {
		return "", err
	}
	return buf.String(), nil
}

// FirstH1 extracts the first top-level H1 from markdown source, used to
// derive a page title. Returns "" if there is none.
func FirstH1(md string) string {
	gm := goldmark.New(goldmark.WithExtensions(extension.GFM))
	root := gm.Parser().Parse(text.NewReader([]byte(md)))
	var found string
	_ = ast.Walk(root, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
		if !entering {
			return ast.WalkContinue, nil
		}
		if h, ok := n.(*ast.Heading); ok && h.Level == 1 {
			found = extractText(h, []byte(md))
			return ast.WalkStop, nil
		}
		return ast.WalkContinue, nil
	})
	return strings.TrimSpace(found)
}

type storageWriter struct {
	src     []byte
	opts    PushOptions
	mermaid int
}

// stripFirstH1 removes the first H1 from the AST so it doesn't end up
// duplicated inside the Confluence page body (title is rendered separately
// above the body by Confluence).
func (w *storageWriter) stripFirstH1(root ast.Node) {
	for c := root.FirstChild(); c != nil; c = c.NextSibling() {
		if h, ok := c.(*ast.Heading); ok && h.Level == 1 {
			root.RemoveChild(root, c)
			return
		}
	}
}

func (w *storageWriter) walkChildren(buf *strings.Builder, n ast.Node) error {
	for c := n.FirstChild(); c != nil; c = c.NextSibling() {
		if err := w.walkNode(buf, c); err != nil {
			return err
		}
	}
	return nil
}

// walkNode dispatches per node kind. Unknown node kinds are silently
// skipped so that unsupported extensions don't break the push.
func (w *storageWriter) walkNode(buf *strings.Builder, n ast.Node) error {
	switch v := n.(type) {
	case *ast.Document:
		return w.walkChildren(buf, v)
	case *ast.Heading:
		return w.writeHeading(buf, v)
	case *ast.Paragraph:
		buf.WriteString("<p>")
		if err := w.walkChildren(buf, v); err != nil {
			return err
		}
		buf.WriteString("</p>")
	case *ast.Text:
		buf.WriteString(escapeXML(string(v.Segment.Value(w.src))))
		if v.HardLineBreak() {
			buf.WriteString("<br/>")
		} else if v.SoftLineBreak() {
			buf.WriteString(" ")
		}
	case *ast.Emphasis:
		tag := "em"
		if v.Level == 2 {
			tag = "strong"
		}
		buf.WriteString("<" + tag + ">")
		if err := w.walkChildren(buf, v); err != nil {
			return err
		}
		buf.WriteString("</" + tag + ">")
	case *ast.CodeSpan:
		buf.WriteString("<code>")
		if err := w.walkChildren(buf, v); err != nil {
			return err
		}
		buf.WriteString("</code>")
	case *ast.Link:
		buf.WriteString(fmt.Sprintf(`<a href="%s">`, escapeAttr(string(v.Destination))))
		if err := w.walkChildren(buf, v); err != nil {
			return err
		}
		buf.WriteString("</a>")
	case *ast.AutoLink:
		url := string(v.URL(w.src))
		buf.WriteString(fmt.Sprintf(`<a href="%s">%s</a>`, escapeAttr(url), escapeXML(url)))
	case *ast.Image:
		url := string(v.Destination)
		alt := extractText(v, w.src)
		buf.WriteString(fmt.Sprintf(`<ac:image ac:alt="%s"><ri:url ri:value="%s" /></ac:image>`, escapeAttr(alt), escapeAttr(url)))
	case *ast.Blockquote:
		buf.WriteString(`<ac:structured-macro ac:name="info"><ac:rich-text-body>`)
		if err := w.walkChildren(buf, v); err != nil {
			return err
		}
		buf.WriteString(`</ac:rich-text-body></ac:structured-macro>`)
	case *ast.List:
		return w.writeList(buf, v)
	case *ast.ListItem:
		buf.WriteString("<li>")
		if err := w.walkChildren(buf, v); err != nil {
			return err
		}
		buf.WriteString("</li>")
	case *ast.FencedCodeBlock:
		return w.writeFencedCode(buf, v)
	case *ast.CodeBlock:
		return w.writeIndentedCode(buf, v)
	case *ast.ThematicBreak:
		buf.WriteString("<hr/>")
	case *ast.HTMLBlock:
		// Pass raw HTML through; Confluence accepts many HTML tags in storage
		// format. Unsafe tags are filtered by the server.
		for i := 0; i < v.Lines().Len(); i++ {
			s := v.Lines().At(i)
			buf.Write(s.Value(w.src))
		}
	case *ast.RawHTML:
		for i := 0; i < v.Segments.Len(); i++ {
			s := v.Segments.At(i)
			buf.Write(s.Value(w.src))
		}
	case *ast.TextBlock:
		return w.walkChildren(buf, v)
	case *extAst.Table:
		return w.writeTable(buf, v)
	case *extAst.TaskCheckBox:
		if v.IsChecked {
			buf.WriteString("☑ ")
		} else {
			buf.WriteString("☐ ")
		}
	case *extAst.Strikethrough:
		buf.WriteString("<del>")
		if err := w.walkChildren(buf, v); err != nil {
			return err
		}
		buf.WriteString("</del>")
	default:
		// Best effort: descend into unknown block/inline containers.
		return w.walkChildren(buf, v)
	}
	return nil
}

func (w *storageWriter) writeHeading(buf *strings.Builder, h *ast.Heading) error {
	level := h.Level
	if level < 1 {
		level = 1
	}
	if level > 6 {
		level = 6
	}
	fmt.Fprintf(buf, "<h%d>", level)
	if err := w.walkChildren(buf, h); err != nil {
		return err
	}
	fmt.Fprintf(buf, "</h%d>", level)
	return nil
}

func (w *storageWriter) writeList(buf *strings.Builder, l *ast.List) error {
	tag := "ul"
	if l.IsOrdered() {
		tag = "ol"
	}
	buf.WriteString("<" + tag + ">")
	if err := w.walkChildren(buf, l); err != nil {
		return err
	}
	buf.WriteString("</" + tag + ">")
	return nil
}

func (w *storageWriter) writeFencedCode(buf *strings.Builder, c *ast.FencedCodeBlock) error {
	lang := string(c.Language(w.src))
	source := readLines(c, w.src)
	if strings.EqualFold(strings.TrimSpace(lang), "mermaid") {
		return w.writeMermaid(buf, source)
	}
	return w.writeCodeMacro(buf, lang, source)
}

func (w *storageWriter) writeIndentedCode(buf *strings.Builder, c *ast.CodeBlock) error {
	return w.writeCodeMacro(buf, "", readLines(c, w.src))
}

func (w *storageWriter) writeCodeMacro(buf *strings.Builder, lang, source string) error {
	buf.WriteString(`<ac:structured-macro ac:name="code">`)
	if lang != "" {
		fmt.Fprintf(buf, `<ac:parameter ac:name="language">%s</ac:parameter>`, escapeXML(lang))
	}
	buf.WriteString(`<ac:parameter ac:name="linenumbers">true</ac:parameter>`)
	fmt.Fprintf(buf, `<ac:plain-text-body><![CDATA[%s]]></ac:plain-text-body>`, source)
	buf.WriteString(`</ac:structured-macro>`)
	return nil
}

func (w *storageWriter) writeMermaid(buf *strings.Builder, source string) error {
	w.mermaid++
	if w.opts.Mermaid == nil || w.opts.PageID == "" {
		// Dry run or pre-page-id pass: emit fallback so the document still
		// makes sense downstream.
		buf.WriteString(FallbackMacro(source, "renderer unavailable in this pass"))
		return nil
	}
	svg, err := w.opts.Mermaid.RenderSVG(source)
	if err != nil {
		buf.WriteString(FallbackMacro(source, err.Error()))
		return nil
	}
	filename, err := w.opts.Mermaid.Upload(w.opts.PageID, w.mermaid, svg)
	if err != nil {
		buf.WriteString(FallbackMacro(source, err.Error()))
		return nil
	}
	buf.WriteString(AttachmentImageMacro(filename))
	if link := GithubSourceLink(w.opts.GithubRepoURL, w.opts.SourceRelPath); link != "" {
		buf.WriteString(link)
	}
	return nil
}

func (w *storageWriter) writeTable(buf *strings.Builder, t *extAst.Table) error {
	buf.WriteString("<table><tbody>")
	for row := t.FirstChild(); row != nil; row = row.NextSibling() {
		buf.WriteString("<tr>")
		for cell := row.FirstChild(); cell != nil; cell = cell.NextSibling() {
			tag := "td"
			if _, ok := row.(*extAst.TableHeader); ok {
				tag = "th"
			}
			buf.WriteString("<" + tag + ">")
			if err := w.walkChildren(buf, cell); err != nil {
				return err
			}
			buf.WriteString("</" + tag + ">")
		}
		buf.WriteString("</tr>")
	}
	buf.WriteString("</tbody></table>")
	return nil
}

// readLines concatenates the raw source lines of a code block verbatim.
func readLines(n ast.Node, src []byte) string {
	lines := n.Lines()
	var sb strings.Builder
	for i := 0; i < lines.Len(); i++ {
		seg := lines.At(i)
		sb.Write(seg.Value(src))
	}
	return sb.String()
}

// extractText concatenates Text segments beneath a node (best-effort plain
// text, used for image alt + heading titles).
func extractText(n ast.Node, src []byte) string {
	var sb strings.Builder
	_ = ast.Walk(n, func(c ast.Node, entering bool) (ast.WalkStatus, error) {
		if !entering {
			return ast.WalkContinue, nil
		}
		if t, ok := c.(*ast.Text); ok {
			sb.Write(t.Segment.Value(src))
		}
		return ast.WalkContinue, nil
	})
	return sb.String()
}

func escapeXML(s string) string {
	r := strings.NewReplacer(
		"&", "&amp;",
		"<", "&lt;",
		">", "&gt;",
	)
	return r.Replace(s)
}

func escapeAttr(s string) string {
	r := strings.NewReplacer(
		"&", "&amp;",
		"<", "&lt;",
		">", "&gt;",
		`"`, "&quot;",
	)
	return r.Replace(s)
}

// KebabCase converts a title like "My Fancy Page!" to "my-fancy-page".
// Exported here since push/pull both use it.
func KebabCase(s string) string {
	var sb strings.Builder
	lastDash := true
	for _, r := range s {
		switch {
		case r >= 'A' && r <= 'Z':
			sb.WriteRune(r + 32)
			lastDash = false
		case (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'):
			sb.WriteRune(r)
			lastDash = false
		default:
			if !lastDash {
				sb.WriteByte('-')
				lastDash = true
			}
		}
	}
	return strings.Trim(sb.String(), "-")
}

