# Kafka Architecture Investigation Tracker

## Context Rules

- After `SKILL.md`, read this tracker first and nothing else.
- Resume from the earliest checklist row whose status is not `done`.
- For the active row, read only the files and references listed in `Read Now`.
- The `Current Cursor` must mirror the active checklist row, including the complete `Read now` and `Write/update` file lists; do not remove references after reading them or omit files just because they are created in a later turn.
- If a `Read Now` investigation file is missing, create it from `assets/templates/` before reading it.
- Do not read all references, templates, or investigation docs for general context.
- Keep this tracker concise. Put detailed reasoning in the files named by `Write/Update`.
- Update this tracker after each user answer, research pass, scenario/spec change, harness run, or blocker.
- Status values: `pending`, `in_progress`, `done`, `blocked`.

## Current Cursor

This section mirrors the earliest non-`done` checklist row. If it conflicts with the checklist, the checklist wins and this section must be corrected.

When changing active steps, copy the destination checklist row's `Read Now` and `Write/Update` cells completely into this cursor. For example, S02's `Read now` includes `SOURCE_RESEARCH.md` even before source research content exists.

- Active step: S01-user-sync
- Status: in_progress
- Read now: `references/intake.md`, `INVESTIGATION_BRIEF.md`, `REFERENCE_ARCHITECTURE.md`
- Write/update: `INVESTIGATION_BRIEF.md`, `REFERENCE_ARCHITECTURE.md`, `TRACKER.md`
- Next action: Ask the next intake question batch and update the brief.
- Stop/ask user when: the research-ready gate is missing an essential user fact; ask 1-5 focused questions.

## Workflow Checklist

| Step | Status | Stage | Read Now | Write/Update | Completion Gate |
| --- | --- | --- | --- | --- | --- |
| S00-bootstrap | done | Create `docs/kafka-architecture-investigation/` and this tracker if missing. | `TRACKER.md` only | `TRACKER.md` | Tracker exists and cursor points at S01. |
| S01-user-sync | in_progress | Ask 1-5 focused user questions per turn until the investigation is research-ready. | `references/intake.md`; `INVESTIGATION_BRIEF.md`; `REFERENCE_ARCHITECTURE.md` | `INVESTIGATION_BRIEF.md`; `REFERENCE_ARCHITECTURE.md`; `TRACKER.md` | Source estate, target state, acceptability boundaries, constraints, evidence needs, and likely Kafka tracks are recorded or explicitly assumed. |
| S02-source-research | pending | Research docs and source code for the selected Kafka tracks. | `references/kafka-internals-checklist.md`; `INVESTIGATION_BRIEF.md`; `REFERENCE_ARCHITECTURE.md`; `SOURCE_RESEARCH.md` | `SOURCE_RESEARCH.md`; `TRACKER.md` | Claims have docs/source paths, version/tag/commit where relevant, confidence, and scenario implications. |
| S03-adr | pending | Build the ADR that justifies the testable approach. | `references/reporting.md`; `INVESTIGATION_BRIEF.md`; `REFERENCE_ARCHITECTURE.md`; `SOURCE_RESEARCH.md`; `ADR.md` | `ADR.md`; `TRACKER.md` | ADR completion gate is satisfied, including a light scenario coverage plan. |
| S04-scenarios-spec | pending | Expand ADR claims into deterministic scenarios and small implementation steps. | `references/scenario-design.md`; `ADR.md`; `SCENARIO_MATRIX.tsv`; `IMPLEMENTATION_SPEC.md` | `SCENARIO_MATRIX.tsv`; `IMPLEMENTATION_SPEC.md`; `TRACKER.md` | Objectives and ADR claims map to scenarios; each implemented scenario has a deterministic construction and step IDs. |
| S05-harness | pending | Build or extend the local harness and artifact contract. | `references/harness-contract.md`; `IMPLEMENTATION_SPEC.md`; `HARNESS_SPEC.md`; `SCENARIO_MATRIX.tsv` | `HARNESS_SPEC.md`; `scripts/kafka-architecture-investigation/`; `TRACKER.md` | Harness can run baseline and produce expected artifact layout. |
| S06-execute | pending | Run the autonomous implementation loop: next pending step, execute, validate, update evidence, continue. | `IMPLEMENTATION_SPEC.md`; `SCENARIO_MATRIX.tsv`; `HARNESS_SPEC.md`; specific active run summaries/log excerpts under `artifacts/kafka-architecture-investigation/` | `SOURCE_RESEARCH.md`; `ADR.md`; `SCENARIO_MATRIX.tsv`; `IMPLEMENTATION_SPEC.md`; `REPORT.md`; `TRACKER.md` | Scenario statuses and evidence paths are recorded; contradictions have been folded back into source research, ADR, or specs. |
| S07-report-runbook | pending | Produce final decision artifacts. | `references/reporting.md`; `REPORT.md`; `RUNBOOK.md`; `ADR.md`; `SCENARIO_MATRIX.tsv`; `IMPLEMENTATION_SPEC.md` | `REPORT.md`; `RUNBOOK.md`; `TRACKER.md` | Report and runbook state proven, falsified, policy-dependent, untested, and uncertain items. |

## Open Questions

- 

## Decisions

- 

## Key Assumptions

- 

## Active Evidence

- 

## Log

- YYYY-MM-DD: Initialized tracker.
