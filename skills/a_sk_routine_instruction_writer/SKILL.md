---
name: a_sk_routine_instruction_writer
description: Turn a rough, half-formed task description into a clean, self-contained instruction prompt for an autonomous or scheduled routine (Claude Code local/cloud routine, /goal, /loop, /schedule, or a reusable skill). Vets the raw text, fixes typos and ambiguity, clarifies only the decisions that change the steps, verifies the plan against a prior real run when a reference exists (a PR, a past routine, a transcript), and hardens the result for unattended execution. Use when the user says "write this routine instruction", "make this prompt count", "clean up this prompt so Claude does it right", pastes a draft for a scheduled/local routine, or asks to author instructions for a recurring/automated task.
---

# a_sk_routine_instruction_writer

You help the user turn a rough task description into an instruction prompt that another Claude (often an unattended, scheduled one) can execute correctly every time. The output is the artifact. Treat the user's draft as intent, not final wording, and make it count.

## What "good" looks like

A finished instruction prompt is:
- **Self-contained.** It assumes no chat history. Everything needed to act is in the text.
- **Directive.** Written as commands to the executing Claude ("You maintain...", "Run...", "Do not merge..."), not as a description of what the user wants.
- **Deterministic.** No "ask the user" steps if it runs unattended. Defaults are derived, not prompted (dates, tags, versions, branch names).
- **Bounded.** The blast radius is explicit and capped. Destructive or outward-facing actions (merge to main, push, deploy, send) are either forbidden or clearly gated.
- **Honest about confidence.** It distinguishes "verified green" from "looks done but a machine can't prove it," and routes the second kind to a human.
- **Clean prose.** Follow the user's global writing rules. Never use em or en dashes; restructure with commas, periods, colons, parentheses, or words.

## Process

Work through these in order. Skip a step only when it clearly does not apply, and say so.

### 1. Restate the intent
Read the raw draft and write back, in two or three sentences, what you believe they are trying to automate. Fix the typos silently in your understanding. This catches misreads before you invest in structure. If the draft is already clear, keep this short.

### 2. Clarify only what changes the steps
Use `AskUserQuestion` for genuine forks where the answer changes the instructions, not for things you can default sensibly. Good candidates: naming conventions, autonomy level (how far it may go before a human gate), fix aggressiveness, what counts as done. Bad candidates: anything with an obvious default, or detail you can infer. Recommend an option and put it first. One round of questions is usually enough; do not interrogate.

### 3. Verify against reality when a reference exists
If the user points to a prior run (a PR URL, a past routine, a transcript, a ticket), inspect it before finalizing. This is the highest-leverage step: a real outcome exposes where the plan is too optimistic.
- For a PR: `gh pr view <n> --repo <owner/repo> --json title,state,body,commits,files,baseRefName,headRefName`. Read the body's risk notes, the fix commits (what broke that the bot did not anticipate), and whether it actually merged or stayed open.
- Extract the corrections the reality forces, and fold them in. Common patterns: green CI is necessary but not sufficient for some classes of change; a tool overshoots and needs partial override; transient infra failures masquerade as real ones; deduplication is needed before fan-out.
- State the verdict plainly: does the plan match what worked, and what did you change.

### 4. Adapt to the execution context
Ask yourself (or the user) where this will run, because it changes the wrapper:
- **Scheduled / local / cloud routine (runs unattended, e.g. daily):** no mid-run questions; derive every input; **exit quietly on no-op runs** (the common case is "nothing to do today"); end with a short report; consider the permission mode (a prompting mode defeats unattended runs, a permissive one removes the human in the loop, so name the tradeoff). Watch for form-level gotchas: if the routine form has its own worktree-isolation toggle and the instructions also create worktrees, do not enable both.
- **/goal:** the condition is the directive; the instruction should describe the end state to hold.
- **/loop:** state the per-iteration unit of work and the stop/continue condition.
- **One-off skill or prompt:** mid-run questions are fine; optimize for a single careful pass.

### 5. Structure the body
Start from the skeleton in `references/routine-template.md` and fill it in. It encodes the section order that works for operational routines (role + autonomy line, derived inputs, hard rules, a quiet no-op exit, numbered phases, a two-tier confidence gate, a closing report) and the rationale for each, plus the small adjustments for /goal, /loop, and one-off prompts. Read it before writing the body so you do not reinvent the structure each time. Deviate when the task genuinely calls for it.

### 6. Deliver and place it
Present the finished instruction as a clean block the user can paste. Then ask where it should live if not already known: pasted into a routine form, saved to a repo file (version-controlled), wrapped via `/schedule` or `/loop`, or turned into its own skill. Flag any form-field choices they still need to make.

## Worked example (the transformation this skill performs)

**Input (raw draft the user pasted):**
> watch the dependabot prs, fix the errors, use a worktree and spin agents to work parallel, update branches with main first, run tests, then find release/dependabot<version> if it exists update it with main and repoint the new dependabot prs to it, else create it

**What the skill does with it:** restate the intent in two sentences; ask only the forks that change steps (what `<version>` means, how aggressive the fixes should be, how far it may go before a human gate); pull the prior consolidation PR the user references and discover that green CI did not prove the runtime-image and deploy-auth bumps worked, that the bot overshot a JDK version, and that infra flakes looked like real failures; then emit a hardened, self-contained instruction with derived inputs (tag = current month), a quiet no-op exit, a two-tier confidence gate, and "never merge to main" as a hard rule.

The lesson the example carries: the value is not retyping the draft neatly. It is the clarifying forks, the reality check against a prior run, and the unattended-execution hardening. A polished restatement that still asks questions mid-run, trusts green CI blindly, or has no blast-radius cap has failed.

## Guardrails
- Do not invent steps the user did not intend. When you add something (a no-op exit, a dedup pass, a risk-note section), it should trace to either their intent, a clarifying answer, or a lesson from the verified reference. Say why you added it.
- Prefer capping blast radius over trusting the model. If unsure whether an action is safe to automate, gate it behind a human.
- Keep the prose tight. The executing Claude reads this every run; every sentence should earn its place.
- Never use em dashes or en dashes anywhere in the output.
