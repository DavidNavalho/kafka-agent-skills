# Intake And Investigation Brief

Use this reference to build `INVESTIGATION_BRIEF.md` and a concise `REFERENCE_ARCHITECTURE.md`.

Ask in small batches. The initial phase is an active synchronization loop with the user: ask, update the brief and architecture, evaluate the research-ready gate, then ask again only for blockers or high-value missing facts.

Question count rule: ask at least one question when a required research-ready fact is missing, and ask no more than five focused questions in one turn. Prefer three or fewer for normal turns; use four or five only when the missing facts are tightly related.

## Minimum Brief

Capture:

- Source architecture: Kafka distribution, version, KRaft or ZooKeeper, broker count, regions/sites, storage model, security model, and network boundaries.
- Data shape: important topics, partition counts, replication factors, retention, compaction, schemas, transactional/idempotent producers, consumer groups, Kafka Streams/Connect, and cluster linking or MirrorMaker.
- Operational objective: migration, failover, disaster recovery, snapshot restore, reduced-broker recovery, backup-tooling validation, transactional cutover, or another target.
- Target architecture: intended cluster count, broker count, version, topology, data movement mechanism, client routing, ownership model, and steady-state behavior.
- Acceptability: acceptable data loss, duplication, reordering, reprocessing, downtime, degraded mode, manual steps, and integrity boundaries. Translate these into RPO/RTO only for DR, failover, and snapshot tracks.
- Constraints: read-only evidence, unavailable systems, no production access, time budget, local machine limits, network access, licensing, security, and destructive-action boundaries.
- Required evidence: decision to support, audience, confidence level, artifacts, runbook depth, and whether the result must be repeatable by someone else.

## Initial Question Batches

Start with Batch 1 unless the user already answered it. Ask the remaining batches only when their facts are still needed for the research-ready gate.

### Batch 1: Orientation

1. What Kafka estate are we modeling: distribution/version, KRaft or ZooKeeper, broker count, regions, and any linking/replication topology?
2. What architecture change, target state, or operational process are we trying to prove or disprove?
3. What outcomes are acceptable or unacceptable: data loss, duplicates, reprocessing, downtime, degraded mode, manual repair, or client changes?

### Batch 2: Data And Clients

1. Which topics, internal topics, consumer groups, producers, transactions, schemas, Connect/Streams apps, or mirrored topics matter for the decision?
2. Which client behavior must be preserved: write ownership, read path, `read_committed`, ordering, replay, offset continuity, credentials, or bootstrap/listener behavior?
3. What evidence do you need at the end: ADR, scenario matrix, runnable harness, report, runbook, demo, or comparison against a tool/vendor claim?

### Batch 3: Constraints And Safety

1. What can the agent access locally: existing repo, Docker, source snapshots, Kafka codebase, product docs, vendor tools, or real sanitized artifacts?
2. What is off limits: production access, destructive rewrites, specific credentials/data, internet access, licensed components, or long-running tests?
3. What local scale is acceptable: broker count, disk usage, runtime, Confluent versus Apache images, and whether a reduced lab is acceptable?

## Track-Specific Follow-Ups

Ask only the relevant questions:

- Snapshot or recovery: snapshot mechanism, consistency point, source availability, target broker count, data loss boundary, and whether identity rewrite is allowed.
- Cluster linking or cutover: planned versus abrupt cutover, link direction, mirror promotion rules, write ownership, offset strategy, rollback expectations.
- Transactions: transactional IDs, `read_committed` consumers, in-flight transaction policy, producer restart behavior, and whether duplicates or abort visibility are acceptable.
- Consumer offsets: offset source, offset sync or copy mechanism, replay tolerance, skipped-record tolerance, and group reset policy.
- Backup-tooling comparison: exact tool output, claimed scope, skipped files/topics, restore procedure, and whether the tool output can be mounted into the harness.

## Research-Ready Gate

Before research begins, `INVESTIGATION_BRIEF.md` and `REFERENCE_ARCHITECTURE.md` must contain:

- Current Kafka estate or explicit assumptions about it.
- Target state or process under investigation.
- Acceptability boundaries in plain language.
- Constraints and safety boundaries.
- Required evidence and final deliverables.
- Likely Kafka tracks and subsystems to research.

If a required item is missing and cannot be assumed safely, ask the user. If a nonessential item is missing, record it as an open assumption and proceed.

## Reference Architecture Content

Keep the architecture concise and fact-oriented:

- Current state: clusters, brokers, topics, clients, storage, replication/linking, and control plane.
- Target state: what changes and what must remain invariant.
- Data/control ownership: who owns writes, metadata, offsets, transaction state, and mirror/linked topics.
- Failure boundary: what can fail, what is assumed available, and what is out of scope.
- Test surrogate: how the local lab preserves the important architecture behavior even if it is smaller than production.

## Assumptions Ledger

Record assumptions as rows:

```text
ID | Assumption | Source | Impact If Wrong | How To Verify | Status
```

Statuses: `open`, `source-backed`, `tested`, `replaced`, `rejected`.

## Scope Guardrails

- Do not force DR terms such as RPO/RTO onto every Kafka investigation.
- Do ask about acceptable loss or degradation in plain language.
- Do not accept "same as production" as a lab design. Identify which behaviors must be preserved and which can be simplified.
- Do not bury missing estate details in chat. Put them in the assumptions ledger.
- Do not move into detailed scenario implementation until the ADR completion gate is satisfied.
