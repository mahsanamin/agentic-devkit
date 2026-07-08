// Package confluence is a thin client for the Confluence Cloud REST API.
// It targets the /wiki/rest/api v1 endpoints used by the Cloud product.
package confluence

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const userAgent = "mdcf/1.0"

// Client is a Confluence REST API client bound to a single base URL + space.
type Client struct {
	baseURL  string // e.g. https://org.atlassian.net (no /wiki)
	email    string
	token    string
	spaceKey string
	http     *http.Client
}

// NotFoundError signals a 404 from the API. Callers (notably push) treat
// stale confluence_page_id as a recoverable case by creating fresh.
type NotFoundError struct {
	URL string
}

func (e *NotFoundError) Error() string { return "not found: " + e.URL }

// New builds a Client. spaceKey may be empty for operations that don't need
// a space (e.g. fetching a page by numeric ID).
func New(baseURL, email, token, spaceKey string) *Client {
	return &Client{
		baseURL:  strings.TrimRight(baseURL, "/"),
		email:    email,
		token:    token,
		spaceKey: spaceKey,
		http:     &http.Client{Timeout: 30 * time.Second},
	}
}

// SpaceKey returns the space this client is bound to (may be "").
func (c *Client) SpaceKey() string { return c.spaceKey }

// apiURL builds a full URL under /wiki/rest/api given a path + query.
func (c *Client) apiURL(path string, query url.Values) string {
	u := c.baseURL + "/wiki/rest/api" + path
	if len(query) > 0 {
		u += "?" + query.Encode()
	}
	return u
}

// do performs an HTTP request, sets auth + headers, decodes JSON into out,
// and maps non-2xx responses to a readable error.
func (c *Client) do(req *http.Request, out any) error {
	req.SetBasicAuth(c.email, c.token)
	req.Header.Set("User-Agent", userAgent)
	if req.Body != nil && req.Header.Get("Content-Type") == "" {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("Accept", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("%s %s: %w", req.Method, req.URL.String(), err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode == http.StatusNotFound {
		return &NotFoundError{URL: req.URL.String()}
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return decodeError(req.Method, req.URL.String(), resp.StatusCode, body)
	}
	if out == nil || len(body) == 0 {
		return nil
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("decode response from %s: %w", req.URL.String(), err)
	}
	return nil
}

func decodeError(method, url string, status int, body []byte) error {
	var e errorResponse
	if json.Unmarshal(body, &e) == nil && e.Message != "" {
		return fmt.Errorf("%s %s: %d %s", method, url, status, e.Message)
	}
	msg := strings.TrimSpace(string(body))
	if len(msg) > 500 {
		msg = msg[:500] + "…"
	}
	if msg == "" {
		msg = http.StatusText(status)
	}
	return fmt.Errorf("%s %s: %d %s", method, url, status, msg)
}

// GetSpace fetches the space bound to this client. Used as a connection test.
func (c *Client) GetSpace() (*Space, error) {
	if c.spaceKey == "" {
		return nil, errors.New("no space key set on client")
	}
	req, err := http.NewRequest(http.MethodGet, c.apiURL("/space/"+c.spaceKey, nil), nil)
	if err != nil {
		return nil, err
	}
	var s Space
	if err := c.do(req, &s); err != nil {
		return nil, err
	}
	return &s, nil
}

// Ping does a minimal auth + connectivity check by listing spaces (limit 1).
func (c *Client) Ping() error {
	q := url.Values{"limit": {"1"}}
	req, err := http.NewRequest(http.MethodGet, c.apiURL("/space", q), nil)
	if err != nil {
		return err
	}
	return c.do(req, nil)
}

// FindPageByTitle searches for a page by exact title in the client's space.
// Optionally constrained to a parent page ID.
func (c *Client) FindPageByTitle(title, parentID string) (*Page, error) {
	q := url.Values{
		"spaceKey": {c.spaceKey},
		"title":    {title},
		"type":     {"page"},
		"expand":   {"version,ancestors"},
		"limit":    {"5"},
	}
	req, err := http.NewRequest(http.MethodGet, c.apiURL("/content", q), nil)
	if err != nil {
		return nil, err
	}
	var sr searchResult
	if err := c.do(req, &sr); err != nil {
		return nil, err
	}
	if parentID == "" {
		if len(sr.Results) == 0 {
			return nil, nil
		}
		p := sr.Results[0]
		return &p, nil
	}
	// Filter results whose nearest ancestor matches parentID. The /content
	// listing returns ancestors in root-first order.
	for _, p := range sr.Results {
		// Re-fetch the page to get ancestors reliably (the listing above may
		// not always expand them consistently).
		detailed, err := c.GetPageByID(p.ID, "version,ancestors")
		if err != nil {
			return nil, err
		}
		if detailed.hasAncestor(parentID) {
			return detailed, nil
		}
	}
	return nil, nil
}

// FindPageByPath splits a slash-delimited path and walks from the space root.
// Example: "Engineering/Backend/Umrah" → space root → "Engineering" →
// "Backend" → "Umrah".
func (c *Client) FindPageByPath(path string) (*Page, error) {
	segments := splitPath(path)
	if len(segments) == 0 {
		return nil, fmt.Errorf("empty page path")
	}
	var parentID string
	var found *Page
	for _, seg := range segments {
		p, err := c.FindPageByTitle(seg, parentID)
		if err != nil {
			return nil, err
		}
		if p == nil {
			return nil, fmt.Errorf("page %q not found under %q", seg, path)
		}
		found = p
		parentID = p.ID
	}
	return found, nil
}

func splitPath(p string) []string {
	raw := strings.Split(p, "/")
	var out []string
	for _, s := range raw {
		s = strings.TrimSpace(s)
		if s != "" {
			out = append(out, s)
		}
	}
	return out
}

// GetPageByID fetches a page by ID. expand is passed through as ?expand=.
func (c *Client) GetPageByID(id, expand string) (*Page, error) {
	q := url.Values{}
	if expand != "" {
		q.Set("expand", expand)
	}
	req, err := http.NewRequest(http.MethodGet, c.apiURL("/content/"+id, q), nil)
	if err != nil {
		return nil, err
	}
	var p Page
	if err := c.do(req, &p); err != nil {
		return nil, err
	}
	return &p, nil
}

func (p *Page) hasAncestor(id string) bool {
	for _, a := range p.Ancestors {
		if a.ID == id {
			return true
		}
	}
	return false
}

// CreatePage creates a new page under parentID (may be empty for root-level).
func (c *Client) CreatePage(title, parentID, storage string) (*Page, error) {
	body := createRequest{
		Type:  "page",
		Title: title,
		Space: spaceRef{Key: c.spaceKey},
		Body:  createBodyStruct{Storage: BodyValue{Value: storage, Representation: "storage"}},
	}
	if parentID != "" {
		body.Ancestors = []ancestorRef{{ID: parentID}}
	}
	data, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest(http.MethodPost, c.apiURL("/content", nil), bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	var p Page
	if err := c.do(req, &p); err != nil {
		return nil, err
	}
	return &p, nil
}

// UpdatePage replaces the body of an existing page, bumping the version.
func (c *Client) UpdatePage(id, title, storage string, currentVersion int) (*Page, error) {
	body := updateRequest{
		ID:      id,
		Type:    "page",
		Title:   title,
		Version: PageVersion{Number: currentVersion + 1},
		Body:    createBodyStruct{Storage: BodyValue{Value: storage, Representation: "storage"}},
	}
	data, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest(http.MethodPut, c.apiURL("/content/"+id, nil), bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	var p Page
	if err := c.do(req, &p); err != nil {
		return nil, err
	}
	return &p, nil
}

// FindAttachment returns the attachment with matching filename on pageID, or
// nil if absent.
func (c *Client) FindAttachment(pageID, filename string) (*Attachment, error) {
	q := url.Values{
		"filename": {filename},
		"expand":   {"version"},
		"limit":    {"5"},
	}
	req, err := http.NewRequest(http.MethodGet, c.apiURL("/content/"+pageID+"/child/attachment", q), nil)
	if err != nil {
		return nil, err
	}
	var al attachmentsList
	if err := c.do(req, &al); err != nil {
		return nil, err
	}
	for _, a := range al.Results {
		if a.Title == filename {
			aa := a
			return &aa, nil
		}
	}
	return nil, nil
}

// UploadAttachment creates (or updates) an attachment on pageID with the
// given filename + contents. contentType is typically "image/svg+xml".
func (c *Client) UploadAttachment(pageID, filename, contentType string, data []byte) (*Attachment, error) {
	existing, err := c.FindAttachment(pageID, filename)
	if err != nil {
		return nil, err
	}
	buf, ct, err := uploadMultipart(filename, contentType, data)
	if err != nil {
		return nil, err
	}

	var (
		method, path string
		out          Attachment
	)
	if existing != nil {
		method = http.MethodPost
		path = "/content/" + pageID + "/child/attachment/" + existing.ID + "/data"
	} else {
		method = http.MethodPost
		path = "/content/" + pageID + "/child/attachment"
	}

	req, err := http.NewRequest(method, c.apiURL(path, nil), buf)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", ct)
	req.Header.Set("X-Atlassian-Token", "no-check")

	// Both create and update return either a single Attachment or a results
	// envelope. Try results first, then fall back.
	var al attachmentsList
	raw, err := c.doRaw(req)
	if err != nil {
		return nil, err
	}
	if json.Unmarshal(raw, &al) == nil && len(al.Results) > 0 {
		return &al.Results[0], nil
	}
	if json.Unmarshal(raw, &out) == nil && out.ID != "" {
		return &out, nil
	}
	if existing != nil {
		return existing, nil
	}
	return nil, fmt.Errorf("unexpected attachment upload response: %s", string(raw))
}

// uploadMultipart builds a multipart form body for file uploads.
func uploadMultipart(filename, contentType string, data []byte) (*bytes.Buffer, string, error) {
	buf := &bytes.Buffer{}
	mw := multipart.NewWriter(buf)
	h := make(map[string][]string)
	h["Content-Disposition"] = []string{fmt.Sprintf(`form-data; name="file"; filename="%s"`, filename)}
	h["Content-Type"] = []string{contentType}
	fw, err := mw.CreatePart(h)
	if err != nil {
		return nil, "", err
	}
	if _, err := fw.Write(data); err != nil {
		return nil, "", err
	}
	if err := mw.WriteField("minorEdit", "true"); err != nil {
		return nil, "", err
	}
	if err := mw.Close(); err != nil {
		return nil, "", err
	}
	return buf, mw.FormDataContentType(), nil
}

// doRaw performs a request and returns the raw body (for non-JSON or
// flexible-shape responses like attachment uploads).
func (c *Client) doRaw(req *http.Request) ([]byte, error) {
	req.SetBasicAuth(c.email, c.token)
	req.Header.Set("User-Agent", userAgent)
	if req.Header.Get("Accept") == "" {
		req.Header.Set("Accept", "application/json")
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%s %s: %w", req.Method, req.URL.String(), err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == http.StatusNotFound {
		return nil, &NotFoundError{URL: req.URL.String()}
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, decodeError(req.Method, req.URL.String(), resp.StatusCode, body)
	}
	return body, nil
}

// AddLabels attaches the given labels to a page (prefix "global").
func (c *Client) AddLabels(pageID string, labels []string) error {
	if len(labels) == 0 {
		return nil
	}
	payload := make([]Label, 0, len(labels))
	for _, l := range labels {
		payload = append(payload, Label{Prefix: "global", Name: l})
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodPost, c.apiURL("/content/"+pageID+"/label", nil), bytes.NewReader(data))
	if err != nil {
		return err
	}
	return c.do(req, nil)
}

// GetLabels lists labels currently attached to a page.
func (c *Client) GetLabels(pageID string) ([]string, error) {
	req, err := http.NewRequest(http.MethodGet, c.apiURL("/content/"+pageID+"/label", nil), nil)
	if err != nil {
		return nil, err
	}
	var ll labelsList
	if err := c.do(req, &ll); err != nil {
		return nil, err
	}
	out := make([]string, 0, len(ll.Results))
	for _, l := range ll.Results {
		out = append(out, l.Name)
	}
	return out, nil
}

// PageURL builds the browser URL for a page.
func (c *Client) PageURL(p *Page) string {
	if p.Links != nil && p.Links.Base != "" && p.Links.WebUI != "" {
		return p.Links.Base + p.Links.WebUI
	}
	return c.baseURL + "/wiki/spaces/" + c.spaceKey + "/pages/" + p.ID
}

