# Nothing about the company leaves the company

The rule with no exceptions. It binds every AI tool, every session, and every human directing
one. Read it before you push to a public repo, publish a page, paste into an external service, or
share a file outside the company.

## What counts as company content

**The test: if it appears in the company brain (`ORG_BRAIN_DIR`), it is company content.** The
brain records the codenames, repo names, team names, services, routing, and internal tooling that
only make sense inside the company. Anything in it, or of the same kind, stays inside.

The list:

- Internal codenames, service names, repo names, team names, project names.
- Colleague names, and who works on what.
- Internal hosts and URLs, the ticket tracker, the wiki, chat channels, CI, dashboards.
- Ticket keys and ticket contents.
- Source code, config, schemas, queries, log lines, and stack traces from company systems.
- Customer and partner data: names, passport numbers, payment details, bookings, emails, IPs.
- Partner and vendor names in a commercial context, contracts, rates, volumes.
- Roadmaps, incident stories, revenue, internal metrics.
- Secrets, tokens, keys, connection strings. Stricter still: these never enter a repo, a message,
  or a context window, not even inside the company.

## Where it may not go

- Any public repo, including your own personal ones.
- Gists, pastebins, public issues, pull requests on third party projects.
- Blogs, talks, social posts, screenshots, screen shares outside the company.
- Any AI tool or third party service the company has not approved. **List the approved ones here
  the day you decide them, with the date.** The generated global rules file renders company
  content into every approved provider's instruction file, and each is uploaded on every session,
  so adding an agent is a decision, not a default.
- A published page or artifact that is not gated to company accounts.
- **Commit messages and branch names in a public repo.** This is the one that catches people. The
  diff can be clean while the message names an internal repo, and then it is in public history.

## The check before an outward push

Run it when the destination is a public repo, a personal repo, or an external service. Run it
before pushing, not after: once it is public, only a force push removes it, and force push is
banned on a default branch.

1. **Name the destination.** Public or external, the check runs. Internal, it does not.
2. **Read the diff, the commit message, and the branch name.** All three, every time.
3. **Search all three against the names in the company brain**, its glossary and map files. Any
   hit is a leak.
4. **Search for the obvious markers too**: the company name, its email domain, its package
   prefix, its ticket key prefixes, internal hostnames, colleague names.
5. **A hit means the change is in the wrong repo.** Move it to a company repo.
6. **Scrubbing is allowed only when the scrubbed version stands on its own.** If removing the
   company specifics leaves something genuinely generic and useful, publish that. Redacting
   something that only makes sense internally is not scrubbing.

A working version of this gate already exists in `ORG_DEVKIT_DIR`, wired as a pre commit hook in
the public toolkit repos. Reuse it rather than writing a new one.

## Owning the repo is not permission

The public toolkit repos are yours. Your git identity owns them, and the workflow there is commit
straight to `main`, no branch, no PR, no review. That is convenient, and it is the highest risk
path on this machine, because nothing stands between a mistake and public history.

So on those repos the check above is **mandatory on every push**, without exception:

- **Every push, not just the first.** A repo that was clean last week is not clean now.
- **The commit message and the branch name, not only the diff.** A clean diff with a company repo
  name in the message still publishes that name.
- **No company names anywhere:** projects, services, codenames, hosts, ticket keys, colleague
  names, internal URLs. Not in code, comments, test fixtures, example output, screenshots, or
  file names.
- **No company specific skill, agent, or script.** If it only makes sense inside the company, it
  belongs in the company overlay repo, not the public one.
- **Found a leak after committing but before pushing?** Amend or reset. After the push it is
  public history, and force push on `main` is banned, so nothing removes it.

The mechanical gate is the pre commit hook installed in each public repo. **If the hook is
missing, disabled, or skipped, the push does not happen** until it is back. `--no-verify` is
never the answer.

Being the owner is what makes this rule necessary, not what excuses it.

## When you are unsure

Treat it as company content and ask a human. Never decide on your own that one case is harmless.

## What this does not block

Normal work inside company systems, reading public documentation, and pulling public dependencies
in. The rule is about what goes out.
