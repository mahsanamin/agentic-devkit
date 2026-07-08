# mdcf — Markdown ↔ Confluence

A fast, single-binary CLI for pushing Markdown files to Confluence Cloud and pulling pages back as Markdown. macOS-first (ARM + Intel universal binary), Linux via the same codebase.

- **Push**: walk a docs tree, render Markdown (incl. Mermaid) into Confluence Storage Format, upsert pages.
- **Pull**: fetch a page by title or ID, convert back to Markdown with frontmatter.
- **No DB, no server**: a YAML config under `~/.mdcf/` and a `.mdcf.yaml` per repo.

## Install

### From source

```bash
cd tools/mdcf
make install            # builds and copies to /usr/local/bin/mdcf
```

### From GitHub releases

```bash
curl -fsSL https://raw.githubusercontent.com/mahsanamin/mdcf/main/install.sh | bash
```

The script detects macOS arm64 / amd64 (and Linux amd64) and downloads the matching binary.

## Quick start

```bash
# 1. One-time global setup (prompts for URL, email, API token)
mdcf setup

# 2. In your docs repo / directory
mdcf init

# 3. Push a single file
mdcf push docs/onboarding.md

# 4. Push an entire directory (skips _* and README.md)
mdcf push docs/

# 5. Pull a page back as Markdown
mdcf pull 123456789
mdcf pull "Runbooks/Alerting"
```

Every command supports `--help`.

## Command reference

### `mdcf setup`

Interactive wizard that writes `~/.mdcf/config.yaml`. Validates the base URL is an Atlassian Cloud root and tests the credentials by listing spaces.

Flags:
- `--force` — overwrite an existing global config.

### `mdcf init`

Interactive wizard that writes `.mdcf.yaml` in the current directory after verifying the space + parent page exist.

Flags:
- `--force` — overwrite an existing `.mdcf.yaml`.

### `mdcf push [path]`

Path defaults to the current directory. In directory mode, recursively collects `*.md` files, skipping:
- files starting with `_`,
- `README.md`,
- hidden directories and `node_modules` / `vendor`.

Per file:
1. Parse YAML frontmatter.
2. Resolve the title: `frontmatter.title` → first `# H1` → filename stem.
3. Convert the body to Confluence Storage Format.
4. If `confluence_page_id` is set in frontmatter, update that page; otherwise search by title under the parent, create if missing.
5. Write `confluence_page_id` back into frontmatter after a fresh create.
6. Print the page URL.

Flags:
- `-d`, `--dry-run` — convert but don't call Confluence.
- `-v`, `--verbose` — print the rendered storage format (useful with `--dry-run`).
- `--title` — override the title (single-file push only).
- `--parent` — override the parent page ID.

### `mdcf pull <title-or-id>`

Fetches a page by numeric ID or by exact title in the workspace's space. Converts the storage format back to Markdown and writes `<kebab-case-title>.md` in the current directory (unless `-o` is set).

Flags:
- `-o`, `--output` — output file path.
- `--space` — override the space key from `.mdcf.yaml`.

### `mdcf help`

Styled, single-screen overview with examples (cobra's `--help` is still available everywhere).

## Config hierarchy

Three levels, merged at runtime. Deeper wins.

### 1. Global — `~/.mdcf/config.yaml`

Created by `mdcf setup`:

```yaml
base_url: https://your-org.atlassian.net   # root only — no /wiki, no space
email: you@company.com
api_token: ${MDCF_API_TOKEN}               # ${VAR} is expanded at runtime
```

File mode is `0600`. Prefer `${MDCF_API_TOKEN}` over pasting the token directly.

### 2. Workspace — `.mdcf.yaml`

Created by `mdcf init` at the repo or docs root:

```yaml
space_key: ENG
parent_page_path: Engineering/Backend
github_repo_url: https://github.com/OWNER/my-repo   # optional — adds "View source" link under Mermaid
```

### 3. Subdirectory — `.mdcf.yaml`

Inherits from shallower `.mdcf.yaml`s. Override only what differs:

```yaml
parent_page_path: Engineering/Backend/Payments
```

When pushing a file, mdcf walks from the file's directory up to `/`, collects every `.mdcf.yaml`, merges them (deeper wins), then merges the global config.

## Frontmatter

YAML block between `---` markers at the top of any Markdown file. Optional; mdcf adds fields after the first successful push.

| Field                  | Who writes it | What it does                                           |
| ---------------------- | ------------- | ------------------------------------------------------ |
| `title`                | you or mdcf   | Page title. Beats the first H1 in the body.            |
| `confluence_page_id`   | mdcf          | Target page for updates. Written after a fresh create. |
| `confluence_parent_id` | you           | Override parent for this file only.                    |
| `labels`               | you           | List of Confluence labels to attach after push.        |

Example:

```markdown
---
title: Deploy runbook
labels:
  - runbook
  - oncall
---

# Deploy runbook

Body here…
```

## Mermaid workflow

For every ```mermaid``` code fence mdcf:

1. Base64url-encodes the source, asks `https://kroki.io/mermaid/svg/<encoded>` to render.
2. Uploads the SVG as `diagram-<n>.svg` to the page as an attachment (creates or updates in place).
3. Embeds `<ac:image><ri:attachment ri:filename="diagram-<n>.svg"/></ac:image>`.
4. If `github_repo_url` is set in config, appends a small "📎 View Mermaid source on GitHub" link under the image.

If Kroki is unreachable, the diagram falls back to a warning macro + code block so the push never fails.

On `mdcf pull`, `mermaid-cloud` macros and generated SVG attachments are restored to ```mermaid``` fenced blocks.

## `.gitignore`

`.mdcf.yaml` is fine to commit (it points at the right space/parent). Keep tokens out of it — they belong in `~/.mdcf/config.yaml` or `MDCF_API_TOKEN`. The global config and any file under `~/.mdcf/` should never be committed anywhere.

## Environment variables

| Variable           | Purpose                                      |
| ------------------ | -------------------------------------------- |
| `MDCF_API_TOKEN`   | Referenced from `~/.mdcf/config.yaml`.       |
| `MDCF_REPO`        | (install.sh) Owner/repo to download from.    |
| `MDCF_PREFIX`      | (install.sh) Install prefix.                 |

Generate an API token at <https://id.atlassian.com/manage-profile/security/api-tokens>.

## Development

```bash
make tidy          # go mod tidy
make vet           # go vet ./...
make build         # build ./bin/mdcf
make build-mac-arm # or build-mac-intel, build-linux
make release-mac   # lipo universal binary
```

## Acceptance

- `go mod tidy` resolves cleanly.
- `go build ./cmd/mdcf` compiles with zero errors.
- `./mdcf --help` lists `setup`, `init`, `push`, `pull`, `help`.
- `./mdcf push --help` lists `-d/--dry-run`, `-v/--verbose`, `--title`, `--parent`.
