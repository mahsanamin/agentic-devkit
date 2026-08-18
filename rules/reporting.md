# Reporting rules (canonical)

Single source of truth for how Claude turns findings into a report, a status update, a
digest, or a summary that someone else will act on. Applies to any routine or skill that
publishes to an audience. If a rule changes, change it here.

The whole file exists to prevent one failure: **publishing what somebody said as though it
were established fact.** That failure is worse than an incomplete report, because it
launders a guess into a finding, and the finding then gets copied forward and starts
driving decisions nobody re-checks.

## The verification gate

Run this over the whole draft before it ships, not just over the parts that came from chat.

1. **Split every claim into verified or conversational.** Verified means you derived it
   yourself from a system of record this session (logs, observability, the DB, git/PR
   state, the tracker, provider or payment records, deploy history). Conversational is
   anything sourced from a person, a chat message, a ticket comment, or a prior report.
2. **If a conversational claim is checkable here, check it.** Then publish the verified
   fact and discard the claim. "It was easier to quote the message" is not a reason. If
   you have the access, not using it is a defect, not a shortcut.
3. **Never restate borrowed specifics.** Dates, times, counts, amounts, currencies,
   identities, locations, and "first / only / none / never" superlatives are exactly the
   values that get garbled as a claim is retold. Re-derive each one or leave it out. A
   wrong specific is worse than a missing one, because a specific reads as evidence.
4. **Check whether several signals are actually one signal.** Alarming details often turn
   out to be one fact restated, or one fact and its own downstream consequence. Establish
   that each is independently sourced before letting them stack into a severity.
5. **When verification contradicts the claim, publish the correction** and say plainly
   that the earlier understanding was wrong. Do not quietly soften it, and never carry
   both versions side by side.
6. **When a claim cannot be verified here, label it and name the check.** Write it as an
   open question carrying the one concrete check that would settle it, and who owns that
   check. Never state it as a finding.
7. **Absence of evidence is not evidence.** Before writing "no X found", establish that
   the source would have recorded an X at all, and state the denominator. A source that
   only logs exceptions cannot prove a clean case, and a zero over a sample of one proves
   nothing.
8. **Severity follows verification.** An unverified claim never holds the top severity
   band. Escalate on verified impact only; otherwise it sits at the lowest band as an
   open question.
9. **Never inherit an unverified claim from a prior report.** Re-verify it or downgrade
   it. Repetition across editions is what turns a guess into an apparent fact, and a claim
   that has ridden two reports unchecked is a bug in the routine, not a standing risk.

## Tells to catch in your own draft

- A specific you did not derive yourself.
- A cluster of alarming details that collapses to one fact once you trace each to a source.
- A "we cannot tell" about a system you can actually query.
- A risk carried over verbatim from the previous edition.
- A hedge doing the work a check should have done.

When you catch one, go verify it and rewrite the item. **Never publish the hedge.**

## Attribution is not a licence

Marking a claim "per <source>" records where it came from. It does not make it publishable
unchecked, and it must never be used to pass off an unverified assertion as reporting.

## Closing a run

State which conversational claims you verified and against what source, which you
corrected, and which you published as labelled open questions. A run that published an
unlabelled conversational claim is incomplete, even if everything else landed.
