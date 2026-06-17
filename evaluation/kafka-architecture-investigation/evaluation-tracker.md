# kafka-architecture-investigation Evaluation Tracker

Use this file as the active watch/update surface for the validation ladder. Keep it concise. Put detailed logs and generated artifacts under `evaluation-runs/`; keep design rationale and phase details in `evaluation-plan.md`.

## Current Cursor

- Active phase: F-small-kafka-golden-path
- Status: pending
- Next action: Confirm whether to proceed into the small Kafka golden-path gate, because this is the first phase requiring Kafka/Docker harness work.
- Stop/ask user when: a run requires higher-cost models, a Kafka/Docker harness, external network-heavy source research, or real Kafka implementation work.

## Validation Ladder

| Phase | Status | Purpose | Gate | Evidence |
| --- | --- | --- | --- | --- |
| A-repeat-cheap-smokes | done | Check repeatability of trigger, tracker-first behavior, known-fact capture, question count, and no premature research/build. | 3-5 clean runs pass or produce only skill/harness fixes. | Clean passes: `evaluation-runs/20260616-115218/summary.md`, `evaluation-runs/20260616-170935/summary.md`, `evaluation-runs/20260616-171704/summary.md`. |
| B-prompt-variants | done | Check generalization across snapshot restore, cluster linking, transactions, backup-tool validation, and vague Kafka architecture prompts. | Each variant stays in S01, captures known facts, asks focused questions, and avoids premature research/build. | Passed variants: `phase-b-cluster-linking-20260616-172436`, `phase-b-transactions-20260616-172932`, `phase-b-backup-tool-20260616-173210`, `phase-b-vague-20260616-173354`. |
| C-resume-intake-loop | done | Check tracker-first resume behavior from partial S01 workspaces. | Agent reads only active `Read Now`, preserves prior facts, asks only missing questions, and marks S01 done only at the gate. | Passed two-case runner: `evaluation-runs/phase-c-resume-20260616-182639/summary.md`. |
| D-adr-scenario-spec-no-kafka | done | Check ADR gate and scenario/spec expansion with fake/simple research inputs, without Kafka/Docker cost. | ADR exists before detailed scenarios; scenarios map objective -> ADR claim -> deterministic test; spec has small executable steps. | Passed three-case runner: `evaluation-runs/phase-d-docs-20260617-104908/summary.md`. |
| E-toy-autonomous-loop | done | Check autonomous implementation loop with shell-testable toy steps. | Agent executes next pending step, validates, updates evidence/status, and continues until done or blocked. | Passed toy runner: `evaluation-runs/phase-e-toy-loop-20260617-110322/summary.md`. |
| F-small-kafka-golden-path | pending | Check real Kafka harness contract with a minimal KRaft lab and one baseline scenario. | Fixed paths, `reset -> seed -> capture -> mutate -> start -> assert -> report`, and evidence under `artifacts/kafka-architecture-investigation/`. | |
| G-historical-complex-benchmark | pending | Run one expensive confidence benchmark from prior real patterns. | Produces decision-grade report/runbook and records proven, falsified, untested, and uncertain items. | |

## Run Log

| Date | Phase | Model/Effort | Result | Tokens | Evidence | Notes |
| --- | --- | --- | --- | ---:| --- | --- |
| 2026-06-15 | A | `gpt-5.3-codex-spark`/low | blocked | unknown | `evaluation-runs/20260615-144704/summary.md` | sbx had API-key/proxy auth despite `codex login status`. |
| 2026-06-16 | A | `gpt-5.3-codex-spark`/low | blocked | unknown | `evaluation-runs/20260616-110824/summary.md` | Copied ChatGPT auth was revoked by sandbox `codex logout`; helper fixed to delete auth cache locally. |
| 2026-06-16 | A | `gpt-5.3-codex-spark`/low | failed | 14280 | `evaluation-runs/20260616-111340/summary.md` | Skill created correct files and asked questions, but did not capture known facts; scorer also had false negatives. |
| 2026-06-16 | A | `gpt-5.4-mini`/low | passed | 14532 | `evaluation-runs/20260616-115218/summary.md` | Captured KRaft and reduced-broker facts, asked four intake questions, no premature research/build. |
| 2026-06-16 | A | `gpt-5.4-mini`/low | failed | 13552 | `evaluation-runs/20260616-170108/summary.md` | Hand-rolled a short tracker instead of copying the canonical tracker; fixed with `bootstrap-investigation.sh` and stricter scoring. |
| 2026-06-16 | A | `gpt-5.4-mini`/low | passed | 16740 | `evaluation-runs/20260616-170935/summary.md` | Canonical tracker structure preserved after bootstrap script fix; asked four intake questions. |
| 2026-06-16 | A | `gpt-5.4-mini`/low | failed-after-review | 8720 | `evaluation-runs/20260616-171307/summary.md` | Summary passed, but manual inspection found S01 Current Cursor dropped `references/intake.md`; fixed tracker template and scorer with `s01_cursor_complete`. |
| 2026-06-16 | A | `gpt-5.4-mini`/low | passed | 14628 | `evaluation-runs/20260616-171704/summary.md` | Passed stricter gate with full S01 cursor, known facts captured, four questions, and no premature research/build. |
| 2026-06-16 | B | `gpt-5.4-mini`/low | passed | 12793 | `evaluation-runs/phase-b-cluster-linking-20260616-172436/summary.md` | Captured Cluster Linking, mirror promotion, and cutover facts; asked four cutover-specific questions. |
| 2026-06-16 | B | `gpt-5.4-mini`/low | failed | 15644 | `evaluation-runs/phase-b-transactions-20260616-172634/summary.md` | Harness ran Codex from `/home/agent/workspace`, so files were written outside the target; fixed runner to use `--cd "$TARGET_DIR"`. |
| 2026-06-16 | B | `gpt-5.4-mini`/low | passed | 8943 | `evaluation-runs/phase-b-transactions-20260616-172932/summary.md` | Captured transactional IDs and `read_committed`; asked four transaction-specific questions. |
| 2026-06-16 | B | `gpt-5.4-mini`/low | passed | 10896 | `evaluation-runs/phase-b-backup-tool-20260616-173210/summary.md` | Captured backup-tool recovery claim, internal topics, offsets, and transaction state. |
| 2026-06-16 | B | `gpt-5.4-mini`/low | passed | 14173 | `evaluation-runs/phase-b-vague-20260616-173354/summary.md` | Preserved unknowns and asked three broad orientation questions without inventing a track. |
| 2026-06-16 | C | `gpt-5.4-mini`/low | failed | 26632 | `evaluation-runs/phase-c-resume-20260616-180923/summary.md` | Expanded runner exposed a real cursor defect: ready S01 advanced to S02 but omitted `SOURCE_RESEARCH.md` from Current Cursor. |
| 2026-06-16 | C | `gpt-5.4-mini`/low | failed | 19531 | `evaluation-runs/phase-c-resume-20260616-181741/summary.md` | Cursor instructions improved but ready case still hand-edited cursor incorrectly; added deterministic `update-tracker-state.py`; also fixed question/no-harness scorer false positives. |
| 2026-06-16 | C | `gpt-5.4-mini`/low | passed | 18315 | `evaluation-runs/phase-c-resume-20260616-182639/summary.md` | Partial S01 stayed in S01 and asked four questions; ready S01 used tracker updater, advanced to S02, and created no research/spec/harness artifacts. |
| 2026-06-17 | D | `gpt-5.4-mini`/low | failed | 49609 | `evaluation-runs/phase-d-docs-20260617-102539/summary.md` | Exposed Phase D quality gaps: source claims lost stable IDs/confidence discipline; S04 scorer confused prompt text with harness work and missed TSV status issues. |
| 2026-06-17 | D | `gpt-5.4-mini`/low | failed | 56562 | `evaluation-runs/phase-d-docs-20260617-103240/summary.md` | Claim IDs were preserved, but source confidence invented `offline source fixture`; S04 matrix had valid field count but invalid statuses such as `S01 planned`. |
| 2026-06-17 | D | `gpt-5.4-mini`/low | invalid | 43563 | `evaluation-runs/phase-d-docs-20260617-103808/summary.md` | Runner passed but emitted a shell prompt-substitution error from unescaped backticks; fixed prompt quoting before accepting evidence. |
| 2026-06-17 | D | `gpt-5.4-mini`/low | passed | 60694 | `evaluation-runs/phase-d-docs-20260617-104908/summary.md` | S02 source research, S03 ADR, and S04 scenario/spec passed strict gates; no external research, harness files, Docker, or Kafka runtime used. |
| 2026-06-17 | E | `gpt-5.4-mini`/low | failed | 14695 | `evaluation-runs/phase-e-toy-loop-20260617-110015/summary.md` | Toy loop executed scripts and updated tracker, but used invalid scenario status `done`; scenarios must use `passed`/`failed` etc. |
| 2026-06-17 | E | `gpt-5.4-mini`/low | passed | 15584 | `evaluation-runs/phase-e-toy-loop-20260617-110322/summary.md` | Executed reset/seed/capture/mutate/start/assert/report, wrote artifacts, marked implementation steps done, scenario passed, and advanced cursor to S07. |

## Open Follow-Ups

- Add a repeat-runner or prompt-fixture runner when Phase B manual repetition becomes tedious.
- Keep `gpt-5.4-mini` low as the default smoke model; use Spark only when available and worth testing.
- Promote the sbx auth-copy pattern into the future generic sbx skill after a few more successful runs.
- Keep tracker phase names aligned with `evaluation-plan.md`'s A-G robustness ladder.
- Decide whether Phase D fake research fixtures should be templates, generated setup scripts, or checked-in sample workspaces.
- Phase D S04 is token-heavy; consider splitting scenario/spec checks if repeated regression runs become too costly.
- Phase F requires real Kafka/Docker work; confirm before running because it crosses the current stop/ask boundary.
