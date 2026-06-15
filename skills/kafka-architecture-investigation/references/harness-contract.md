# Harness Contract

Use this reference when implementing the local proof harness. Use the fixed paths below; do not switch to repo-local conventions unless the user explicitly overrides the skill convention.

## Shape

Implement the local equivalent of:

```text
reset -> seed -> capture -> mutate -> start -> assert -> report
```

Each step should be rerunnable from a clean checkout or clearly state required local prerequisites.

## Harness Paths

Create harness entrypoints here:

```text
scripts/kafka-architecture-investigation/
  reset.sh
  seed.sh
  capture.sh
  mutate.sh
  start.sh
  assert.sh
  report.sh
```

If a step needs subcommands, helpers, or language-specific code, place them under `scripts/kafka-architecture-investigation/lib/` and keep the seven entrypoints as the stable interface.

## Artifact Layout

Use this artifact layout:

```text
artifacts/kafka-architecture-investigation/
  runs/<run-id>/
    command-log.txt
    summary.tsv
    scenarios/<scenario-id>/
      inputs/
      working-copy/
      logs/
      assertions/
      report.md
  snapshots/
    <snapshot-id>/
```

Keep immutable snapshots or captures separate from disposable scenario working copies.

## Harness Step Contract

- `reset`: stop containers/processes, clear disposable state, preserve immutable inputs unless explicitly asked.
- `seed`: create topics, produce fixtures, create consumer offsets, produce transactions, configure links, and record fixture metadata.
- `capture`: snapshot/copy/export the state under test and record exact timing and method.
- `mutate`: apply deterministic scenario-specific changes only to a disposable copy.
- `start`: boot target topology and collect startup metadata/logs.
- `assert`: run admin, data, transaction, consumer group, and client assertions.
- `report`: write per-scenario evidence and update `summary.tsv`.

## Safety Rules

- Default to copy-on-write or disposable directories.
- Do not run destructive cleanup outside the lab root.
- Print target directories before deleting generated artifacts.
- Prefer project-local scripts over host-global Kafka CLI assumptions.
- In Docker labs, prefer Kafka CLI tools inside containers unless the project already standardizes host tools.
- Keep credentials, real hostnames, and customer data out of reusable templates and public reports unless the user explicitly wants them included.

## Summary TSV

Use stable, machine-readable columns:

```text
scenario_id	status	expected	observed	evidence_path	notes
```

Keep status values small: `pass`, `fail`, `expected-degraded`, `blocked`, `inconclusive`, `nondeterministic`.

## Evidence Requirements

For each scenario, capture enough to replay the reasoning:

- command transcript or script output
- container/process status
- relevant broker/controller logs
- topic metadata
- sample produced/consumed records or checksums
- transaction/consumer group observations when relevant
- exact mutation performed
- source/doc claims that justified the scenario

## Iteration Rule

When a harness result is surprising, update documents in this order:

1. `SOURCE_RESEARCH.md` if the implementation model was wrong.
2. `ADR.md` if the decision model or options changed.
3. `SCENARIO_MATRIX.tsv` if expected behavior or scenario construction changes.
4. `IMPLEMENTATION_SPEC.md` if the execution plan changes.
5. Harness scripts if the scenario remains valid but the implementation is flawed.
6. `REPORT.md` after evidence is stable.
