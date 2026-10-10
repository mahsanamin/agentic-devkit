#!/usr/bin/env bash
#
# Behaviour fixture for a_s_blog_lint, the readability report used by a_sk_blog_writer.
#
# Each EXPECT-RULE case must produce a finding for exactly the named rule, and each EXPECT-CLEAN
# case must produce none. The clean cases guard against the false positives that would make
# authors ignore the report: version numbers and file names that look like sentence ends, words
# inside code, card text split at its tags, and a heading or visual that resets the word gap.
#
# Usage: bash tests/test_blog_lint.sh

set -uo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$REPO_ROOT/scripts/a_s_blog_lint"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf 'FAIL   %s\n' "$1"; }

# expect_rule <name> <rule> <content> : the lint exits 1 and reports <rule>
expect_rule() {
  local name="$1" rule="$2" body="$3" f="$WORK/case.md" out
  printf '%s\n' "$body" > "$f"
  out="$("$LINT" "$f")"
  if [ $? -eq 1 ] && grep -q ": $rule: " <<<"$out"; then ok "$name"; else
    bad "$name (expected $rule, got:)"; sed 's/^/       /' <<<"$out"
  fi
}

# expect_clean <name> <content> : no findings, exit 0
expect_clean() {
  local name="$1" body="$2" f="$WORK/case.md"
  printf '%s\n' "$body" > "$f"
  if "$LINT" -q "$f"; then ok "$name"; else
    bad "$name (expected clean, got:)"; "$LINT" "$f" | sed 's/^/       /'
  fi
}

words() { local n="$1" w="$2"; for _ in $(seq "$n"); do printf '%s ' "$w"; done; }
# a paragraph of <n> short sentences, five words each
para() { for _ in $(seq "$1"); do printf 'The cat sat down here. '; done; printf '\n'; }

printf '\nsentences\n'
expect_rule  "26-word sentence"            long-sentence "$(words 25 word)end."
expect_clean "25-word sentence"            "$(words 24 word)end."
expect_clean "version and file name"       "Install version 1.5 from README.md first. Then run it."
expect_clean "abbreviations do not split"  "Use a tool, e.g. a linter. It helps."
expect_rule  "long sentence in a list"     long-sentence "- $(words 30 word)end."
expect_rule  "long sentence in a card"     long-sentence "<div class=\"card\"><h3>Title</h3><p>$(words 30 word)end.</p></div>"
expect_clean "card tags split sentences"   "<div class=\"card\"><h3>$(words 15 word)</h3><p>$(words 15 word)end.</p></div>"

printf '\nparagraphs and walls of text\n'
expect_rule  "81-word paragraph"           long-paragraph "$(words 80 word)end."
expect_clean "frontmatter is skipped"      "---
title: $(words 100 word)
---

Short body here."
expect_rule  "301 words with no break"     wall-of-text "$(para 15)

$(para 15)

$(para 15)

$(para 15)

Then one more."
expect_clean "a heading resets the gap"    "$(para 15)

$(para 15)

$(para 15)

$(para 15)

## Next part

$(para 15)

$(para 15)

$(para 15)

$(para 15)"
expect_clean "a table resets the gap"      "$(para 15)

$(para 15)

$(para 15)

$(para 15)

| a | b |
|---|---|
| 1 | 2 |

$(para 15)

$(para 15)

$(para 15)

$(para 15)"

printf '\nwords\n'
expect_rule  "words to avoid"              word-to-avoid "We leverage the cache."
expect_rule  "filler"                      filler "You simply run it."
expect_clean "filler inside inline code"   'Run `just build` now.'
expect_clean "filler inside <code>"        '<div class="card"><p>Run <code>just build</code> now.</p></div>'
expect_clean "words inside a code block"   '```
simply leverage
```'
expect_clean "a quotation is not checked"   "> Just simply leverage $(words 30 word)end."
expect_clean "word part is not a hit"      "The keyboard is justified."

printf '\nimages\n'
expect_rule  "markdown image with no alt"  image-alt "![](/a.png)"
expect_rule  "img with no alt"             image-alt '<img src="/a.png">'
expect_rule  "img with empty alt"          image-alt '<img src="/a.png" alt="">'
expect_clean "img with alt"                '<img src="/a.png" alt="A chart of load by hour">'
expect_clean "markdown image with alt"     "![A chart of load by hour](/a.png)"

printf '\nusage\n'
if "$LINT" -q "$WORK/missing.md" 2>/dev/null; [ $? -eq 2 ]; then ok "missing file exits 2"; else bad "missing file exits 2"; fi
if printf 'Short and clear.\n' | "$LINT" -q; then ok "reads stdin"; else bad "reads stdin"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
