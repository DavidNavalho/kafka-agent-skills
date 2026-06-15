# Reporting And Decision Artifacts

Use this reference when writing `ADR.md`, `REPORT.md`, `RUNBOOK.md`, and the final user summary.

## Report Layers

Write at least two layers:

1. Executive layer: source architecture, problem, target architecture, approach, result, and unfinished work.
2. Evidence layer: scenario rationale, expected results, observed results, evidence paths, limitations, and follow-up uncertainties.

Always write:

- ADR: decision, alternatives, drivers, consequences, source research, and scenario coverage.
- Runbook: exact operator procedure, validation gates, stop criteria, rollback/fallback, and manual repair steps.
- Research note: source paths, docs, claims, and confidence.

## Claim Classification

Classify important claims as:

- `proven`: supported by source-backed scenario evidence.
- `falsified`: contradicted by deterministic evidence.
- `plausible`: supported by docs/source but not yet exercised.
- `policy`: depends on acceptable loss, downtime, manual work, or business decision.
- `unknown`: not yet researched or tested.

## ADR Shape

Use this fixed shape in `ADR.md`:

```text
# ADR: <decision>

## Status
Proposed | Accepted | Rejected | Superseded

## Context
Source architecture, target state, and problem.

## Decision Drivers
Evidence needs, constraints, acceptable outcomes, and operational boundaries.

## Options
Options considered and why they did or did not work.

## Decision
The chosen approach.

## Evidence
Source paths, source claims, scenario families, scenario IDs, run IDs, and result summary.

## Scenario Coverage Plan
Objectives, claims, and scenario families that must be expanded into `SCENARIO_MATRIX.tsv`.

## Consequences
Known tradeoffs, manual steps, residual uncertainties, and follow-up work.
```

## ADR Completion Gate

Do not expand detailed scenarios until `ADR.md` contains:

- source architecture and target state
- decision drivers and acceptability boundaries
- researched options and selected approach
- source-backed claims or explicit open claims
- light scenario coverage plan
- known consequences and unresolved policy choices

If the ADR is incomplete, return to user synchronization or source research.

## Runbook Shape

Include:

- Preconditions and required access.
- Inputs and immutable artifacts.
- Step-by-step procedure.
- Validation gates with commands or scripts.
- Expected degraded states and acceptable manual repair.
- Stop criteria.
- Rollback or fallback.
- Evidence to collect during a real run.

## Final User Summary

Keep chat concise:

- what was built or analyzed
- where the main documents live
- what was proven/falsified
- what remains open
- what command or file the user should inspect next

Do not paste large reports into chat when a project document exists.
