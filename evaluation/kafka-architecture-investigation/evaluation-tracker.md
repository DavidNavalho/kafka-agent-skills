# kafka-architecture-investigation Evaluation Tracker

Use this file as the active watch/update surface for the validation ladder. Keep it concise. Put detailed logs and generated artifacts under `evaluation-runs/`; keep design rationale in `evaluation-plan.md`.

## Current Cursor

- Active phase: A-repeat-cheap-smokes
- Status: in_progress
- Next action: Run 2-4 more clean tracker-first smokes with `gpt-5.4-mini` low and different `RUN_SET` values.
- Stop/ask user when: a run requires higher-cost models, a Kafka/Docker harness, external network-heavy source research, or real Kafka implementation work.

## Validation Ladder

| Phase | Status | Purpose | Gate | Evidence |
| --- | --- | --- | --- | --- |
| A-repeat-cheap-smokes | in_progress | Check repeatability of trigger, tracker-first behavior, known-fact capture, question count, and no premature research/build. | 3-5 clean runs pass or produce only skill/harness fixes. | `evaluation-runs/20260616-115218/summary.md` passed once with `gpt-5.4-mini` low. |
| B-prompt-variants | pending | Check generalization across snapshot restore, cluster linking, transactions, backup-tool validation, and vague Kafka architecture prompts. | Each variant stays in S01, captures known facts, asks focused questions, and avoids premature research/build. | |
| C-resume-intake-loop | pending | Check tracker-first resume behavior from partial S01 workspaces. | Agent reads only active `Read Now`, preserves prior facts, asks only missing questions, and marks S01 done only at the gate. | |
| D-adr-scenario-spec-no-kafka | pending | Check ADR gate and scenario/spec expansion with fake/simple research inputs, without Kafka/Docker cost. | ADR exists before detailed scenarios; scenarios map objective -> ADR claim -> deterministic test; spec has small executable steps. | |
| E-toy-autonomous-loop | pending | Check autonomous implementation loop with shell-testable toy steps. | Agent executes next pending step, validates, updates evidence/status, and continues until done or blocked. | |
| F-small-kafka-golden-path | pending | Check real Kafka harness contract with a minimal KRaft lab and one baseline scenario. | Fixed paths, `reset -> seed -> capture -> mutate -> start -> assert -> report`, and evidence under `artifacts/kafka-architecture-investigation/`. | |
| G-historical-complex-benchmark | pending | Run one expensive confidence benchmark from prior real patterns. | Produces decision-grade report/runbook and records proven, falsified, untested, and uncertain items. | |

## Run Log

| Date | Phase | Model/Effort | Result | Tokens | Evidence | Notes |
| --- | --- | --- | --- | ---:| --- | --- |
| 2026-06-15 | A | `gpt-5.3-codex-spark`/low | blocked | unknown | `evaluation-runs/20260615-144704/summary.md` | sbx had API-key/proxy auth despite `codex login status`. |
| 2026-06-16 | A | `gpt-5.3-codex-spark`/low | blocked | unknown | `evaluation-runs/20260616-110824/summary.md` | Copied ChatGPT auth was revoked by sandbox `codex logout`; helper fixed to delete auth cache locally. |
| 2026-06-16 | A | `gpt-5.3-codex-spark`/low | failed | 14280 | `evaluation-runs/20260616-111340/summary.md` | Skill created correct files and asked questions, but did not capture known facts; scorer also had false negatives. |
| 2026-06-16 | A | `gpt-5.4-mini`/low | passed | 14532 | `evaluation-runs/20260616-115218/summary.md` | Captured KRaft and reduced-broker facts, asked four intake questions, no premature research/build. |

## Open Follow-Ups

- Add a repeat-runner or prompt-fixture runner when Phase A/B manual repetition becomes tedious.
- Keep `gpt-5.4-mini` low as the default smoke model; use Spark only when available and worth testing.
- Promote the sbx auth-copy pattern into the future generic sbx skill after a few more successful runs.
- Decide whether Phase D fake research fixtures should be templates, generated setup scripts, or checked-in sample workspaces.
