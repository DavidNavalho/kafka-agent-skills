# Harness Specification

## Root

- Script root: `scripts/kafka-architecture-investigation/`
- Artifact root: `artifacts/kafka-architecture-investigation/`
- Lab root:
- Immutable input root:

## Commands

- Reset: `scripts/kafka-architecture-investigation/reset.sh`
- Seed: `scripts/kafka-architecture-investigation/seed.sh`
- Capture: `scripts/kafka-architecture-investigation/capture.sh`
- Mutate: `scripts/kafka-architecture-investigation/mutate.sh`
- Start: `scripts/kafka-architecture-investigation/start.sh`
- Assert: `scripts/kafka-architecture-investigation/assert.sh`
- Report: `scripts/kafka-architecture-investigation/report.sh`

## Fixture

Describe topics, partitions, producers, consumers, transactions, offsets, and generated records.

## Scenario Execution

Describe how each scenario gets a disposable working copy and where it writes evidence.

## Validation Gates

- Control plane:
- Data plane:
- Transactions:
- Consumer offsets:
- Client ramp:

## Safety

- Destructive operations:
- Directories allowed for cleanup:
- Directories never mutated:
