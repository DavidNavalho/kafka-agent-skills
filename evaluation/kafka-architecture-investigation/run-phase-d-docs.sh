#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run-phase-d-docs.sh [options]

Run Phase D document-only evaluations for kafka-architecture-investigation.

Options:
  --sbx NAME           sbx sandbox name. Defaults to agent-skills-eval.
  --model NAME         Codex model. Defaults to gpt-5.4-mini.
  --effort NAME        Reasoning effort. Defaults to low.
  --results-dir DIR    Host results directory.
  --sync-host-codex-auth
                      Copy host ChatGPT Codex auth into sbx before running.
  -h, --help           Show this help.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SBX_NAME="${SBX_NAME:-agent-skills-eval}"
MODEL="${MODEL:-gpt-5.4-mini}"
EFFORT="${EFFORT:-low}"
SANDBOX_WORKSPACE="${SANDBOX_WORKSPACE:-/home/agent/workspace}"
SKILL_SOURCE="${SKILL_SOURCE:-$REPO_ROOT/skills/kafka-architecture-investigation}"
SKILL_DEST="${SKILL_DEST:-/home/agent/.codex/skills/kafka-architecture-investigation}"
SYNC_HOST_CODEX_AUTH="${SYNC_HOST_CODEX_AUTH:-0}"
RUN_SET="${RUN_SET:-phase-d-docs-$(date +%Y%m%d-%H%M%S)}"
RESULTS_DIR="${RESULTS_DIR:-$SCRIPT_DIR/evaluation-runs/$RUN_SET}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sbx)
      SBX_NAME="${2:?Missing value for --sbx}"
      shift 2
      ;;
    --model)
      MODEL="${2:?Missing value for --model}"
      shift 2
      ;;
    --effort)
      EFFORT="${2:?Missing value for --effort}"
      shift 2
      ;;
    --results-dir)
      RESULTS_DIR="${2:?Missing value for --results-dir}"
      shift 2
      ;;
    --sync-host-codex-auth)
      SYNC_HOST_CODEX_AUTH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log() {
  printf '[kafka-arch-eval] %s\n' "$*"
}

bool() {
  if "$@"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

sync_host_codex_auth() {
  local script="$REPO_ROOT/evaluation/sbx-sandbox-pattern/copy-codex-auth-to-sbx.sh"

  test -f "$script" || {
    echo "Codex auth sync helper is missing: $script" >&2
    exit 1
  }

  log "Syncing host ChatGPT Codex auth into sbx"
  bash "$script" --sbx "$SBX_NAME"
}

refresh_skill() {
  log "Installing only the skill under test inside sbx: $SKILL_DEST"
  sbx exec "$SBX_NAME" -- env SKILL_SOURCE="$SKILL_SOURCE" SKILL_DEST="$SKILL_DEST" sh -lc '
    test -f "$SKILL_SOURCE/SKILL.md" || {
      echo "Skill source not visible inside sbx: $SKILL_SOURCE" >&2
      exit 1
    }
    rm -rf "$HOME/.codex/skills"
    mkdir -p "$(dirname "$SKILL_DEST")"
    cp -R "$SKILL_SOURCE" "$SKILL_DEST"
  ' >/dev/null
}

check_ready() {
  local status

  log "Checking Codex runner inside sbx"
  status="$(sbx exec "$SBX_NAME" -- sh -lc '
    command -v codex >/dev/null 2>&1 || {
      echo "codex is not installed in sbx" >&2
      exit 1
    }
    codex login status || {
      echo "codex is not authenticated in sbx" >&2
      exit 1
    }
  ' 2>&1)" || {
    printf '%s\n' "$status" >&2
    exit 1
  }

  case "$status" in
    *"Logged in using ChatGPT"*) ;;
    *)
      printf '%s\n' "$status" >&2
      echo "Codex in sbx is not authenticated with ChatGPT." >&2
      exit 1
      ;;
  esac
}

extract_tokens_used() {
  local trace="$1"

  awk '
    /tokens used/ {
      if (getline line) {
        gsub(",", "", line)
        if (line ~ /^[0-9]+$/) {
          print line
          found = 1
        }
      }
      exit
    }
    END {
      if (!found) {
        print "unknown"
      }
    }
  ' "$trace"
}

prepare_workspace() {
  local case_name="$1"
  local target_dir="$2"

  log "Preparing Phase D workspace case=$case_name target=$target_dir"
  sbx exec "$SBX_NAME" -- env CASE_NAME="$case_name" TARGET_DIR="$target_dir" SKILL_DEST="$SKILL_DEST" sh -lc '
    set -eu
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"

    docs="INVESTIGATION_BRIEF.md REFERENCE_ARCHITECTURE.md SOURCE_RESEARCH.md"
    if [ "$CASE_NAME" = "s03-adr" ]; then
      docs="$docs ADR.md"
    elif [ "$CASE_NAME" = "s04-scenario-spec" ]; then
      docs="$docs ADR.md SCENARIO_MATRIX.tsv IMPLEMENTATION_SPEC.md"
    fi
    bash "$SKILL_DEST/scripts/bootstrap-investigation.sh" "$TARGET_DIR" $docs

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/INVESTIGATION_BRIEF.md" <<'"'"'BRIEF'"'"'
# Kafka Architecture Investigation Brief

## Objective

Determine whether copied filesystem-level Kafka broker data snapshots from an Apache Kafka 3.7 KRaft source cluster can be restored into a smaller local recovery cluster, and identify the failure modes that must be tested before relying on the process.

## Source Architecture

- Kafka distribution/version: Apache Kafka 3.7.x
- Mode: KRaft
- Broker/controller count: 6 brokers, controllers co-located with brokers
- Storage/snapshot model: filesystem-level broker data directory snapshots captured at a common maintenance point
- Topics/data classes: critical `orders`, `payments`, and compacted `customer-profile`; representative partition counts and replication factors can be reduced in the lab
- Producers/consumers: idempotent `orders` producers, transactional `payments` producers, `payment-ledger` consumers using `read_committed`, and named consumer groups whose offsets matter
- Likely Kafka tracks: KRaft metadata identity, broker/log directory identity, partition logs/checkpoints, consumer offsets, transaction state, producer state, and reduced-broker placement

## Target State

- Intended topology: 3-broker Apache Kafka 3.7.x local recovery cluster
- Recovery mechanism: restore from copied filesystem snapshots into a reduced-broker disposable environment
- Ownership/write model: recovery cluster is validation-only/read-only until feasibility is proven

## Acceptability Boundaries

- No committed business records may be silently lost for critical topics
- Bounded duplicates or replay are acceptable if documented and recoverable
- Per-partition ordering must be preserved for restored committed records
- Aborted records must remain invisible to `read_committed` consumers
- Consumer offset continuity is required for named groups or must be explicitly classified as not preserved
- Manual repair is acceptable only on disposable snapshot copies and must be documented

## Constraints And Safety

- Available locally: sbx, Docker in later phases, copied fixture data, public Kafka docs/source in real research phases
- Off limits: production systems, credentials, destructive writes to original artifacts, licensed components not already available
- Phase D constraint: use only supplied offline fixture notes; do not browse, clone, or run Kafka

## Evidence Required

- Required artifacts: source research, ADR, scenario matrix, implementation spec, runnable local harness later, report, and runbook
- Repeatability target: another engineer can rerun later harness steps from fixed commands and inspect artifacts
BRIEF

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/REFERENCE_ARCHITECTURE.md" <<'"'"'ARCH'"'"'
# Reference Architecture

## Current State

Apache Kafka 3.7.x source cluster in KRaft mode with 6 brokers and co-located controllers. Filesystem-level broker data directory snapshots are copied from the source estate. Critical topics include ordinary, compacted, and transactional workloads; named consumer offsets and `read_committed` visibility are in scope.

## Target State

Restore copied snapshot data into a 3-broker Apache Kafka 3.7.x local recovery cluster for validation. The recovery target is read-only until feasibility and failure modes are proven.

## Ownership And Invariants

- Write ownership: source remains authoritative
- Metadata ownership: KRaft
- Offset ownership: named consumer groups must preserve or explicitly document offset discontinuity
- Transaction state ownership: restored transaction metadata and markers must keep aborted records invisible to `read_committed`
- Data integrity invariants: no silent committed-record loss for critical topics; per-partition ordering preserved for restored records; bounded replay is acceptable if documented

## Failure Boundary

- In scope: metadata identity mismatch, reduced-broker partition placement, partition logs/checkpoints, offsets, transactions, compaction, and local recovery behavior
- Out of scope: mutation of original snapshots, production access, client cutover automation, and licensed components

## Local Test Surrogate

The local surrogate may reduce topic scale but must preserve KRaft mode, broker-count reduction, filesystem-snapshot restore semantics, offsets, transaction visibility, and reduced-broker placement behavior.
ARCH

    if [ "$CASE_NAME" = "s03-adr" ] || [ "$CASE_NAME" = "s04-scenario-spec" ]; then
      cat > "$TARGET_DIR/docs/kafka-architecture-investigation/SOURCE_RESEARCH.md" <<'"'"'RESEARCH'"'"'
# Source Research

## Scope

- Kafka distribution/version: Apache Kafka 3.7.x
- Source tag or commit: offline fixture representing `apache-kafka-3.7.x`
- Product docs: offline fixture notes supplied by Phase D runner
- Subsystems: KRaft metadata identity, log loading, consumer offsets, transactions, reduced-broker placement

## Claims

### Claim C1

- Subsystem: KRaft metadata and broker identity
- Source/doc path: `core/src/main/scala/kafka/server/KafkaRaftServer.scala`; `metadata/src/main/java/org/apache/kafka/controller/ClusterControlManager.java`
- Evidence: broker startup depends on matching cluster/node identity and metadata registrations before accepting restored broker data.
- Implication for scenario design: include a metadata/identity mismatch scenario before trusting a raw copied data directory.
- Confidence: source-backed

### Claim C2

- Subsystem: Partition logs and checkpoints
- Source/doc path: `core/src/main/scala/kafka/log/LogManager.scala`; `storage/src/main/java/org/apache/kafka/storage/internals/log/UnifiedLog.java`
- Evidence: log loading uses local checkpoints, leader epochs, producer snapshots, and segment/index files; copied data can be loaded only when metadata and local files agree enough for startup.
- Implication for scenario design: include clean snapshot and metadata/data mismatch scenarios with explicit data-plane assertions.
- Confidence: source-backed

### Claim C3

- Subsystem: Consumer offsets
- Source/doc path: `group-coordinator/src/main/java/org/apache/kafka/coordinator/group/GroupMetadataManager.java`; `__consumer_offsets`
- Evidence: committed offsets are Kafka records in internal topics and must align with restored topic data to avoid replay or skip behavior.
- Implication for scenario design: include offset continuity and replay classification scenarios.
- Confidence: source-backed

### Claim C4

- Subsystem: Transactions and producer state
- Source/doc path: `transaction-coordinator/src/main/java/org/apache/kafka/coordinator/transaction/TransactionStateManager.java`; `storage/src/main/java/org/apache/kafka/storage/internals/log/ProducerStateManager.java`
- Evidence: transaction metadata, control batches, producer epochs, and last stable offset affect what `read_committed` consumers can see after restore.
- Implication for scenario design: include committed and aborted transaction visibility scenarios.
- Confidence: source-backed

### Claim C5

- Subsystem: Reduced-broker recovery
- Source/doc path: `metadata/src/main/java/org/apache/kafka/controller/ReplicationControlManager.java`
- Evidence: a 6-broker source topology cannot be assumed to map directly onto a 3-broker target without deterministic metadata or replica placement handling.
- Implication for scenario design: include reduced-broker placement and missing-replica scenarios before declaring feasibility.
- Confidence: source-backed

## Open Questions

- None for document-only Phase D; real source paths must be verified in a later Kafka/source phase.

## Search Notes

- Phase D used offline fixture paths only; no network, clone, or Kafka runtime was used.
RESEARCH
    fi

    if [ "$CASE_NAME" = "s04-scenario-spec" ]; then
      cat > "$TARGET_DIR/docs/kafka-architecture-investigation/ADR.md" <<'"'"'ADR'"'"'
# ADR: Validate reduced-broker Kafka snapshot restore with deterministic local scenarios

## Status

Proposed

## Context

The source architecture is Apache Kafka 3.7.x in KRaft mode with 6 brokers. The target state is a 3-broker local recovery cluster restored from copied filesystem-level broker data snapshots. The investigation must determine whether this restore shape is feasible and which failure modes make it unsafe.

## Decision Drivers

- Preserve committed critical-topic records without silent loss.
- Classify replay, duplicate, and offset discontinuity behavior.
- Preserve `read_committed` transaction visibility for relevant workloads.
- Never mutate original snapshots or production evidence.
- Prefer deterministic state construction over timing-dependent broker crashes.

## Options

- Raw mount only: rejected because it does not prove metadata identity, offsets, transactions, or reduced-broker placement.
- Documentation-only decision: rejected because Kafka startup and log recovery have version-specific implementation behavior.
- Deterministic local scenario suite: selected because it can force the important failure modes on disposable copies and produce rerunnable evidence.

## Decision

Use a deterministic local scenario suite built from copied snapshot fixtures. Start with baseline restore, then force metadata/data mismatch, reduced-broker placement, consumer offset continuity, and transaction visibility scenarios before any feasibility claim.

## Evidence

- Source research: C1 KRaft identity, C2 log/checkpoint loading, C3 consumer offsets, C4 transactions, C5 reduced-broker placement.
- Scenario results: not yet executed.
- Harness run: not yet built.

## Scenario Coverage Plan

| Objective | ADR Claim | Scenario Family | Required Evidence |
| --- | --- | --- | --- |
| O1 baseline restore feasibility | C1, C2 | Baseline clean restore | broker startup plus topic read assertions |
| O2 reduced-broker restore safety | C1, C5 | Reduced-broker recovery | metadata/replica placement assertion |
| O3 offset continuity | C3 | Consumer offsets | committed offset and replay classification |
| O4 transaction visibility | C4 | Transactions | `read_committed` and `read_uncommitted` visibility assertion |
| O5 mismatch handling | C1, C2 | Metadata/data mismatch | deterministic failure or repair classification |

## Consequences

- Feasibility cannot be claimed from broker startup alone.
- Manual repair may be acceptable only on disposable copies and must be recorded in the runbook.
- Real Kafka/source verification remains required after document-only Phase D.
ADR
    fi

    case "$CASE_NAME" in
      s02-source-research)
        python3 "$SKILL_DEST/scripts/update-tracker-state.py" "$TARGET_DIR" \
          --step-status S01-user-sync=done \
          --step-status S02-source-research=pending \
          --cursor S02-source-research \
          --cursor-status pending
        ;;
      s03-adr)
        python3 "$SKILL_DEST/scripts/update-tracker-state.py" "$TARGET_DIR" \
          --step-status S01-user-sync=done \
          --step-status S02-source-research=done \
          --step-status S03-adr=pending \
          --cursor S03-adr \
          --cursor-status pending
        ;;
      s04-scenario-spec)
        python3 "$SKILL_DEST/scripts/update-tracker-state.py" "$TARGET_DIR" \
          --step-status S01-user-sync=done \
          --step-status S02-source-research=done \
          --step-status S03-adr=done \
          --step-status S04-scenarios-spec=pending \
          --cursor S04-scenarios-spec \
          --cursor-status pending
        ;;
      *)
        echo "Unknown case: $CASE_NAME" >&2
        exit 2
        ;;
    esac
  ' >/dev/null
}

make_prompt() {
  local case_name="$1"
  local target_dir="$2"

  case "$case_name" in
    s02-source-research)
      cat <<PROMPT
Use \$kafka-architecture-investigation to resume the existing Kafka investigation in $target_dir.

The tracker is at S02-source-research. Do not browse, clone, curl, or use the network. Use only these offline source notes as the research fixture, preserve the supplied claim IDs exactly as C1-C5 in SOURCE_RESEARCH.md headings, and use only the allowed confidence labels from the source-research template. For these offline notes, use Confidence: docs-only and record the limitation in Search Notes. Mark S02 done if the source-research gate is satisfied, move the cursor to S03, and stop before writing ADR.md.

Offline source notes:
- C1 KRaft metadata/broker identity: broker startup depends on matching cluster/node identity and metadata registrations before accepting restored broker data. Fixture paths: core/src/main/scala/kafka/server/KafkaRaftServer.scala and metadata/src/main/java/org/apache/kafka/controller/ClusterControlManager.java.
- C2 Partition logs/checkpoints: log loading uses local checkpoints, leader epochs, producer snapshots, and segment/index files. Fixture paths: core/src/main/scala/kafka/log/LogManager.scala and storage/src/main/java/org/apache/kafka/storage/internals/log/UnifiedLog.java.
- C3 Consumer offsets: committed offsets are records in internal topics and must align with restored topic data to classify replay or skips. Fixture path: group-coordinator/src/main/java/org/apache/kafka/coordinator/group/GroupMetadataManager.java.
- C4 Transactions: transaction metadata, control batches, producer epochs, and last stable offset affect read_committed visibility. Fixture paths: transaction-coordinator/src/main/java/org/apache/kafka/coordinator/transaction/TransactionStateManager.java and storage/src/main/java/org/apache/kafka/storage/internals/log/ProducerStateManager.java.
- C5 Reduced-broker recovery: a 6-broker source topology cannot be assumed to map directly onto a 3-broker target without deterministic metadata or replica placement handling. Fixture path: metadata/src/main/java/org/apache/kafka/controller/ReplicationControlManager.java.
PROMPT
      ;;
    s03-adr)
      cat <<PROMPT
Use \$kafka-architecture-investigation to resume the existing Kafka investigation in $target_dir.

The tracker is at S03-adr and SOURCE_RESEARCH.md already contains offline source-backed claims. Build ADR.md only. Do not create SCENARIO_MATRIX.tsv, IMPLEMENTATION_SPEC.md, HARNESS_SPEC.md, scripts, or any Kafka/Docker assets. If the ADR completion gate is satisfied, mark S03 done, move the cursor to S04, and stop before detailed scenario expansion.
PROMPT
      ;;
    s04-scenario-spec)
      cat <<PROMPT
Use \$kafka-architecture-investigation to resume the existing Kafka investigation in $target_dir.

The tracker is at S04-scenarios-spec and ADR.md is complete. Expand the ADR into SCENARIO_MATRIX.tsv and IMPLEMENTATION_SPEC.md only. Use the exact 13-column tab-separated scenario matrix header and fill the artifacts column for every scenario row so implementation_step_ids/status/notes do not shift. The status column must be exactly one allowed status value, normally planned; do not write values like S01 planned. Do not create HARNESS_SPEC.md, Docker Compose, scripts, or run Kafka. If the scenario/spec gate is satisfied, mark S04 done, move the cursor to S05, and stop before harness work.
PROMPT
      ;;
    *)
      echo "Unknown Phase D case: $case_name" >&2
      exit 2
      ;;
  esac
}

score_run() {
  local case_name="$1"
  local host_run_dir="$2"
  local trace="$host_run_dir/trace.log"
  local target_dump="$host_run_dir/target-files.txt"
  local tracker="$host_run_dir/TRACKER.md"
  local source="$host_run_dir/SOURCE_RESEARCH.md"
  local adr="$host_run_dir/ADR.md"
  local matrix="$host_run_dir/SCENARIO_MATRIX.tsv"
  local spec="$host_run_dir/IMPLEMENTATION_SPEC.md"

  local result tracker_exists no_external no_harness source_ok adr_ok matrix_ok spec_ok cursor_ok case_gate_ok

  tracker_exists="$(bool test -s "$tracker")"
  if grep -Eiq 'git clone|curl[[:space:]]|https?://|kafka\.apache\.org|docs\.confluent\.io|github\.com/apache/kafka' "$trace"; then
    no_external="no"
  else
    no_external="yes"
  fi
  if grep -Eiq '/bin/(ba)?sh -lc ".*docker( compose|-compose)|^exec.*docker' "$trace" ||
     grep -Eq 'HARNESS_SPEC.md|scripts/kafka-architecture-investigation/.+\.sh' "$target_dump"; then
    no_harness="no"
  else
    no_harness="yes"
  fi
  source_ok="$(bool sh -c '
    test -s "$1" &&
    grep -Eq "Claim C[1-5]" "$1" &&
    grep -Eiq "Subsystem:" "$1" &&
    grep -Eiq "Source/doc path:" "$1" &&
    grep -Eiq "Implication for scenario design:" "$1" &&
    grep -Eiq "Confidence: (source-backed|docs-only)" "$1" &&
    grep -Eiq "KRaft|transaction|consumer offsets|Reduced-broker" "$1"
  ' sh "$source")"
  adr_ok="$(bool sh -c '
    test -s "$1" &&
    grep -Eq "^## Context" "$1" &&
    grep -Eq "^## Decision Drivers" "$1" &&
    grep -Eq "^## Options" "$1" &&
    grep -Eq "^## Decision" "$1" &&
    grep -Eq "^## Evidence" "$1" &&
    grep -Eq "^## Scenario Coverage Plan" "$1" &&
    grep -Eq "^## Consequences" "$1" &&
    grep -Eiq "C1|C2|C3|C4|C5" "$1" &&
    ! grep -Eq "TBD|<decision>" "$1"
  ' sh "$adr")"
  matrix_ok="$(bool sh -c '
    test -s "$1" &&
    head -n 1 "$1" | grep -Eq "scenario_id[[:space:]]+track[[:space:]]+objective_ids[[:space:]]+adr_claim_ids" &&
    awk -F "\t" "NR > 1 && NF == 13 && \$1 ~ /^S[0-9]+/ && \$3 != \"\" && \$4 != \"\" && \$7 != \"TBD\" && \$10 != \"\" && \$11 != \"\" && \$12 ~ /^(planned|implemented|passed|failed|blocked|nondeterministic|superseded)$/ { count++ } END { exit(count >= 3 ? 0 : 1) }" "$1"
  ' sh "$matrix")"
  spec_ok="$(bool sh -c '
    test -s "$1" &&
    grep -Eq "^## Quality Gates" "$1" &&
    grep -Eq "^## Step Plan" "$1" &&
    grep -Eq "I[0-9]+.*S[0-9]+" "$1" &&
    grep -Eiq "Validation Gate" "$1" &&
    ! grep -Eq "TBD" "$1"
  ' sh "$spec")"

  case "$case_name" in
    s02-source-research)
      cursor_ok="$(bool sh -c '
        grep -Eiq "Active step: S03-adr" "$1" &&
        grep -Eiq "Read now:.*ADR\\.md" "$1" &&
        grep -Eq "S02-source-research[[:space:]]*\\|[[:space:]]*done" "$1"
      ' sh "$tracker")"
      case_gate_ok="$(bool sh -c '
        test "$1" = "yes" &&
        ! grep -Eq "ADR.md|SCENARIO_MATRIX.tsv|IMPLEMENTATION_SPEC.md|HARNESS_SPEC.md" "$2"
      ' sh "$source_ok" "$target_dump")"
      ;;
    s03-adr)
      cursor_ok="$(bool sh -c '
        grep -Eiq "Active step: S04-scenarios-spec" "$1" &&
        grep -Eiq "Read now:.*SCENARIO_MATRIX\\.tsv" "$1" &&
        grep -Eiq "Read now:.*IMPLEMENTATION_SPEC\\.md" "$1" &&
        grep -Eq "S03-adr[[:space:]]*\\|[[:space:]]*done" "$1"
      ' sh "$tracker")"
      case_gate_ok="$(bool sh -c '
        test "$1" = "yes" &&
        ! grep -Eq "SCENARIO_MATRIX.tsv|IMPLEMENTATION_SPEC.md|HARNESS_SPEC.md" "$2"
      ' sh "$adr_ok" "$target_dump")"
      ;;
    s04-scenario-spec)
      cursor_ok="$(bool sh -c '
        grep -Eiq "Active step: S05-harness" "$1" &&
        grep -Eiq "Read now:.*HARNESS_SPEC\\.md" "$1" &&
        grep -Eq "S04-scenarios-spec[[:space:]]*\\|[[:space:]]*done" "$1"
      ' sh "$tracker")"
      case_gate_ok="$(bool sh -c '
        test "$1" = "yes" &&
        test "$2" = "yes" &&
        ! grep -Eq "HARNESS_SPEC.md|scripts/kafka-architecture-investigation/.+\\.sh" "$3"
      ' sh "$matrix_ok" "$spec_ok" "$target_dump")"
      ;;
    *)
      echo "Unknown Phase D case: $case_name" >&2
      exit 2
      ;;
  esac

  result="fail"
  if [ "$tracker_exists" = "yes" ] &&
     [ "$no_external" = "yes" ] &&
     [ "$no_harness" = "yes" ] &&
     [ "$cursor_ok" = "yes" ] &&
     [ "$case_gate_ok" = "yes" ]; then
    result="pass"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$result" \
    "$tracker_exists" \
    "$no_external" \
    "$no_harness" \
    "$source_ok" \
    "$adr_ok" \
    "$matrix_ok" \
    "$spec_ok" \
    "$cursor_ok"
}

write_markdown_summary() {
  local summary_tsv="$1"
  local summary_md="$2"

  {
    echo '# kafka-architecture-investigation Phase D Docs Summary'
    echo
    echo "Run set: \`$RUN_SET\`"
    echo
    echo '| Case | Model | Effort | Exit | Result | Seconds | Tokens | Tracker | No External | No Harness | Source OK | ADR OK | Matrix OK | Spec OK | Cursor OK |'
    echo '|---|---|---:|---:|---|---:|---:|---|---|---|---|---|---|---|---|'
    awk -F '\t' 'NR > 1 {
      printf "| `%s` | `%s` | `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15
    }' "$summary_tsv"
  } > "$summary_md"
}

mkdir -p "$RESULTS_DIR"

summary_tsv="$RESULTS_DIR/summary.tsv"
summary_md="$RESULTS_DIR/summary.md"
any_fail=0

printf 'case\tmodel\teffort\texit_code\tresult\telapsed_seconds\ttokens_used\ttracker_exists\tno_external\tno_harness\tsource_ok\tadr_ok\tmatrix_ok\tspec_ok\tcursor_ok\tlog_dir\n' > "$summary_tsv"

if is_truthy "$SYNC_HOST_CODEX_AUTH"; then
  sync_host_codex_auth
fi

refresh_skill
check_ready

for case_name in s02-source-research s03-adr s04-scenario-spec; do
  run_id="${case_name}-${MODEL}-${EFFORT}"
  host_run_dir="$RESULTS_DIR/$run_id"
  sandbox_run_dir="$SANDBOX_WORKSPACE/evaluation-runs/$RUN_SET/$run_id"
  target_dir="$SANDBOX_WORKSPACE/kafka-architecture-investigation-$RUN_SET-$case_name"

  mkdir -p "$host_run_dir"
  prepare_workspace "$case_name" "$target_dir"

  prompt="$(make_prompt "$case_name" "$target_dir")"
  printf '%s\n' "$prompt" > "$host_run_dir/prompt.txt"

  sbx exec "$SBX_NAME" -- env SANDBOX_RUN_DIR="$sandbox_run_dir" RUN_PROMPT="$prompt" sh -lc '
    rm -rf "$SANDBOX_RUN_DIR"
    mkdir -p "$SANDBOX_RUN_DIR"
    printf "%s\n" "$RUN_PROMPT" > "$SANDBOX_RUN_DIR/prompt.txt"
  ' >/dev/null

  log "Running $case_name model=$MODEL effort=$EFFORT target=$target_dir"
  started_at="$(date +%s)"
  set +e
  sbx exec "$SBX_NAME" -- env MODEL="$MODEL" EFFORT="$EFFORT" TARGET_DIR="$target_dir" SANDBOX_RUN_DIR="$sandbox_run_dir" sh -lc '
    codex exec \
      --skip-git-repo-check \
      --cd "$TARGET_DIR" \
      --dangerously-bypass-approvals-and-sandbox \
      -m "$MODEL" \
      -c "model_reasoning_effort=\"$EFFORT\"" \
      -o "$SANDBOX_RUN_DIR/final.md" \
      < "$SANDBOX_RUN_DIR/prompt.txt"
  ' > "$host_run_dir/transcript.log" 2> "$host_run_dir/stderr.log"
  exit_code=$?
  set -e
  finished_at="$(date +%s)"
  elapsed_seconds=$((finished_at - started_at))

  sbx exec "$SBX_NAME" -- env SANDBOX_RUN_DIR="$sandbox_run_dir" sh -lc '
    test -f "$SANDBOX_RUN_DIR/final.md" && cat "$SANDBOX_RUN_DIR/final.md"
  ' > "$host_run_dir/final.md" 2>/dev/null || : > "$host_run_dir/final.md"

  cat "$host_run_dir/transcript.log" "$host_run_dir/stderr.log" > "$host_run_dir/trace.log"
  tokens_used="$(extract_tokens_used "$host_run_dir/trace.log")"

  sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" sh -lc '
    if [ -d "$TARGET_DIR" ]; then
      find "$TARGET_DIR" -maxdepth 5 -type f -print | sort
    fi
  ' > "$host_run_dir/target-files.txt" 2>/dev/null || : > "$host_run_dir/target-files.txt"

  for doc in TRACKER.md INVESTIGATION_BRIEF.md REFERENCE_ARCHITECTURE.md SOURCE_RESEARCH.md ADR.md SCENARIO_MATRIX.tsv IMPLEMENTATION_SPEC.md HARNESS_SPEC.md; do
    sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" DOC="$doc" sh -lc '
      path="$TARGET_DIR/docs/kafka-architecture-investigation/$DOC"
      test -f "$path" && cat "$path"
    ' > "$host_run_dir/$doc" 2>/dev/null || : > "$host_run_dir/$doc"
  done

  scores="$(score_run "$case_name" "$host_run_dir")"
  IFS=$'\t' read -r result tracker_exists no_external no_harness source_ok adr_ok matrix_ok spec_ok cursor_ok <<< "$scores"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$case_name" \
    "$MODEL" \
    "$EFFORT" \
    "$exit_code" \
    "$result" \
    "$elapsed_seconds" \
    "$tokens_used" \
    "$tracker_exists" \
    "$no_external" \
    "$no_harness" \
    "$source_ok" \
    "$adr_ok" \
    "$matrix_ok" \
    "$spec_ok" \
    "$cursor_ok" \
    "$host_run_dir" >> "$summary_tsv"

  log "Case $case_name result: $result exit=$exit_code seconds=$elapsed_seconds tokens=$tokens_used"
  if [ "$result" != "pass" ]; then
    any_fail=1
  fi
done

write_markdown_summary "$summary_tsv" "$summary_md"

log "Summary: $summary_md"

if [ "$any_fail" -ne 0 ]; then
  exit 1
fi
