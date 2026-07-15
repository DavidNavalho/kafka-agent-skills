# Skill Testing

This is the testing index for every published skill in this repository. It distinguishes deterministic script tests, fresh-context agent evaluations, and live integration runs. Generated `evaluation-runs/` directories are ignored; durable summaries and harnesses are linked below.

## Current status

| Skill | Latest recorded confidence | Important remaining gap |
| --- | --- | --- |
| `run-agents-in-sbx` | Static/mock lifecycle suite plus a 6/6 authenticated live boundary matrix on 2026-07-15. | Real auth-refresh, cancellation, and cleanup-failure recovery remain mock-tested only. |
| `kafka-local-lab` | Public release baseline passed 12/12 Codex and Claude scenarios on 2026-04-27. | Negative host-failure paths are not all represented in the release matrix. |
| `kafka-architecture-investigation` | Evaluation ladder phases A-E passed through a deterministic toy autonomous loop on 2026-06-17. | The real Kafka golden path and historical complex benchmark, phases F-G, are pending. |

## `run-agents-in-sbx`

Testing has three layers:

1. [`run-static-tests.sh`](evaluation/run-agents-in-sbx/run-static-tests.sh) checks shell/Python syntax, opt-in refusal, host timeout enforcement, auth-file permissions, live lock contention, handoff validation, sandbox identity mismatch, success, auth refresh, timeout, invalid handoff, cleanup, the live scorer, and credential non-disclosure using mock `sbx` and Codex executables.
2. A fresh-context agent evaluation required an agent to plan a realistic sandboxed task from the skill alone. It selected the correct worktree, read-only context, posture, credential disclosure, handoff, and recovery behavior. That evaluation exposed a malformed-handoff preservation gap, which was fixed before the live run.
3. [`run-live-boundary-eval.sh`](evaluation/run-agents-in-sbx/run-live-boundary-eval.sh) is an explicit opt-in test that copies real file-backed ChatGPT auth into generated trusted sandboxes. It runs both Codex postures and scores owned writes, read-only enforcement, hidden unmounted state, API-key environment removal, network-policy capture, handoff evidence, auth-cache stability, credential leakage, and sandbox removal.

Latest authenticated result: three consecutive `outer` runs and three consecutive `workspace-write` runs passed (6/6) with `sbx v0.35.0`, `codex-cli 0.144.4`, `gpt-5.4-mini`, and low reasoning effort. The effective network policy included `default-allow-all`, so the result proves filesystem and lifecycle boundaries, not egress restriction. See the [detailed result](evaluation/run-agents-in-sbx/evaluation-results.md).

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
