Build a CLI tool called `mdcf` (Markdown ↔ Confluence) in Go.

## Goal
A fast, single-binary CLI for engineers to push Markdown files to Confluence and pull Confluence pages back as Markdown. macOS first (ARM + Intel universal binary). Linux later via same codebase.

## Name
`mdcf` — reads as "MD to CF" and "CF to MD". Binary name: `mdcf`.

## Stack
- Go 1.22+, ESM modules
- github.com/spf13/cobra — commands + auto --help on every command
- github.com/charmbracelet/huh — interactive prompts
- github.com/charmbracelet/lipgloss — terminal output styling
- github.com/yuin/goldmark — Markdown AST parser (no regex-based conversion)
- github.com/JohannesKaufmann/html2markdown — Confluence HTML → Markdown (pull)
- gopkg.in/yaml.v3 — frontmatter parsing
- Standard library net/http for all API calls

## Config hierarchy (three levels, deeper wins, merged at runtime)

1. Global — ~/.mdcf/config.yaml (created by `mdcf setup`)
   base_url: "https://your-org.atlassian.net"   ← root only, never /wiki or space
   email: "you@company.com"
   api_token: "${MDCF_API_TOKEN}"               ← resolve ${VAR} from env at runtime

2. Workspace — .mdcf.yaml in any repo/docs directory (created by `mdcf init`)
   space_key: "ENG"
   parent_page_path: "Engineering/Backend"
   github_repo_url: "https://github.com/org/repo"   ← optional, for Mermaid source links

3. Subdirectory — .mdcf.yaml deeper in tree, inherits from parent, overrides only what differs
   parent_page_path: "Engineering/Backend/Umrah"

Config resolution for push: start from target file's directory, walk up collecting .mdcf.yaml files, merge all, then merge with global. Deeper wins.

## Commands

### mdcf setup
Interactive wizard (huh forms). Prompts: base_url, email, api_token.
Validates base_url matches https://*.atlassian.net.
Tests connection via GET /wiki/rest/api/space.
Saves to ~/.mdcf/config.yaml.
Warns if token stored as plaintext vs ${VAR}.
Flag: --force to overwrite.

### mdcf init
Requires global config (exit 1 with "Run mdcf setup first" if missing).
Prompts for space_key and parent_page_path.
Verifies space + parent page exist via API.
Saves .mdcf.yaml in current directory.
Flag: --force to overwrite.

### mdcf push [target]
target = single .md file or directory (default: current dir).
Directory mode: push all .md files, skip files prefixed with _, skip README.md.
Per file:
  1. Parse YAML frontmatter (gray-matter style: between --- markers)
  2. Title: frontmatter title → first # H1 → filename stem
  3. Convert body to Confluence Storage Format (see Conversion)
  4. If confluence_page_id in frontmatter → update that page
  5. Else search by title → update if found, create if not
  6. After create: write confluence_page_id back into frontmatter in-place
  7. Print page URL on success
Flags: -d/--dry-run, -v/--verbose, --title (single file), --parent (page ID override)

### mdcf pull [page-title or page-id]
Fetch Confluence page by title or numeric ID.
Convert storage format → Markdown (see Pull Conversion).
Save as kebab-case-title.md in current directory.
Write frontmatter: title, confluence_page_id, labels.
Flags: -o/--output path, --space key override

### mdcf help
Cobra handles --help on every command automatically.
Also add a help subcommand that prints a styled overview with examples using lipgloss.

## Markdown → Confluence Storage Format
Use goldmark AST walker, not regex. Map:
- h1–h6 → 

–
- bold/italic/inline code → // - link → - external image → - blockquote → Confluence info macro - fenced code (non-mermaid) → Confluence code macro, language param, linenumbers=true - fenced code (mermaid) → see Mermaid section - ul/ol →
/
- table →
/	## Mermaid handling For each ```mermaid block: 1. Base64url-encode the source, GET https://kroki.io/mermaid/svg/ (10s timeout) 2. Upload SVG as attachment to the Confluence page: POST /wiki/rest/api/content/{pageId}/child/attachment Header: X-Atlassian-Token: no-check Filename: diagram-{index}.svg Handle existing attachment: check first, PUT to update if exists 3. Embed: 4. If github_repo_url set in config, append below image:
View Mermaid source on GitHub

5. Fallback if Kroki unreachable: embed source as code block + prepend Confluence warning macro. Do not fail the push. ## Confluence Storage Format → Markdown (pull) Pre-process XML before passing to html2markdown: - code macro → fenced code block with language - mermaid-cloud macro → ```mermaid fenced block (restore source) - info/note/warning macro → blockquote with prefix (ℹ / 📝 / ⚠) - expand macro containing mermaid source → strip entirely - ac:image with ri:attachment → skip (generated SVG) - ac:image with ri:url → ![](url) ## Confluence API client (internal/confluence/client.go) Struct: Client { baseURL, email, token, spaceKey, http.Client (30s timeout) } Methods: GetSpace, FindPageByTitle, FindPageByPath (split "/" traverse ancestors), GetPageByID, CreatePage, UpdatePage, UploadAttachment, AddLabels, PageURL Auth: HTTP Basic (email:token). Base: {baseURL}/wiki/rest/api. On non-2xx: extract message from JSON body, return as Go error. User-Agent: mdcf/1.0 ## Terminal output (internal/ui/ui.go) lipgloss styles: Success (green), Error (red), Warning (yellow), Dim (grey), URL (blue underline), Bold, Header (cyan). Helpers: PrintSuccess, PrintError, PrintWarning, PrintURL, PrintSummary(succeeded, failed int). Spinner for all async ops (API calls, Kroki, attachment upload). ## Frontmatter Auto-written after first push: confluence_page_id: "123456789" User-settable: title, confluence_page_id, confluence_parent_id, labels[] When writing back: preserve all existing fields, re-serialize cleanly as ---\n{yaml}\n---\n{body}. ## Error handling - Global config missing → "Run mdcf setup first" → exit 1 - Workspace config missing → prompt inline, offer to save - confluence_page_id 404 → warn, create new page, update frontmatter with new ID - Kroki timeout → fallback (warning macro + code block), continue - Per-file failures → collect all, print summary at end, do not abort mid-batch ## Project structure mdcf/ ├── cmd/mdcf/main.go ├── internal/ │ ├── config/config.go + loader.go │ ├── confluence/client.go + types.go │ ├── converter/push.go + pull.go + mermaid.go │ └── ui/ui.go ├── cmd_impl/setup.go + init.go + push.go + pull.go ├── Makefile ├── install.sh └── README.md ## Makefile targets build, build-mac-arm, build-mac-intel, build-linux, install, release-mac (lipo universal binary) ## install.sh Detect Mac ARM vs Intel, download correct binary from GitHub releases, install to /usr/local/bin. ## README must cover Installation (make install, install.sh), quick start, full command reference with examples, config hierarchy reference, Mermaid workflow, frontmatter fields, .gitignore note, env var setup. ## Acceptance criteria After writing all files: 1. Run: go mod tidy 2. Run: go build ./cmd/mdcf — must compile with zero errors 3. Run: ./mdcf --help — all commands must appear 4. Run: ./mdcf push --help — all flags must appear
Copy prompt

