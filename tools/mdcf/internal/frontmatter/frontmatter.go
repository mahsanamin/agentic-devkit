// Package frontmatter parses and rewrites YAML frontmatter at the top of
// Markdown files (between --- markers), preserving body content verbatim.
package frontmatter

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// Doc holds parsed frontmatter + the remaining body.
type Doc struct {
	Fields map[string]any
	Body   string
	// Had indicates the source file actually had a frontmatter block.
	Had bool
}

// Parse splits content into frontmatter + body. If no frontmatter block is
// present, returns a Doc with Had=false and the whole input as Body.
func Parse(content string) (*Doc, error) {
	// Normalise CRLF → LF so the regex-free detection below is simple.
	normalised := strings.ReplaceAll(content, "\r\n", "\n")
	if !strings.HasPrefix(normalised, "---\n") {
		return &Doc{Fields: map[string]any{}, Body: content}, nil
	}
	rest := normalised[len("---\n"):]
	idx := strings.Index(rest, "\n---\n")
	if idx < 0 {
		// Trailing close with no newline after — e.g. last line is "---".
		if strings.HasSuffix(rest, "\n---") {
			idx = len(rest) - len("\n---")
			yamlPart := rest[:idx]
			fields := map[string]any{}
			if strings.TrimSpace(yamlPart) != "" {
				if err := yaml.Unmarshal([]byte(yamlPart), &fields); err != nil {
					return nil, fmt.Errorf("parse frontmatter: %w", err)
				}
			}
			return &Doc{Fields: fields, Body: "", Had: true}, nil
		}
		return &Doc{Fields: map[string]any{}, Body: content}, nil
	}
	yamlPart := rest[:idx]
	body := rest[idx+len("\n---\n"):]
	fields := map[string]any{}
	if strings.TrimSpace(yamlPart) != "" {
		if err := yaml.Unmarshal([]byte(yamlPart), &fields); err != nil {
			return nil, fmt.Errorf("parse frontmatter: %w", err)
		}
	}
	return &Doc{Fields: fields, Body: body, Had: true}, nil
}

// Render reassembles the frontmatter + body back into a full file. If fields
// is empty/nil, returns the body alone (no --- markers).
func Render(fields map[string]any, body string) (string, error) {
	if len(fields) == 0 {
		return body, nil
	}
	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(fields); err != nil {
		return "", fmt.Errorf("encode frontmatter: %w", err)
	}
	if err := enc.Close(); err != nil {
		return "", err
	}
	return "---\n" + buf.String() + "---\n" + body, nil
}

// ReadFile reads + parses a Markdown file.
func ReadFile(path string) (*Doc, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return Parse(string(data))
}

// WriteBack rewrites the file atomically with updated frontmatter. It
// preserves the body and any existing keys not listed in updates. A nil or
// empty value in updates is treated as "set this key"; to remove a key the
// caller should delete it from doc.Fields first.
func WriteBack(path string, doc *Doc, updates map[string]any) error {
	if doc.Fields == nil {
		doc.Fields = map[string]any{}
	}
	for k, v := range updates {
		doc.Fields[k] = v
	}
	out, err := Render(doc.Fields, doc.Body)
	if err != nil {
		return err
	}
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, ".mdcf-fm-*")
	if err != nil {
		return fmt.Errorf("create tempfile: %w", err)
	}
	tmpName := tmp.Name()
	if _, err := tmp.WriteString(out); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return fmt.Errorf("write tempfile: %w", err)
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		os.Remove(tmpName)
		return fmt.Errorf("rename %s → %s: %w", tmpName, path, err)
	}
	return nil
}
