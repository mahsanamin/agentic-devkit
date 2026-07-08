---
name: a_sk_commit
description: Create a clean, human-readable git commit for the current changes. Groups the diff into a coherent commit, writes a clear message in the project's style, and commits (respecting the repo's permission posture). Say "a_sk_commit" or "commit" when ready to commit. Generic and project-agnostic — imported from the AI-Awareness framework (aa-commit) and de-coupled from it.
---

# a_sk_commit — clean git commit

An on-demand skill to turn the current working changes into a well-scoped commit with a message a human would be glad to read. It delegates the message wording to the `a_sag_commit_writer` agent and keeps the git actions here. No task-flow / config-file coupling.

## When to use
- You've finished a logical unit of work and want to commit it cleanly.
- Triggers: "commit", "a_sk_commit", "commit this".

## Flow
1. **Survey the change.** `git status` + `git diff` (staged and unstaged). If the changes span unrelated concerns, group them and commit in logical chunks rather than one blob — stage per chunk (`git add -p` / per-file).
2. **Match the repo's conventions.** Look at recent history (`git log --oneline -20`) for the message style: Conventional Commits (`feat(scope): …`), ticket prefixes, sentence case, etc. Follow whatever the repo already does. Respect the global no-em-dash rule.
3. **Draft the message** by invoking the **`a_sag_commit_writer`** agent with the diff + any ticket/context. It returns the message text only; it does not run git.
4. **Show, then commit** per the repo's permission posture:
   - Default (`ask`): show the staged diff summary + the drafted message, get approval, then `git commit`.
   - Autonomous (`git add`/`commit`/`push` already in `.claude/settings.json` `allow`): commit deliberately at meaningful checkpoints with the same care, narrating *"Committing at checkpoint: <what>"*. Don't ask redundantly, don't commit noisily.
5. **Never force-push.** Pushing is a separate, explicit step — only if asked.

## Done-when
A commit exists with a clear, convention-matching message; unrelated changes weren't lumped together; nothing was pushed unless explicitly requested. Report the commit hash + subject.
