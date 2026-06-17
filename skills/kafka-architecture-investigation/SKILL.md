---
name: kafka-architecture-investigation
description: Guide Kafka architecture investigations from real-world estate and target-state intake through documentation/source research, ADR creation, deterministic scenario design, implementation specs, local harnesses, runbooks, and reports. Use when researching, testing, or proving Kafka architecture changes such as disaster recovery, snapshot restore, KRaft metadata recovery, cluster linking migration, transactional cutover, consumer offset recovery, backup-tooling claims, reduced-broker recovery, or any Kafka design where documentation alone is insufficient and a local proof is needed.
---

# Kafka Architecture Investigation

## Purpose

Turn a Kafka architecture question into a source-backed, deterministic, locally testable investigation with a small tracker, reference architecture, ADR, scenario matrix, implementation spec, harness evidence, runbook, and report.

This skill is not a general "make me a Kafka lab" workflow. If the available skills include `kafka-local-lab`, use it as a companion for simple local lab materialization. If it is unavailable, continue with project-local lab design unless installing the companion skill would materially save time.

## Operating Rules

- Keep chat updates short: state the current phase and link to the working document.
- Keep the tracker small. Put detailed reasoning in the fixed investigation files.
- Use the opinionated file layout below. Do not invent alternate names or scatter investigation state across the repo unless the user explicitly requests it.
- After reading this `SKILL.md`, bootstrap or read `TRACKER.md` before reading any project investigation file or skill reference.
- Resume from the earliest non-`done` row in the tracker checklist. Read only the files and references named by that row.
- When updating `TRACKER.md`, keep the Current Cursor aligned with the active checklist row. Copy the full `Read Now` and `Write/Update` file lists from the destination checklist row; do not shorten them to only the files you used this turn.
- Start with an interactive synchronization loop. Ask at least one question when the research-ready gate is blocked, and ask no more than five focused questions in one turn.
- During `S01-user-sync`, record any facts already supplied by the user in `INVESTIGATION_BRIEF.md` and `REFERENCE_ARCHITECTURE.md` before asking the next question batch. Ask only for the missing facts needed by the research-ready gate.
- After intake and source research are sufficient, drive the work yourself: ADR, scenario/spec, harness, execution, and report. Stop only for missing user facts, destructive actions, unclear policy tradeoffs, or external blockers.
- After the ADR completion gate is met, run an autonomous implementation loop: pick the next pending step in `IMPLEMENTATION_SPEC.md`, execute it, validate it, update evidence and status, then continue until all steps are done or a stop condition is reached.
- Treat docs as useful but incomplete. Use official docs for intended behavior, source code for implementation behavior, local tests for version-specific behavior, and harness artifacts as final evidence.
- Do not treat "Kafka started" as proof. Validate control plane, data plane, transaction visibility, consumer offsets, and client behavior as relevant.
- Prefer deterministic state construction over timing-based process kills. If a crash timing test is unavoidable, mark it as nondeterministic and do not use it as the only proof.
- Never mutate original snapshots, production exports, or source evidence. Work on disposable copies.

## Fixed Project Files

Use these exact investigation paths:

```text
docs/kafka-architecture-investigation/
  TRACKER.md
  INVESTIGATION_BRIEF.md
  REFERENCE_ARCHITECTURE.md
  SOURCE_RESEARCH.md
  ADR.md
  SCENARIO_MATRIX.tsv
  IMPLEMENTATION_SPEC.md
  HARNESS_SPEC.md
  REPORT.md
  RUNBOOK.md
scripts/kafka-architecture-investigation/
  reset.sh
  seed.sh
  capture.sh
  mutate.sh
  start.sh
  assert.sh
  report.sh
artifacts/kafka-architecture-investigation/
  runs/
  snapshots/
```

Create `TRACKER.md` first by copying the bundled template. Create the other files lazily from `assets/templates/` when the active tracker step needs them. Keep all durable investigation state in `docs/kafka-architecture-investigation/`, harness entrypoint scripts in `scripts/kafka-architecture-investigation/`, and raw harness output under `artifacts/kafka-architecture-investigation/`.

## Context Management

Use `TRACKER.md` as the only always-read investigation file.

Tracker transitions are low-freedom. When changing checklist statuses or moving the Current Cursor to another step, use the bundled updater instead of hand-editing the cursor:

```bash
python3 <skill-dir>/scripts/update-tracker-state.py . \
  --step-status S01-user-sync=done \
  --step-status S02-source-research=pending \
  --cursor S02-source-research \
  --cursor-status pending
```

1. After this skill loads, check for `docs/kafka-architecture-investigation/TRACKER.md`.
2. If it is missing, run the bundled bootstrap script from the project root. For S01 use:
   ```bash
   bash <skill-dir>/scripts/bootstrap-investigation.sh . INVESTIGATION_BRIEF.md REFERENCE_ARCHITECTURE.md
   ```
   Resolve `<skill-dir>` to this skill's installed directory, for example `/home/agent/.codex/skills/kafka-architecture-investigation`.
   Do not hand-write, summarize, or reconstruct `TRACKER.md`; the canonical tracker template is required for resume/context management.
3. Read `TRACKER.md`.
4. Find the earliest checklist row whose status is not `done`.
5. If a listed investigation file is missing, create it from the matching template before reading it.
6. Read only the files and skill references listed in that row's `Read Now` column.
7. Do the work for that step, update the durable files named in `Write/Update`, then update `TRACKER.md` before moving on. Use `update-tracker-state.py` for status/cursor changes.
8. When updating `TRACKER.md`, ensure `Current Cursor` still mirrors the earliest non-`done` checklist row, including the complete `Read now` and `Write/update` lists. If advancing to a new row, copy every file/reference from that row, including files that do not exist yet or will only be created in the next turn.

Do not read all references, templates, or investigation documents "to get context". The tracker is the context index.

## Workflow

The workflow checklist in `TRACKER.md` is authoritative. Keep this summary aligned with those rows:

- `S00-bootstrap`: create the fixed investigation directory and tracker if missing.
- `S01-user-sync`: ask focused user questions until the research-ready gate is satisfied.
- `S02-source-research`: research docs and source code for the selected Kafka tracks.
- `S03-adr`: build the ADR that justifies the testable approach.
- `S04-scenarios-spec`: expand ADR claims into deterministic scenarios and small implementation steps.
- `S05-harness`: build or extend the local harness and artifact contract.
- `S06-execute`: run the autonomous implementation loop and iterate on evidence.
- `S07-report-runbook`: produce the final report and runbook.

## Reference Purpose Summary

Read these files only when the active tracker row lists them in `Read Now`.

- `references/intake.md`: initial questions, synchronization loop, and research-ready gate.
- `references/kafka-internals-checklist.md`: source/docs research and subsystem-specific failure analysis.
- `references/scenario-design.md`: ADR/source claims into deterministic scenarios.
- `references/harness-contract.md`: scripts, artifact directories, assertions, and rerunnable commands.
- `references/reporting.md`: ADR, runbook, final report, and user-facing summary.
