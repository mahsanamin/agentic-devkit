# Mermaid syntax that renders (canonical)

Single source of truth for writing Mermaid that survives the parser, wherever the diagram ends
up: mdnest, Confluence, GitHub, an artifact, or a repo doc. Colors and palette are a separate
concern and live with each target (mdnest: `rules/mdnest.md`). Read this before writing a
diagram, and run `a_s_mermaid_lint` on the file before publishing it.

Every rule here was checked against mermaid 12 by parsing and rendering the example. "Breaks"
means the whole diagram is replaced by a parse error, not just the offending line.

## Quoting is a flowchart feature, not a general escape

There is no one escape rule across diagram types, so "when in doubt, quote it" is wrong, and it
has already shipped a broken document.

| Diagram type | Are `"..."` quotes syntax? | What they do |
|---|---|---|
| `flowchart` / `graph` | Yes | Protect node text and edge labels; special characters inside become literal. |
| `sequenceDiagram` | **No** | They are ordinary characters. They render as visible `"` marks and protect nothing. |
| `stateDiagram-v2`, `classDiagram` | Only in specific positions | Do not rely on them. Keep label text plain. |

In a sequence diagram, `A->>B: "text"` renders with the quote marks showing, and the line is
still just as broken if the text contains a `;`. Same for a quoted participant alias:
`participant FE as "app (js)"` puts the quotes in the box.

## The killer: a semicolon inside sequence-diagram text

In a sequence diagram `;` ends a statement, exactly like a newline. Whatever follows it is read
as the start of a new statement, the parser expects an arrow there, and the entire diagram is
replaced by:

```
Parse error on line 8:
...d=C1; Domain=example.com    Note over FE
-----------------------^
Expecting '()', 'SOLID_OPEN_ARROW', ... got 'NEWLINE'
```

That is the diagram-wide failure, from one character, and the error names a token list that
says nothing about semicolons. It lands on HTTP headers, cookie attributes, CSS and shell
snippets, which is most of what a technical sequence diagram carries.

It applies everywhere a sequence diagram takes free text:

| Position | Example that breaks the diagram |
|---|---|
| Message text | `SRV-->>FE: Set-Cookie: id=C1; Domain=example.com` |
| `Note` text | `Note over FE: minted; stored` |
| Participant alias | `participant FE as app; js` |
| Block label | `loop every 7d; daily`, `alt ok; not ok`, `par a; b` |

**Fix: write `#59;` where you want a semicolon.** Mermaid turns the numeric entity back into a
`;` at render time, so the text reads correctly and the statement is not cut:

```
SRV-->>FE: Set-Cookie: id=C1#59; Domain=example.com
```

Rewording so the semicolon is not needed (a comma, or a second message) is equally fine and
usually reads better. A trailing `;` with nothing after it is harmless.

## The same character behaves differently per diagram type

This is why one blanket rule cannot work:

| Where a `;` sits | Result |
|---|---|
| flowchart node label, `A[a; b]` or `A["a; b"]` | Fine. Renders as `a; b`. |
| flowchart edge label, `A -->\|x; y\| B` | Fine, quoted or not. |
| end of a flowchart statement, `A --> B;` | Fine. That is its job, and why `classDef` lines end in `;`. |
| sequenceDiagram text | Breaks the whole diagram. |
| `stateDiagram-v2` transition label, `A --> B: go; now` | Worse than a break: it parses. The label becomes `go`, and you get two phantom states named `;` and `now`. Nothing reports an error. |

The last row is why a diagram still has to be looked at after it renders. A clean parse is not
proof the diagram says what you wrote.

## Unquoted labels in a flowchart

In a `flowchart` / `graph`, an unquoted label (node text or the text between `|...|`) breaks on
`(`, `)`, `[`, `]`, `{`, `}`, `@`, and an inner `"`. A bare `@` throws
`Parse error ... got 'LINK_ID'` and blanks the diagram.

- WRONG: `GC -->|@import pulls in| RULES`
- RIGHT: `GC -->|"@import pulls in"| RULES`

Quoting is safe here and costs nothing, so quote every flowchart label, even a plain one. Do
not carry that habit into a sequence diagram (see the top of this file).

Verified fine unquoted in a flowchart label, for reference: `,` `/` `:` `#` `&` `%` `=` `-` `;`
`+`. Quote anyway; it is one less thing to remember.

## What is safe in sequence-diagram text

Verified to render with no quoting and no entity: `:` `,` `(` `)` `=` `/` `@` `&` `<` `>` `+`
`-` `#` `%` `{` `}` `<br/>`, and arrow-looking text such as `-->>`. Only `;` cuts the
statement.

## Before publishing a diagram

1. **Lint it**: `a_s_mermaid_lint <file.md>`, or pipe the diagram in on stdin. It pulls out
   every ```` ```mermaid ```` block and reports the failure modes above with a line number and
   the fix. Exit 0 is clean, 1 means findings.
2. **Then look at it rendered.** The state-diagram row above parses clean and is still wrong.
3. If `mmdc` is already installed the lint also compile-checks each block. Do not install it
   just for this.

## Diagram type and line breaks

- Pick the type that fits: `flowchart` for processes and architecture, `sequenceDiagram` for
  request and response flows, `classDiagram` for data models, `stateDiagram-v2` for lifecycles,
  `gantt` for timelines, `block-beta` for layered scope.
- Keep one direction (`flowchart LR` or `TB`) and short labels. Use `<br/>` for a line break,
  which works in both flowchart labels and sequence message text.
