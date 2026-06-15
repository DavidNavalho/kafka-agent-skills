# Scenario Design

Use this reference to turn the ADR and source-backed failure models into deterministic test scenarios.

## Scenario Rule

Every scenario must connect:

```text
objective -> ADR claim -> failure model -> deterministic construction -> assertion -> evidence
```

If the deterministic construction is missing, keep the scenario as a research item or mark it nondeterministic.

## Matrix Columns

Use the exact columns in `assets/templates/SCENARIO_MATRIX.tsv`:

```text
scenario_id track objective_ids adr_claim_ids purpose setup fault_or_mutation expected_result assertions artifacts implementation_step_ids status notes
```

Statuses: `planned`, `implemented`, `passed`, `failed`, `blocked`, `nondeterministic`, `superseded`.

## Scenario Families

Choose only families relevant to the investigation:

- Baseline: healthy startup, produce/consume, internal topics, admin commands, and teardown.
- Clean snapshot/restore: controlled stop or consistent capture, restore, and validation.
- Abrupt snapshot/restore: copied state without clean stop, recovery checkpoints, and log loading.
- Metadata/data mismatch: metadata from one point, partition data from another.
- Reduced-broker recovery: imported data whose original replicas or broker IDs no longer match target topology.
- Missing or extra partition data: unknown partitions, missing replicas, or partial topic copies.
- Producer state: idempotent producers, sequence recovery, duplicate prevention, and producer epoch behavior.
- Transactions: in-flight, committed, aborted, or marker/control-state edge cases with `read_committed` consumers.
- Consumer offsets: offset rewind, missing offsets, copied offsets, or offset sync mismatch.
- Cluster linking/cutover: mirror promotion, bidirectional links, ownership changes, writes during failover, and rollback.
- Backup-tool comparison: vendor/tool output mounted into the same assertions used for native snapshots.

## ADR Coverage Gate

Before implementation starts:

- Every stated objective has at least one scenario or an explicit out-of-scope reason.
- Every high-confidence ADR claim that affects correctness has a scenario or an explicit source-only rationale.
- Every scenario has a deterministic construction or is marked `nondeterministic`.
- Every scenario maps to one or more implementation steps in `IMPLEMENTATION_SPEC.md`.

## Determinism Guidance

Prefer:

- Seed a known fixture.
- Capture or copy it once as immutable input.
- Make a disposable scenario working copy.
- Mutate files, metadata, topic state, or client state into the exact failure mode.
- Start the target and assert exact outcomes.

Avoid relying only on:

- killing a broker at just the right moment
- sleeping for a guessed interval
- log lines with no data-plane assertion
- consumer lag as a proxy for transaction visibility
- "broker is running" as a recovery proof

If process timing is part of the real architecture question, run it as a separate stress/nondeterminism scenario and record variance across attempts.

## Assertions

Pick assertions that match the target claim:

- Control plane: brokers register, controller stable, topic metadata correct, internal topics present.
- Data plane: expected keys/offsets visible, no unexpected gaps, duplicates classified, compaction considered.
- Transactions: `read_committed` and `read_uncommitted` behavior checked when relevant, LSO implications captured.
- Consumer groups: committed offsets match target policy, replay/skip behavior classified.
- Linking/migration: topic ownership, mirror state, promotion state, and post-cutover write behavior verified.
- Client ramp: producers/consumers can reconnect using intended bootstrap/listeners and credentials.
- Runbook: procedure can be repeated from clean state without hand-editing hidden assumptions.

## Pass/Fail Language

Use explicit classifications:

- `pass`: observed behavior matches expected behavior and evidence is attached.
- `expected-degraded`: behavior is degraded but within the agreed acceptability boundary.
- `fail`: behavior violates the boundary or contradicts the claim.
- `blocked`: scenario cannot run because an input, license, tool, or environment is missing.
- `inconclusive`: evidence is insufficient or nondeterministic.

Do not soften a failing scenario into a success because the system can be manually repaired. Record manual repair as a separate runbook step or fallback.
