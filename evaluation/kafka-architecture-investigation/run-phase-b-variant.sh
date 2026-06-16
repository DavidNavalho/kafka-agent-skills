#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run-phase-b-variant.sh VARIANT [run-sbx-smoke options]

Run one Phase B prompt-variant smoke for kafka-architecture-investigation.

Variants:
  cluster-linking   Cluster Linking cutover/promotion investigation.
  transactions      Transactional producer/read_committed migration concern.
  backup-tool       Backup/recovery tooling claim validation.
  vague             Vague Kafka architecture investigation with minimal facts.

Any remaining options are passed to run-sbx-smoke.sh.
USAGE
}

prompt_cluster_linking() {
  cat <<'PROMPT'
Use $kafka-architecture-investigation to start investigating this Kafka architecture question in {{TARGET_DIR}}: can we safely cut over from an active Kafka source cluster to a recovery target using Kafka Cluster Linking?

Known context:
- The source and target Kafka clusters are connected with Kafka Cluster Linking.
- We need reason about mirror topic promotion and cutover safety.
- I do not yet know the Kafka/Confluent versions, link direction, topic list, offset strategy, planned versus abrupt cutover model, or acceptable downtime/data loss.

Do not research Kafka or Confluent docs/source yet. Do not create Docker Compose, scripts, scenarios, or a harness yet. Start the investigation properly with the tracker-first workflow and ask the next focused intake questions.
PROMPT
}

patterns_cluster_linking() {
  cat <<'PATTERNS'
cluster linking|Cluster Linking
mirror|promotion|promote
cutover
PATTERNS
}

prompt_transactions() {
  cat <<'PROMPT'
Use $kafka-architecture-investigation to start investigating this Kafka architecture question in {{TARGET_DIR}}: can we migrate or recover Kafka workloads that use transactions without exposing aborted records or breaking read_committed consumers?

Known context:
- Producers use Kafka transactions with transactional IDs.
- Some consumers use read_committed isolation.
- I do not yet know versions, topic layout, consumer groups, offset strategy, in-flight transaction policy, or acceptable duplicates/data loss.

Do not research Kafka docs/source yet. Do not create Docker Compose, scripts, scenarios, or a harness yet. Start the investigation properly with the tracker-first workflow and ask the next focused intake questions.
PROMPT
}

patterns_transactions() {
  cat <<'PATTERNS'
transaction|transactional
read_committed
migrate|migration|recover|recovery
PATTERNS
}

prompt_backup_tool() {
  cat <<'PROMPT'
Use $kafka-architecture-investigation to start investigating this Kafka architecture question in {{TARGET_DIR}}: can a Kafka backup/recovery tool's exported artifacts really support full cluster recovery?

Known context:
- A backup/recovery tool claims full Kafka recovery from its exported artifacts.
- We need validate whether the output captures enough state, including internal topics, consumer offsets, and transaction state.
- I do not yet know the tool version, export layout, Kafka version, skipped files/topics, restore procedure, or acceptable gaps.

Do not research the tool, Kafka docs, or Kafka source yet. Do not create Docker Compose, scripts, scenarios, or a harness yet. Start the investigation properly with the tracker-first workflow and ask the next focused intake questions.
PROMPT
}

patterns_backup_tool() {
  cat <<'PATTERNS'
backup|recovery tool|tool
internal topics|consumer offsets|transaction
full.*recover|full.*recovery|claim
PATTERNS
}

prompt_vague() {
  cat <<'PROMPT'
Use $kafka-architecture-investigation to start investigating this Kafka architecture question in {{TARGET_DIR}}: we need evaluate a Kafka architecture change, but I have not yet described the source estate, target state, risk boundaries, or evidence needs.

Known context:
- This is a Kafka architecture investigation.
- Source architecture, target state, acceptable outcomes, constraints, and evidence requirements are all currently unknown.

Do not research Kafka docs/source yet. Do not create Docker Compose, scripts, scenarios, or a harness yet. Start the investigation properly with the tracker-first workflow and ask the next focused intake questions.
PROMPT
}

patterns_vague() {
  cat <<'PATTERNS'
Kafka architecture|architecture investigation
unknown
PATTERNS
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

variant="${1:-}"
if [ -z "$variant" ] || [ "$variant" = "-h" ] || [ "$variant" = "--help" ]; then
  usage
  exit 0
fi
shift

case "$variant" in
  cluster-linking)
    PROMPT_TEXT="$(prompt_cluster_linking)"
    EXPECTED_FACT_PATTERNS="$(patterns_cluster_linking)"
    ;;
  transactions)
    PROMPT_TEXT="$(prompt_transactions)"
    EXPECTED_FACT_PATTERNS="$(patterns_transactions)"
    ;;
  backup-tool)
    PROMPT_TEXT="$(prompt_backup_tool)"
    EXPECTED_FACT_PATTERNS="$(patterns_backup_tool)"
    ;;
  vague)
    PROMPT_TEXT="$(prompt_vague)"
    EXPECTED_FACT_PATTERNS="$(patterns_vague)"
    ;;
  *)
    echo "Unknown Phase B variant: $variant" >&2
    usage >&2
    exit 2
    ;;
esac

export PROMPT_TEXT EXPECTED_FACT_PATTERNS
export RUN_SET="${RUN_SET:-phase-b-${variant}-$(date +%Y%m%d-%H%M%S)}"

exec "$SCRIPT_DIR/run-sbx-smoke.sh" "$@"
