package confluence

// Space represents a minimal Confluence space payload.
type Space struct {
	Key  string `json:"key"`
	Name string `json:"name"`
	ID   string `json:"id"`
}

// Page is a Confluence content item of type "page".
type Page struct {
	ID        string        `json:"id"`
	Type      string        `json:"type"`
	Title     string        `json:"title"`
	Version   PageVersion   `json:"version"`
	Space     *Space        `json:"space,omitempty"`
	Body      *PageBody     `json:"body,omitempty"`
	Links     *PageLinks    `json:"_links,omitempty"`
	Ancestors []ancestorRef `json:"ancestors,omitempty"`
	Metadata  *PageMetadata `json:"metadata,omitempty"`
}

// PageMetadata optionally carries labels (requested via ?expand=metadata.labels).
type PageMetadata struct {
	Labels *labelsList `json:"labels,omitempty"`
}

// PageVersion carries Confluence's optimistic-lock version number.
type PageVersion struct {
	Number int `json:"number"`
}

// PageBody optionally holds a body representation (we only ever request
// storage format).
type PageBody struct {
	Storage BodyValue `json:"storage,omitempty"`
}

// BodyValue is the shape of each body representation.
type BodyValue struct {
	Value          string `json:"value"`
	Representation string `json:"representation"`
}

// PageLinks is the subset of the _links envelope we use.
type PageLinks struct {
	Base   string `json:"base"`
	WebUI  string `json:"webui"`
	TinyUI string `json:"tinyui"`
	Self   string `json:"self"`
}

// searchResult wraps list responses (/content/search, /content).
type searchResult struct {
	Results []Page `json:"results"`
	Size    int    `json:"size"`
}

// createRequest is the payload sent to POST /wiki/rest/api/content.
type createRequest struct {
	Type      string           `json:"type"`
	Title     string           `json:"title"`
	Space     spaceRef         `json:"space"`
	Ancestors []ancestorRef    `json:"ancestors,omitempty"`
	Body      createBodyStruct `json:"body"`
}

type createBodyStruct struct {
	Storage BodyValue `json:"storage"`
}

type spaceRef struct {
	Key string `json:"key"`
}

type ancestorRef struct {
	ID string `json:"id"`
}

// updateRequest is the payload sent to PUT /wiki/rest/api/content/{id}.
type updateRequest struct {
	ID      string           `json:"id"`
	Type    string           `json:"type"`
	Title   string           `json:"title"`
	Version PageVersion      `json:"version"`
	Body    createBodyStruct `json:"body"`
}

// errorResponse is Confluence's standard error envelope.
type errorResponse struct {
	StatusCode int    `json:"statusCode"`
	Message    string `json:"message"`
	Reason     string `json:"reason"`
}

// Attachment represents a minimal attachment record.
type Attachment struct {
	ID      string      `json:"id"`
	Title   string      `json:"title"`
	Version PageVersion `json:"version"`
}

type attachmentsList struct {
	Results []Attachment `json:"results"`
}

// Label represents a Confluence label.
type Label struct {
	Prefix string `json:"prefix"`
	Name   string `json:"name"`
}

type labelsList struct {
	Results []Label `json:"results"`
}
