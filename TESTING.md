# Skill Testing

This is the testing index for every published skill in this repository. It distinguishes deterministic script tests, fresh-context agent evaluations, and live integration runs. Generated `evaluation-runs/` directories are ignored; durable summaries and harnesses are linked below.

## Current status

| Skill | Latest recorded confidence | Important remaining gap |
| --- | --- | --- |
| `run-agents-in-sbx` | Static/mock lifecycle suite, a 6/6 authenticated live boundary matrix, and a final-semantic 9/9 low-effort fresh-context matrix across three models. | Real auth-refresh, cancellation, and cleanup-failure recovery remain mock-tested only; the model sample is finite and has no no-skill control. |
| `kafka-local-lab` | Public release baseline passed 12/12 Codex and Claude scenarios on 2026-04-27. | Negative host-failure paths are not all represented in the release matrix. |
| `kafka-architecture-investigation` | Evaluation ladder phases A-E passed through a deterministic toy autonomous loop on 2026-06-17. | The real Kafka golden path and historical complex benchmark, phases F-G, are pending. |

## `run-agents-in-sbx`

Testing has three layers:

1. [`run-static-tests.sh`](evaluation/run-agents-in-sbx/run-static-tests.sh) checks shell/Python syntax, opt-in refusal, timeout enforcement, auth-file permissions, bounded live-owner waiting, ambiguous-lock preservation, handoff validation, sandbox identity mismatch, success, auth refresh, timeout, invalid handoff, cleanup, both scorers, credential non-disclosure, guest CLI setup before auth copy, and a complete mocked fresh-context matrix.
2. [`run-live-boundary-eval.sh`](evaluation/run-agents-in-sbx/run-live-boundary-eval.sh) is an explicit opt-in test that copies real file-backed ChatGPT auth into generated trusted sandboxes. It runs both Codex postures and scores owned writes, read-only enforcement, hidden unmounted state, API-key environment removal, network-policy capture, handoff evidence, auth-cache stability, credential leakage, and sandbox removal.
3. [`run-fresh-context-matrix.sh`](evaluation/run-agents-in-sbx/run-fresh-context-matrix.sh) gives new low-effort agents only a natural mixed-trust request, an output schema, and an immutable read-only snapshot of the skill. A host-only scorer gates workspace ownership, exact auth placement, auth-lineage serialization, untrusted-code isolation, timeout, handoff, changed-auth recovery, leakage, and cleanup. The skill, runner, scorer, and fixtures are snapshotted once and content-digested so every cell evaluates one fixed candidate.

Latest authenticated results: three consecutive `outer` runs and three consecutive `workspace-write` runs passed (6/6) on 2026-07-15. On 2026-07-20, three repetitions each of `gpt-5.6-sol`, `gpt-5.5`, and `gpt-5.3-codex-spark`, all at low reasoning effort, passed the final semantic and lifecycle gate (9/9). The raw matrix was 8/9 before removing one redundant summary-list requirement from the host-only scorer; the typed safety decision was correct in the affected output, and the calibration is retained in the baseline. These finite cells are cross-model evidence, not a guarantee for every model. See the [detailed results](evaluation/run-agents-in-sbx/evaluation-results.md).

Run the deterministic suite:

```bash
evaluation/run-agents-in-sbx/run-static-tests.sh
```

Preview and deliberately authorize the live test:

```bash
evaluation/run-agents-in-sbx/run-live-boundary-eval.sh --plan
ALLOW_REAL_CODEX_AUTH=1 evaluation/run-agents-in-sbx/run-live-boundary-eval.sh
```

The live harness refuses to run without the opt-in variable. If auth changes or becomes ambiguous, follow the preserved sandbox's recovery instructions rather than deleting it.

Preview and deliberately authorize the low-effort fresh-context matrix:

```bash
evaluation/run-agents-in-sbx/run-fresh-context-matrix.sh --plan
ALLOW_REAL_CODEX_AUTH=1 \
evaluation/run-agents-in-sbx/run-fresh-context-matrix.sh \
  --models "gpt-5.6-sol gpt-5.5 gpt-5.3-codex-spark" \
  --efforts low \
  --auth-lock-wait 86400 \
  --guest-codex-version 0.145.0-alpha.13 \
  --repetitions 3
```

Authenticated evaluations are intentionally local and operator-triggered. This repository does not add CI that would either reduce the check to shallow linting or require unattended subscription/API credentials.

- [Evaluation plan](evaluation/run-agents-in-sbx/evaluation-plan.md)
- [Detailed results](evaluation/run-agents-in-sbx/evaluation-results.md)
- [2026-07-20 low-effort baseline](evaluation/run-agents-in-sbx/baselines/fresh-context-low-effort-20260720.md)

## `kafka-local-lab`

The model-matrix harness installs only the skill under test into `sbx`, gives the agent a natural prompt, inspects generated configuration, starts the Docker Compose lab, and requires component-specific runtime smoke tests. Built-in scenarios cover default Apache Kafka, Confluent Kafka, Schema Registry, Kafka Connect, AKHQ, and the full stack.

The 2026-04-27 release baseline ran all six scenarios with Codex `gpt-5.4-mini`/low and Claude `haiku`/low: 12/12 cells matched expected configuration and passed their required smoke checks. Earlier Codex model-comparison and option-specific runs are also recorded.

- [Evaluation plan](evaluation/kafka-local-lab/evaluation-plan.md)
- [Evaluation results](evaluation/kafka-local-lab/evaluation-results.md)
- [Model-matrix harness](evaluation/kafka-local-lab/run-model-matrix.sh)

## `kafka-architecture-investigation`

This skill uses a staged evaluation ladder. Fresh-context agents are scored on tracker-first intake, known-fact capture, prompt variants, resume behavior, source/ADR/scenario gates, and an autonomous implementation loop. The ladder intentionally starts with cheaper document and toy-runtime checks before real Kafka work.

Completed phases A-E cover repeated intake smokes, four architecture variants, partial-workspace resume, source-to-ADR-to-scenario/spec progression, and a shell-testable autonomous loop. Failed and invalid intermediate runs are retained in the tracker because they drove fixes to cursor management, source confidence, prompt quoting, and scenario statuses.

Phases F-G are explicitly not complete: the skill has not yet passed its small real Kafka golden path or the historical complex benchmark.

- [Evaluation plan](evaluation/kafka-architecture-investigation/evaluation-plan.md)
- [Evaluation tracker and run log](evaluation/kafka-architecture-investigation/evaluation-tracker.md)
- [Low-cost sbx smoke harness](evaluation/kafka-architecture-investigation/run-sbx-smoke.sh)
