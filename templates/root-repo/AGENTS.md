# Agent instructions: {{ORG_NAME}}

**Read [`ROOT.md`](ROOT.md) in this repo and follow it.** It is the starting point for all work
for this company, for every AI tool. Everything else is one hop from there.

Two things you must not skip:

- [`root.config`](root.config) tells you where every other repo sits on this machine. Nothing
  else hardcodes a path. An empty value means that repo is not on this machine, which is normal.
- [`rules/boundary.md`](rules/boundary.md) is the rule with no exceptions: nothing about the
  company leaves the company. Read it before you paste, publish, push, or share anything outward.

`AGENTS.md` is the canonical instruction file in this repo and in every repo it governs.
`CLAUDE.md` and `GEMINI.md` only import it, so every agent gets the same contract and there is
still one copy. How to set up or update the toolkit is the toolkit's own business, and it says so
in `DEVKIT_DIR`.

## Using this from another repo

Put a file like this one at the top of that repo, with an absolute path to this repo's `ROOT.md`
instead of the relative link. Get the path from `ROOT_DIR` in `root.config`. Then that repo's
agent starts here, and there is still one copy of the rules.
