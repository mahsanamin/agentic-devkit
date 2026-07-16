# Agents

A personal, **project-agnostic** library of Claude Code sub-agents. Every agent here is generic: it carries no language, stack, company, or domain specifics, and defers to the rules of whatever project spawns it (its `AGENTS.md` / `CLAUDE.md`, `.claude/rules/`, installed standards, config, and ops skills). Invoke whichever one fits the situation while working in any project or skill.

## Conventions

- **Naming:** all agents use the `a_sag_` prefix (matching this repo's personal-namespace convention). Filename equals the frontmatter `name`.
- **Operating context:** every agent opens with an "Operating context" note stating the spawning project's conventions win, and that any path/command/tool it names is a default to replace with the project's actual equivalent. That is what keeps them reusable.
- **No em or en dashes** in any of these files (house style).
- **Models** are assigned by task tier: **Haiku** for fast mechanical execution, **Sonnet** for code understanding / testing / debugging / refactoring / docs / incident work, **Opus** for architecture, security, deep review, and production-critical decisions.

## Catalog

### Core dev loop
| Agent | Model | Role |
|-------|-------|------|
| `a_sag_code_reviewer` | opus | High-bar review (Bug/Security/Missing/Question/Trade-off only; mandatory self-review) |
| `a_sag_debugger` | sonnet | Reproduce, root-cause with evidence, fix minimally, verify |
| `a_sag_test_author` | sonnet | Write/strengthen tests against the contract; raise coverage |
| `a_sag_refactorer` | sonnet | Improve structure/readability with behavior preserved and proven |
| `a_sag_performance_optimizer` | sonnet | Measure, fix the proven hot path, measure again |
| `a_sag_plan_verifier` | sonnet | Cross-check a plan's concrete claims against real source |
| `a_sag_test_runner` | haiku (bg) | Run unit tests in background; detect skipped suites + cache false-greens |
| `a_sag_build_runner` | haiku | Build + install fresh artifact + run targeted tests (no code writing) |
| `a_sag_e2e_runner` | haiku (bg) | Run the E2E/browser suite in background, report results |

### Git / PR / docs
| Agent | Model | Role |
|-------|-------|------|
| `a_sag_commit_writer` | haiku | One clean commit message from context + diff |
| `a_sag_pr_writer` | haiku | PR title + body filled from the project's template |
| `a_sag_task_doc_writer` | haiku | Product ticket doc + technical PR-description doc for a task |
| `a_sag_docs_sync` | sonnet | Keep living reference docs in sync with the diff (surgical, verified) |
| `a_sag_dependency_upgrader` | sonnet | Bump deps, build, test, read changelogs, split clean vs risky |

### Understanding / quality / security
| Agent | Model | Role |
|-------|-------|------|
| `a_sag_codebase_explorer` | opus | Map a complex repo into CODEMAP + INVARIANTS |
| `a_sag_security_reviewer` | opus | STRIDE + OWASP threat model; verdict + severity findings |
| `a_sag_qa_evaluator` | opus | Skeptical live-app QA against acceptance criteria + rubrics |
| `a_sag_design_spec_extractor` | sonnet | Design reference into implementation-ready UI spec mapped to project tokens/assets |
| `a_sag_verification_step_generator` | sonnet | Ticket into a numbered, API-first verification checklist |
| `a_sag_prompt_engineer` | sonnet | Write/optimize prompts, agent/skill instructions, tool descriptions |

### Autonomous-build harness (Plan, Build, Review, Merge)
| Agent | Model | Role |
|-------|-------|------|
| `a_sag_spec_planner` | opus | Brief into an ambitious product SPEC |
| `a_sag_architect` | opus | SPEC into architecture/ADR doc |
| `a_sag_acceptance_contract` | opus | Testable definition of done, negotiated with QA |
| `a_sag_implementer` | opus | Implement the contract with bounded fan-out + self-eval |
| `a_sag_review_tool_liaison` | sonnet | Drive an external automated review tool, gate merge |
| `a_sag_merge_gatekeeper` | sonnet | Final merge gate across all reviewers; produce handoff |
| `a_sag_backlog_orchestrator` | sonnet | Run one backlog item through the harness, stop at the gate, two-strikes rollback |

### Incident / ops investigation pipeline
| Agent | Model | Role |
|-------|-------|------|
| `a_sag_incident_context_extractor` | haiku | Parse alert/free-text into window, resource, telemetry source, creds, freshness |
| `a_sag_observability_investigator` | sonnet | APM/metrics/trace query for the window + long-pole span attribution |
| `a_sag_error_tracker_investigator` | sonnet | Error-tracker issue + events + stack traces |
| `a_sag_warehouse_timeline_analyst` | sonnet | Parallel warehouse queries into per-entity timelines (authoritative) |
| `a_sag_incident_pattern_search` | sonnet | Has this error been seen before? memory-first classification |
| `a_sag_channel_ack_search` | sonnet | Search a partner's chat channel for prior acknowledgement (read-only) |
| `a_sag_incident_report_formatter` | opus | Synthesize all findings into a severity-rated two-zone report |
| `a_sag_service_health_check` | haiku | Walk a service pipeline of observability checks into a verdict + owner |

### Research
| Agent | Model | Role |
|-------|-------|------|
| `a_sag_crawler` | haiku | Polite cache-first web research into structured data |

### Search / recovery
| Agent | Model | Role |
|-------|-------|------|
| `a_sag_claude_session_finder` | haiku | Find a Claude Code session on this machine (live or closed) from a rough description; return the exact `claude --resume` command. Read-only |
| `a_sag_confluence_finder` | haiku | Search one project's Confluence space and return the matching pages with links. Read-only |

### Notes / external writing
| Agent | Model | Role |
|-------|-------|------|
| `a_sag_mdnest_writer` | haiku | Safe scribe for mdnest: store caller-authored markdown without corrupting code fences or Mermaid, then verify the saved note. Rules in `rules/mdnest.md` |
| `a_sag_routine_logger` | haiku | Run-visibility logger: a routine (`a_r_*`/`a_r_l_*`) calls it ONCE at the end of a run to append one dated line (when + a one-line summary) to that routine's monthly log in mdnest (`MyAutomations/ClaudeRoutines/<routine>/logs/<YYYY-MM>.md`), then verify it landed. Best-effort; no-ops if mdnest is unavailable |

## How these chain

- **Harness:** `a_sag_spec_planner` to `a_sag_architect` to `a_sag_acceptance_contract` to `a_sag_implementer` to `a_sag_qa_evaluator` to `a_sag_review_tool_liaison` to `a_sag_merge_gatekeeper`. `a_sag_backlog_orchestrator` runs one issue through that loop and stops at the gate.
- **Incident:** `a_sag_incident_context_extractor` to (`a_sag_observability_investigator` and/or `a_sag_error_tracker_investigator`) to `a_sag_warehouse_timeline_analyst` to (`a_sag_incident_pattern_search` + `a_sag_channel_ack_search`) to `a_sag_incident_report_formatter`.

## Provenance

The core dev-loop, git/PR, and task-doc agents are genericized from an upstream framework's own agents (renamed to the `a_` namespace and de-coupled from framework artifacts). The harness set comes from a Planner/Generator/Evaluator build harness, the incident set from a production payments incident workflow, and the build/design/verification/health agents from mobile and service repos, all generalized to be stack-agnostic. `a_sag_debugger`, `a_sag_test_author`, `a_sag_refactorer`, `a_sag_performance_optimizer`, `a_sag_dependency_upgrader`, and `a_sag_prompt_engineer` were added from widely-used open-source subagent collections and tuned to the same conventions.
