# mdnest writing rules (canonical)

Single source of truth for how Claude reads and (above all) **writes** to Ahsan's
private markdown notes via the `mdnest` CLI. Imported into global `~/.claude/CLAUDE.md`
and followed by the `a_sag_mdnest_writer` agent. If a rule changes, change it here.

## What mdnest is
`mdnest` is a CLI on Ahsan's machines for read/write access to his private markdown
notes server. It is available. Use it. Do not claim a lack of access.

## Discovery and addressing
- Discover servers and namespaces: `mdnest servers -v` (the `*` marks the default alias).
- Quick reference: `mdnest --help`.
- Path format: `@alias/namespace/path/to/file.md`.
- A pasted URL like `mdnest://@srv-ahsan-mini/mahsan_brain/Temp/x.md` maps to the path
  `@srv-ahsan-mini/mahsan_brain/Temp/x.md` (drop the `mdnest://`). Do not assume an
  alias; read the one in the path, or run `mdnest servers -v` if none is given.

## Verbs
| Verb | Effect |
|---|---|
| `read <path>` | Print a note |
| `create <path> <content>` | New file ONLY (fails if it already exists) |
| `write <path> <content>` | Overwrite an EXISTING file (fails 404 if missing) |
| `append <path> <content>` | Add to the end (creates the file if missing) |
| `prepend <path> <content>` | Add to the start (creates the file if missing) |
| `delete`, `move`, `list`, `search` | As named |

Pick the verb deliberately: `create` for a brand new note, `write` to replace one
that exists. Using the wrong one fails loudly, which is the safe behavior.

## The safe-write contract (READ THIS; it is the whole point)
The one real failure mode is **content corruption from shell quoting**, not the CLI.
Passing markdown that contains backticks or quotes straight into a bash heredoc or a
quoted argument, and escaping the backticks (`` \` ``), stores the backslashes
literally. That breaks every code fence and Mermaid block: ```` ```mermaid ```` becomes
`` \`\`\`mermaid `` and the renderer shows raw text instead of a diagram.

Never hand-escape backticks or quotes for mdnest. Instead, always:

1. **Write the full note to a temp file with a literal-writing tool** (the Write tool,
   or a single-quoted heredoc with NO escaping). This stores characters verbatim, so no
   shell rule can mangle them.
   - `Write /tmp/note.md` with the real content (clean `` ``` `` fences, real `"` quotes).
2. **Send the file to mdnest, do not inline the markdown:**
   - New note:    `mdnest create <path> "$(cat /tmp/note.md)"`
   - Update note: `mdnest write  <path> "$(cat /tmp/note.md)"`
   - `"$(cat ...)"` passes the file content literally; backticks inside are not re-evaluated.
3. **Verify after every write. Do not trust, confirm:**
   - No escaped backticks survived:
     `mdnest read <path> | grep -q '\\\\`' && echo BAD || echo CLEAN` (must print CLEAN).
   - The fence is intact: `mdnest read <path> | grep -n '```mermaid'` shows a bare
     ```` ```mermaid ```` line (no backslashes, nothing merged onto it).

If verification fails, fix the temp file and `write` again; never leave a corrupted note.

## Mermaid rules (always colorful, always readable, always valid)
Goal: punchy, high-contrast diagrams whose roles read at a glance. The renderer used by
mdnest computes readable text contrast per node, so group nodes by role and use distinct,
saturated fills. Living palette: `@srv-ahsan-mini/mahsan_brain/MyProjects/mdNest/mermaid-style.md`
(mirrored below; keep in sync).

- **Use `classDef` roles, then assign nodes** (do not hand-color each node):
  ```
  classDef frontend fill:#1971c2,stroke:#74c0fc,stroke-width:2px;
  classDef backend  fill:#2f9e44,stroke:#8ce99a,stroke-width:2px;
  classDef external fill:#e8590c,stroke:#ffc078,stroke-width:2px;
  classDef data     fill:#6741d9,stroke:#b197fc,stroke-width:2px;
  classDef infra    fill:#0c8599,stroke:#66d9e8,stroke-width:2px;
  ```
  Roles: frontend (blue) = UI/clients; backend (green) = services/logic; external
  (orange) = third-party; data (purple) = stores/queues; infra (teal) = schedulers/
  proxies/brokers/links. Assign with `class A,B backend;` or `A:::backend`.
- **Do not set `color:` yourself.** mdnest computes the readable text color per fill.
  (Outside mdnest, e.g. GitHub or Confluence, set `fill`, `stroke`, AND `color` together.)
- Keep one direction (`flowchart LR` or `TB`) and short labels; `<br/>` for line breaks.
- Pick the right diagram type: `flowchart` for processes/architecture, `sequenceDiagram`
  for request/response flows, `classDiagram` for data models, `stateDiagram-v2` for
  lifecycles, `gantt` for timelines.
- Subgraphs, `direction` inside a subgraph, emojis, and blank lines inside the block are
  all fine in mdnest (proven against existing notes).

### Mermaid syntax that breaks a whole diagram (avoid these)
Two failure modes have actually bitten us. Each kills the ENTIRE diagram, not one line.

1. **Escaped backticks in the fence** (see the safe-write contract above): keep
   ```` ```mermaid ```` clean, never `` \` ``.
2. **Unquoted edge labels that contain special characters.** The label between `|...|`
   (and any text label on a link) MUST be wrapped in double quotes when it contains
   anything beyond plain words and spaces, especially `@`, `(`, `)`, `:`, `#`, `&`, `;`,
   `/`, `,`. A bare `@` in an edge label is parsed as special syntax and throws
   `Parse error on line N ... got 'LINK_ID'`, blanking the diagram.
   - WRONG: `GC -->|@import pulls in| RULES`
   - RIGHT: `GC -->|"@import pulls in"| RULES`
   - Habit: **always quote edge labels** (`A -->|"label"| B`), even plain ones. Node text
     inside `["..."]` / `(["..."])` is already safe; the gap is the edge label.

When in doubt, quote it. Quoting a label is always safe; leaving a special character
unquoted is the gamble that breaks the render.

## Log unexpected mdnest problems
Whenever mdnest behaves unexpectedly (an error, data loss, or inconsistent or surprising
results), record one markdown file per bug in `@srv-ahsan-mini/mahsan_brain/MyProjects/mdNest/Bugs`
(summary, repro steps, expected vs actual, impact, workaround). This is Ahsan's mdnest
bug tracker. A corrupted write caused by our own escaping is NOT an mdnest bug; fix the
procedure instead of filing it.

Known CLI quirks already logged there:
- `list` ignores subfolder paths and returns the whole namespace.
- `move` can leave the destination empty and unwritable (verify, and re-`append` after a move).
- `create <path> -` stores a literal dash instead of reading stdin (use `append` for new
  files from stdin, or the `"$(cat ...)"` form above).
