#!/usr/bin/env bash
#
# Behaviour fixture for a_s_mermaid_lint, the gate that stops Mermaid which will not render.
#
# It matters because Mermaid fails whole-diagram and blames the wrong thing. One `;` in a
# sequence-diagram message replaces the entire diagram with "Parse error on line N ... got
# 'NEWLINE'", a message that names arrow tokens and never mentions the semicolon, so the
# author cannot debug it from what they see. The rules the lint enforces were each checked
# against mermaid 12 by parsing and rendering the example; every EXPECT-ERROR case below is a
# diagram mermaid genuinely refuses (or silently mangles, for the state-diagram case), and
# every EXPECT-CLEAN case is one it genuinely accepts.
#
# Falsification, since a fixture never seen failing is not evidence. Each mutation below was
# applied to scripts/a_s_mermaid_lint and the named cases were seen to fail:
#   - the entity strip is dropped               (escaped semicolon is clean, and the transition one)
#   - the ';' check fires on a trailing ';'     (trailing semicolon is clean)
#   - the ';' check is applied to flowcharts    (semicolon in a flowchart label)
#   - strip_quoted is removed                   (quoted edge label, quoted node label)
#   - the shape wrappers are not peeled         (cylinder node)
#   - the diagram type is assumed, not read     (every sequenceDiagram case, and both stream cases)
#
# Usage: bash tests/test_mermaid_lint.sh

set -uo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$REPO_ROOT/scripts/a_s_mermaid_lint"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf 'FAIL   %s\n' "$1"; }

# expect_error <name> <content>   : the lint must report an ERROR (exit 1)
expect_error() {
  local name="$1" body="$2" f="$WORK/case.md"
  printf '%s\n' "$body" > "$f"
  if "$LINT" -q "$f"; then bad "$name (expected an error, got clean)"; else ok "$name"; fi
}

# expect_clean <name> <content>   : no ERROR (warnings allowed, exit 0)
expect_clean() {
  local name="$1" body="$2" f="$WORK/case.md"
  printf '%s\n' "$body" > "$f"
  if "$LINT" -q "$f"; then ok "$name"; else
    bad "$name (expected clean, got:)"; "$LINT" "$f" | sed 's/^/       /'
  fi
}

# expect_warn <name> <content>    : clean by default, an error under --strict
expect_warn() {
  local name="$1" body="$2" f="$WORK/case.md"
  printf '%s\n' "$body" > "$f"
  if "$LINT" -q "$f" && ! "$LINT" -q -s "$f"; then ok "$name"; else
    bad "$name (expected a warning only)"; "$LINT" "$f" | sed 's/^/       /'
  fi
}

fence() { printf '```mermaid\n%s\n```\n' "$1"; }

printf '\nsequenceDiagram: the semicolon that blanks the diagram\n'

expect_error "semicolon in message text" "$(fence 'sequenceDiagram
    participant FE
    participant SRV
    SRV-->>FE: Set-Cookie: id=C1; Domain=example.com')"

expect_error "semicolon in Note text" "$(fence 'sequenceDiagram
    participant FE
    Note over FE: minted; stored')"

expect_error "semicolon in a participant alias" "$(fence 'sequenceDiagram
    participant FE as app; js
    FE->>FE: x')"

expect_error "semicolon in a loop label" "$(fence 'sequenceDiagram
    participant FE
    loop every 7d; daily
        FE->>FE: x
    end')"

expect_clean "escaped semicolon is clean" "$(fence 'sequenceDiagram
    participant FE
    participant SRV
    SRV-->>FE: Set-Cookie: id=C1#59; Domain=example.com')"

expect_clean "trailing semicolon is clean" "$(fence 'sequenceDiagram
    participant FE
    FE->>FE: hello;')"

expect_clean "characters that are safe in message text" "$(fence 'sequenceDiagram
    participant FE as www.example.com (js)
    FE->>FE: GET /c, X-Id: C1 = ok & 50% @host <br/> a+b-c #1 {j}')"

expect_warn "quotes render literally in a sequenceDiagram" "$(fence 'sequenceDiagram
    participant FE as "Front End"
    FE->>FE: "hello there"')"

printf '\nflowchart: the unquoted label\n'

expect_error "unquoted edge label with an @" "$(fence 'flowchart LR
    A -->|@import pulls in| B')"

expect_error "unquoted node label with parentheses" "$(fence 'flowchart LR
    A[a (b)] --> B')"

expect_clean "quoted edge label" "$(fence 'flowchart LR
    A -->|"@import pulls in"| B')"

expect_clean "quoted node label" "$(fence 'flowchart LR
    A["a (b)"] --> B')"

expect_clean "semicolon in a flowchart label" "$(fence 'flowchart LR
    A[a; b] -->|x; y| B
    classDef role fill:#1971c2,stroke:#74c0fc;
    class A role;')"

expect_clean "cylinder node" "$(fence 'flowchart LR
    START -->|"append row"| REG[("~/.a_tasks/tasks.tsv")]')"

expect_clean "shape metadata syntax" "$(fence 'flowchart LR
    A@{ shape: rect }
    A --> B')"

printf '\nstateDiagram-v2: the silent one\n'

expect_error "semicolon in a transition label" "$(fence 'stateDiagram-v2
    A --> B: go; now')"

expect_clean "escaped semicolon in a transition label" "$(fence 'stateDiagram-v2
    A --> B: go#59; now')"

printf '\nfile handling\n'

expect_error "escaped backticks corrupt every fence" '\`\`\`mermaid
flowchart LR
    A --> B
\`\`\`'

expect_error "two blocks, different types" "$(fence 'flowchart LR
    A --> B')
$(fence 'sequenceDiagram
    participant FE
    FE->>FE: a; b')"

expect_clean "table pipes outside a block" 'Prose first.

| col | value |
|---|---|
| a | @import (x) |

'"$(fence 'flowchart LR
    A --> B')"

expect_clean "a shell fence is not a diagram" '```bash
echo "a (b)" | grep -o "@x"
```'

printf '%s\n' 'sequenceDiagram
    participant FE
    FE->>FE: a; b' > "$WORK/raw.mmd"
if "$LINT" -q "$WORK/raw.mmd"; then bad "unfenced .mmd file"; else ok "unfenced .mmd file"; fi

if printf 'sequenceDiagram\n    participant FE\n    FE->>FE: a; b\n' | "$LINT" -q -; then
  bad "stdin"; else ok "stdin"
fi

if "$LINT" -q "$REPO_ROOT"/docs/*.md "$REPO_ROOT/AGENTS.md" "$REPO_ROOT/rules/mermaid.md"; then
  ok "this repo's own diagrams are clean"
else
  bad "this repo's own diagrams are clean"
  "$LINT" "$REPO_ROOT"/docs/*.md "$REPO_ROOT/AGENTS.md" "$REPO_ROOT/rules/mermaid.md" | sed 's/^/       /'
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
