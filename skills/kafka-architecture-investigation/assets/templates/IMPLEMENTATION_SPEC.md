# Implementation Specification

## Inputs

- ADR: `ADR.md`
- Scenario matrix: `SCENARIO_MATRIX.tsv`
- Harness spec: `HARNESS_SPEC.md`

## Quality Gates

- ADR completion gate satisfied:
- Objective-to-scenario coverage complete:
- Deterministic construction defined for each implemented scenario:
- Harness artifact contract defined:
- Safety boundaries reviewed:

## Step Plan

| Step ID | Scenario IDs | Action | Expected Output | Validation Gate | Status |
| --- | --- | --- | --- | --- | --- |
| I001 | S001 | Build baseline fixture | Healthy lab and seed data | Baseline assertions pass | planned |

## Autonomous Execution Rules

- Execute steps in order.
- Update status after each validation gate.
- Revise source research, ADR, scenario matrix, or harness spec when evidence changes the plan.
- Stop for user input only when a policy choice, missing environment fact, credential/license issue, or destructive action blocks progress.

## Open Implementation Questions

- 
