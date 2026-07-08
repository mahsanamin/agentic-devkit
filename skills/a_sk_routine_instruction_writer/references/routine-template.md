# Hardened routine-instruction template

A reusable skeleton for the finished instruction prompt. Not every routine needs every section; drop what does not apply and say why. The point is that an unattended Claude reading this once per run has everything it needs and cannot wander outside its bounds.

```
You <one-line role: what this routine owns>. Run autonomously; never ask the
user questions. If you hit a genuinely blocking decision, stop and put it in
the final report instead of guessing.

Derived inputs:
- <input> = <how to compute it deterministically, e.g. current month -> tag>
  (so the routine never depends on a value a human types at run time)

Hard rules (apply throughout):
- <what is forbidden / the blast-radius cap, e.g. never push to main>
- <what "done" means, e.g. the full suite passes, not just a compile>
- <how to tell a real failure from a flake, and what to do about flakes>

Phase 0 - Discover:
- <gather the work list>. If there is nothing to do, write a one-line
  "nothing to do" report and stop. (Most scheduled runs are no-ops; exiting
  quietly keeps the log clean and avoids busywork.)

Phase 1 .. N - <the actual work>:
- <numbered, concrete steps; include exact commands where they help>
- <a confidence gate that separates machine-verifiable "green" from
  "looks done but a machine cannot prove it," routing the second kind to a
  human via the report>

Final phase - hand off:
- <the human-gated or outward-facing action, clearly bounded>

End every run with a short report: what was found, what was done, what was
held back for a human, and any links produced.
```

## Section rationale (why each piece earns its place)

- **Role + autonomy line.** An unattended run cannot ask questions, so the first thing it needs to know is "you are on your own, here is your lane."
- **Derived inputs.** Anything a human would normally supply (a date, a tag, a version, a branch name) must be computed from the environment, or the routine stalls waiting for input that never comes.
- **Hard rules up front.** The executing model reads these before it acts, so put the irreversible/outward-facing limits where they cannot be missed. Prefer capping blast radius over trusting the model to be careful.
- **Quiet no-op exit.** The common case for a scheduled routine is "nothing changed today." Without an explicit early exit, the model invents work or writes noise.
- **Two-tier confidence gate.** Tests passing is necessary but not always sufficient. Changes a machine cannot validate (runtime images never booted in CI, deploy/auth paths, external-service compatibility) must be flagged for a human even when green.
- **Closing report.** The only window the user has into an unattended run. Make it short and scannable: found / done / held back / links.

## Context wrappers

The same hardened body slots into different runners:
- **Scheduled / local / cloud routine:** the full template above. Watch the form fields too (do not double up worktree isolation; a prompting permission mode defeats unattended runs, a permissive one removes the human gate, so name the tradeoff).
- **/goal:** lead with the end state to hold; the condition is the directive.
- **/loop:** state the per-iteration unit of work and the stop/continue condition.
- **One-off skill or prompt:** mid-run questions are fine; optimize for a single careful pass instead of a quiet no-op.
