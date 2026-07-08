package converter

import (
	"encoding/xml"
	"fmt"
	"io"
	"strings"

	htmltomd "github.com/JohannesKaufmann/html-to-markdown/v2"
)

// ConvertStorageToMarkdown turns Confluence Storage Format into Markdown.
// It pre-processes the Confluence-specific ac:* / ri:* tags into plain
// HTML / fenced code blocks, then hands the result to html2markdown.
func ConvertStorageToMarkdown(storage string) (string, error) {
	cleaned, err := preprocessStorage(storage)
	if err != nil {
		return "", err
	}
	md, err := htmltomd.ConvertString(cleaned)
	if err != nil {
		return "", fmt.Errorf("html to markdown: %w", err)
	}
	// Collapse runs of >2 blank lines left by the converter.
	for strings.Contains(md, "\n\n\n\n") {
		md = strings.ReplaceAll(md, "\n\n\n\n", "\n\n\n")
	}
	return strings.TrimSpace(md) + "\n", nil
}

// preprocessStorage walks the Confluence Storage Format XML, replacing
// Confluence-specific macros with stand-ins that html-to-markdown can
// handle. The walk is token-based (streaming) to keep it O(n).
func preprocessStorage(storage string) (string, error) {
	// Wrap in a root element so the XML decoder is happy even when the page
	// body contains multiple top-level elements (Confluence does not wrap).
	// Also declare the ac: / ri: namespaces so the decoder doesn't error.
	wrapped := `<root xmlns:ac="http://atlassian.com/content" xmlns:ri="http://atlassian.com/resource/identifier">` +
		storage + `</root>`

	dec := xml.NewDecoder(strings.NewReader(wrapped))
	dec.Strict = false
	dec.AutoClose = xml.HTMLAutoClose
	dec.Entity = xml.HTMLEntity

	var out strings.Builder
	if err := processTokens(dec, &out, ""); err != nil {
		return "", err
	}
	return out.String(), nil
}

// processTokens reads tokens from dec, writing transformed HTML to out.
// stopElem, when non-empty, causes the function to return upon encountering
// the matching end element (so callers can consume a subtree).
func processTokens(dec *xml.Decoder, out *strings.Builder, stopElem string) error {
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return fmt.Errorf("xml decode: %w", err)
		}
		switch t := tok.(type) {
		case xml.StartElement:
			if err := handleStart(dec, out, t); err != nil {
				return err
			}
		case xml.EndElement:
			name := qName(t.Name)
			if name == stopElem || name == "root" {
				return nil
			}
			out.WriteString("</" + name + ">")
		case xml.CharData:
			out.WriteString(escapeXML(string(t)))
		case xml.Comment:
			// drop
		case xml.ProcInst, xml.Directive:
			// drop
		}
	}
}

func qName(n xml.Name) string {
	if n.Space == "ac" || n.Space == "http://atlassian.com/content" {
		return "ac:" + n.Local
	}
	if n.Space == "ri" || n.Space == "http://atlassian.com/resource/identifier" {
		return "ri:" + n.Local
	}
	return n.Local
}

func attr(e xml.StartElement, name string) string {
	for _, a := range e.Attr {
		full := qName(a.Name)
		if full == name || a.Name.Local == name {
			return a.Value
		}
	}
	return ""
}

func handleStart(dec *xml.Decoder, out *strings.Builder, e xml.StartElement) error {
	name := qName(e.Name)
	switch name {
	case "ac:structured-macro":
		return handleMacro(dec, out, e)
	case "ac:image":
		return handleImage(dec, out, e)
	case "ri:attachment", "ri:url":
		// These only appear inside ac:image; handleImage will have consumed
		// them. If we see one bare, drop it and its subtree.
		return skipTo(dec, name)
	default:
		// Pass through as plain HTML. Drop ac:/ri: namespaces; keep others.
		passName := name
		if strings.HasPrefix(passName, "ac:") || strings.HasPrefix(passName, "ri:") {
			// Unknown ac: element — skip the whole subtree rather than
			// emit garbage HTML.
			return skipTo(dec, name)
		}
		writeStart(out, passName, e.Attr)
		return nil
	}
}

// writeStart writes an open tag, excluding ac:/ri: attributes.
func writeStart(out *strings.Builder, name string, attrs []xml.Attr) {
	out.WriteString("<" + name)
	for _, a := range attrs {
		full := qName(a.Name)
		if strings.HasPrefix(full, "ac:") || strings.HasPrefix(full, "ri:") {
			continue
		}
		fmt.Fprintf(out, ` %s="%s"`, a.Name.Local, escapeAttr(a.Value))
	}
	// Self-close void elements so the HTML converter doesn't choke.
	switch name {
	case "br", "hr", "img":
		out.WriteString("/>")
		return
	}
	out.WriteString(">")
}

// skipTo consumes tokens until the matching end of `name`.
func skipTo(dec *xml.Decoder, name string) error {
	depth := 1
	for depth > 0 {
		tok, err := dec.Token()
		if err != nil {
			return err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			if qName(t.Name) == name {
				depth++
			}
		case xml.EndElement:
			if qName(t.Name) == name {
				depth--
			}
		}
	}
	return nil
}

// handleMacro dispatches on ac:name of an ac:structured-macro.
func handleMacro(dec *xml.Decoder, out *strings.Builder, e xml.StartElement) error {
	macroName := attr(e, "ac:name")
	switch macroName {
	case "code":
		return handleCodeMacro(dec, out)
	case "mermaid", "mermaid-cloud":
		return handleMermaidMacro(dec, out)
	case "info":
		return handleAdmonition(dec, out, "ℹ")
	case "note":
		return handleAdmonition(dec, out, "📝")
	case "warning":
		return handleAdmonition(dec, out, "⚠")
	case "expand":
		return handleExpandMacro(dec, out)
	default:
		// Unknown macro — drop the subtree silently.
		return skipTo(dec, "ac:structured-macro")
	}
}

// collectMacro reads inside an ac:structured-macro, extracting parameters,
// plain-text-body, and rich-text-body as raw strings.
type macroBits struct {
	params   map[string]string
	plain    string
	rich     string
	richHTML string
}

func collectMacro(dec *xml.Decoder) (*macroBits, error) {
	m := &macroBits{params: map[string]string{}}
	depth := 1
	for depth > 0 {
		tok, err := dec.Token()
		if err != nil {
			return nil, err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			name := qName(t.Name)
			switch name {
			case "ac:parameter":
				pname := attr(t, "ac:name")
				val, err := readText(dec, name)
				if err != nil {
					return nil, err
				}
				m.params[pname] = val
			case "ac:plain-text-body":
				val, err := readText(dec, name)
				if err != nil {
					return nil, err
				}
				m.plain = val
			case "ac:rich-text-body":
				val, err := readAsHTML(dec, name)
				if err != nil {
					return nil, err
				}
				m.richHTML = val
			case "ac:structured-macro":
				depth++
			default:
				if err := skipTo(dec, name); err != nil {
					return nil, err
				}
			}
		case xml.EndElement:
			if qName(t.Name) == "ac:structured-macro" {
				depth--
			}
		}
	}
	return m, nil
}

// readText reads inner character data of an element and returns it plain.
func readText(dec *xml.Decoder, name string) (string, error) {
	var sb strings.Builder
	depth := 1
	for depth > 0 {
		tok, err := dec.Token()
		if err != nil {
			return "", err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			if qName(t.Name) == name {
				depth++
			}
		case xml.EndElement:
			if qName(t.Name) == name {
				depth--
			}
		case xml.CharData:
			sb.Write(t)
		}
	}
	return sb.String(), nil
}

// readAsHTML serialises the subtree into HTML (used for info/note rich
// text). It strips ac:/ri: namespaced nodes along the way.
func readAsHTML(dec *xml.Decoder, stopName string) (string, error) {
	var sb strings.Builder
	if err := processTokens(dec, &sb, stopName); err != nil {
		return "", err
	}
	return sb.String(), nil
}

func handleCodeMacro(dec *xml.Decoder, out *strings.Builder) error {
	m, err := collectMacro(dec)
	if err != nil {
		return err
	}
	lang := m.params["language"]
	out.WriteString("<pre><code")
	if lang != "" {
		fmt.Fprintf(out, ` class="language-%s"`, escapeAttr(lang))
	}
	out.WriteString(">")
	out.WriteString(escapeXML(m.plain))
	out.WriteString("</code></pre>")
	return nil
}

func handleMermaidMacro(dec *xml.Decoder, out *strings.Builder) error {
	m, err := collectMacro(dec)
	if err != nil {
		return err
	}
	// Confluence's mermaid-cloud macro stores source either in a parameter
	// named "code", in plain-text-body, or in rich-text-body. Try in order.
	source := m.params["code"]
	if source == "" {
		source = m.plain
	}
	if source == "" {
		source = strings.TrimSpace(stripTags(m.richHTML))
	}
	out.WriteString(`<pre><code class="language-mermaid">`)
	out.WriteString(escapeXML(source))
	out.WriteString(`</code></pre>`)
	return nil
}

func handleAdmonition(dec *xml.Decoder, out *strings.Builder, prefix string) error {
	m, err := collectMacro(dec)
	if err != nil {
		return err
	}
	// Emit as a blockquote with the prefix glyph at the top so html2markdown
	// turns it into a > blockquote line.
	fmt.Fprintf(out, "<blockquote><p><strong>%s</strong></p>%s</blockquote>", prefix, m.richHTML)
	return nil
}

func handleExpandMacro(dec *xml.Decoder, out *strings.Builder) error {
	// Per spec: if the expand macro contains mermaid source, strip entirely.
	// We can't easily peek, so we always strip expands (they're UI sugar).
	return skipTo(dec, "ac:structured-macro")
}

func handleImage(dec *xml.Decoder, out *strings.Builder, e xml.StartElement) error {
	alt := attr(e, "ac:alt")
	// Look at children to decide between ri:attachment (skip) and ri:url (emit).
	var (
		urlValue string
		skip     bool
	)
	for {
		tok, err := dec.Token()
		if err != nil {
			return err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			switch qName(t.Name) {
			case "ri:attachment":
				skip = true
				if err := skipTo(dec, "ri:attachment"); err != nil {
					return err
				}
			case "ri:url":
				urlValue = attr(t, "ri:value")
				if err := skipTo(dec, "ri:url"); err != nil {
					return err
				}
			default:
				if err := skipTo(dec, qName(t.Name)); err != nil {
					return err
				}
			}
		case xml.EndElement:
			if qName(t.Name) == "ac:image" {
				if !skip && urlValue != "" {
					fmt.Fprintf(out, `<img src="%s" alt="%s"/>`, escapeAttr(urlValue), escapeAttr(alt))
				}
				return nil
			}
		}
	}
}

// stripTags removes all XML tags from a fragment, leaving text content.
func stripTags(s string) string {
	var sb strings.Builder
	depth := 0
	for _, r := range s {
		switch r {
		case '<':
			depth++
		case '>':
			if depth > 0 {
				depth--
			}
		default:
			if depth == 0 {
				sb.WriteRune(r)
			}
		}
	}
	return sb.String()
}

