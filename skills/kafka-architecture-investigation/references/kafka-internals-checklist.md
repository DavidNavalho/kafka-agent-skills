# Kafka Internals Checklist

Use this reference when a claim depends on Kafka implementation behavior. Prefer primary docs and source for the exact Kafka or Confluent version under test. Record source tag/commit, file path, class/function, claim, and confidence in `SOURCE_RESEARCH.md`.

Do not treat this file as a complete map of Kafka internals. Use it to choose where to look and what questions to answer.

## Source Setup

- Identify distribution: Apache Kafka, Confluent Platform, managed Kafka, or vendor tool.
- Identify version and protocol/features that matter: KRaft/ZooKeeper, transactions, idempotence, tiered storage, cluster linking, consumer group protocol.
- Prefer source tags that match the deployed version. If unavailable, record the nearest inspected version.
- Search source with `rg` by class, filename, log message, config key, and file name.
- Record short source excerpts only when needed; otherwise record paths and paraphrased behavior.

Useful search targets:

```bash
rg "meta.properties|quorum-state|bootstrap.checkpoint|recovery-point-offset-checkpoint|replication-offset-checkpoint"
rg "ProducerStateManager|TransactionStateManager|TransactionCoordinator|LastStableOffset|control batch"
rg "GroupMetadataManager|OffsetFetch|__consumer_offsets"
rg "stray|offline log directory|LogLoader|UnifiedLog|leader-epoch-checkpoint"
```

## KRaft Metadata And Identity

Questions to answer:

- Which files bind broker identity, cluster identity, and log directory identity?
- Where is the metadata log stored for this deployment?
- What does startup validate before accepting broker data?
- How are controller quorum state, metadata snapshots, and broker registrations recovered?
- What happens when metadata and partition data come from different points in time?
- What validation or cleanup occurs for partitions unknown to the metadata log?

Inspect for:

- `meta.properties`
- metadata log directories and `__cluster_metadata`
- quorum state files
- metadata snapshots and checkpoints
- broker registration and log directory registration behavior
- startup validation, log loading, and stray partition handling

## Partition Logs And Checkpoints

Questions to answer:

- What local files define log start, recovery point, replication checkpoint, leader epochs, and producer state?
- Which files are authoritative versus rebuildable?
- What happens when a segment exists locally but metadata no longer assigns it?
- How does Kafka recover after unclean shutdown or copied data directories?
- Which files must be copied atomically for the scenario being tested?

Inspect for:

- topic-partition directories
- log segments, indexes, time indexes, transaction indexes
- leader epoch checkpoints
- recovery and replication checkpoint files
- cleaner checkpoints for compacted topics
- log loader behavior

## Transactions And Producer State

Questions to answer:

- Where does transactional coordinator state live?
- How are transactional markers, control batches, producer IDs, epochs, and sequence numbers restored?
- How does Last Stable Offset affect `read_committed` consumers after restore or cutover?
- What happens to in-flight, aborted, or partially replicated transactions?
- Does the proposed migration preserve enough state for idempotent and transactional producers?

Inspect for:

- `__transaction_state`
- producer state snapshots
- transaction indexes
- control batch handling
- transaction coordinator startup and recovery
- client producer ID/epoch behavior

## Consumer Offsets And Group State

Questions to answer:

- Are committed offsets copied, recreated, synchronized, or intentionally reset?
- Does the scenario preserve consumer group generation/member state, or only offsets?
- What are valid outcomes for duplicates, reprocessing, or skipped records?
- Are offset assertions aligned with `read_committed` visibility and topic data state?

Inspect for:

- `__consumer_offsets`
- group coordinator state loading
- offset commit/fetch behavior
- offset sync behavior for linking/mirroring tools

## Cluster Linking And Mirrored Topics

Confluent cluster linking behavior may not be fully available in Apache Kafka source. Use Confluent docs, CLI output, local experiments, and observable metadata.

Questions to answer:

- Which cluster owns writes before and after promotion?
- What metadata distinguishes source, mirror, promoted, and failed-over topics?
- How are offsets, topic configs, ACLs, schemas, and transactions handled or not handled?
- What does abrupt versus planned promotion change?
- What is the rollback story after writes occur on the target?

## Backup Tooling Or Snapshot Product Claims

Questions to answer:

- What exact files, directories, metadata, and checkpoints does the tool copy?
- Does it coordinate with Kafka or storage snapshots for consistency?
- Does it copy hidden/internal topics and metadata logs?
- Does it preserve cluster identity intentionally or rewrite it?
- What does it skip, filter, transform, or regenerate?
- Can its output be mounted into a local test harness and validated independently?

## Claim Recording

Use this shape in `SOURCE_RESEARCH.md`:

```text
Claim: C1
Subsystem:
Version/commit:
Source/doc path:
Evidence:
Implication for scenario design:
Confidence: docs-only | source-backed | locally-tested | harness-proven
```

Use stable claim IDs (`C1`, `C2`, etc.) and preserve supplied claim IDs exactly. These IDs are the bridge into ADR claims and scenario rows.

Use only the listed confidence values. Do not invent extra labels such as `offline-fixture`; if a document-only fixture provides source-path notes without live verification, use `docs-only` and record the limitation in Search Notes.
