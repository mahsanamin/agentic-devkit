---
name: a_sk_sonarqube_coverage
description: Drive test coverage on the current change up to the project's SonarQube (or CI) coverage gate. Finds the coverage command, measures coverage on the changed/new code, writes tests following the project's testing conventions for the uncovered lines, and re-runs until the gate passes. Say "a_sk_sonarqube_coverage", "raise coverage to the gate", or "get coverage green". Generic and project-agnostic — imported from an upstream framework and de-coupled from it.
---

# a_sk_sonarqube_coverage — meet the coverage gate

An on-demand skill to raise coverage on the code you changed until the SonarQube / CI gate is satisfied. Focus is **new-code coverage** (what the gate actually checks on a PR), not chasing 100% everywhere.

## When to use
- A PR fails the SonarQube "coverage on new code" gate, or you want to pre-empt that before pushing.
- Triggers: "a_sk_sonarqube_coverage", "raise coverage to the gate", "get the SonarQube coverage green".

## Flow
1. **Find the coverage command.** In order: the project's documented coverage command (its testing rule / README / `package.json` / build config); else infer from the stack (e.g. `npm test -- --coverage`, `./gradlew test jacocoTestReport`, `pytest --cov`, `go test -cover`). Confirm the command + where it writes the report. If you can't determine it, ask.
2. **Scope to the change.** Determine the changed/new lines (`git diff <base>...HEAD`). The gate cares about coverage on those — target them, not the whole repo.
3. **Measure.** Run the coverage command, read the report, and list the uncovered new/changed lines and branches.
4. **Write tests** for the uncovered paths, following the **project's existing testing conventions** (test framework, file location/naming, assertion idioms, mocking style, module boundaries — mirror the neighbouring tests). Test real behaviour and edge cases; do not write assertion-free or trivially-passing tests just to move the number.
5. **Re-run** the coverage command and iterate until the new-code coverage clears the gate threshold. Confirm the suite is green (no skipped/failing tests masking gaps).
6. **Report** the before/after coverage on new code, which files got tests, and confirmation the gate threshold is met.

## Guardrails
- Never game the metric (no dead-code deletion to inflate %, no empty tests, no lowering the threshold).
- Don't modify production code to make it "look" covered; if code is untestable, say so and suggest the minimal refactor.

## Done-when
New-code coverage meets the gate, all tests pass, and the added tests are meaningful. Report the numbers.
