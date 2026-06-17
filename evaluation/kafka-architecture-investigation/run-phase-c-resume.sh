#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run-phase-c-resume.sh [options]

Run Phase C resume evaluations for kafka-architecture-investigation.

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
RUN_SET="${RUN_SET:-phase-c-resume-$(date +%Y%m%d-%H%M%S)}"
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

question_count() {
  local final="$1"

  awk '
    /^[[:space:]]*[0-9]+[.)][[:space:]]+/ { numbered++ }
    { qmarks += gsub(/\?/, "?") }
    END {
      if (qmarks > 0) {
        print qmarks
      } else {
        print numbered + 0
      }
    }
  ' "$final"
}

prepare_partial_workspace() {
  local target_dir="$1"

  log "Preparing partial S01 workspace: $target_dir"
  sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" SKILL_DEST="$SKILL_DEST" sh -lc '
    set -eu
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    bash "$SKILL_DEST/scripts/bootstrap-investigation.sh" "$TARGET_DIR" INVESTIGATION_BRIEF.md REFERENCE_ARCHITECTURE.md

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/INVESTIGATION_BRIEF.md" <<'"'"'BRIEF'"'"'
# Kafka Architecture Investigation Brief

## Objective

Can a filesystem-level Kafka broker data snapshot from an Apache Kafka 3.7 KRaft source cluster be restored into a smaller local recovery cluster?

## Source Architecture

- Kafka distribution/version: Apache Kafka 3.7.x
- Mode: KRaft
- Broker/controller count: 6 brokers, controllers co-located with brokers
- Regions/sites: single production region
- Storage/snapshot model: filesystem-level broker data directory snapshots captured at a common maintenance point
- Topics/data classes: business topics are in scope; exact topic list and partition counts are not yet known
- Producers: unknown
- Consumers/groups: consumer groups matter but exact groups are not yet known
- Internal features: KRaft metadata, consumer offsets, and broker log state are likely relevant

## Target State

- Intended topology: 3-broker local recovery cluster
- Data movement or recovery mechanism: restore from copied filesystem snapshots into a reduced-broker recovery environment
- Client behavior: unknown
- Ownership/write model: unknown

## Acceptability Boundaries

- Data loss: unknown
- Duplication/reprocessing: unknown
- Ordering: unknown
- Downtime/degraded mode: unknown
- Manual intervention: unknown
- Excluded actions: do not mutate original snapshots or source evidence

## Evidence Required

- Decision supported: whether reduced-broker snapshot restore is feasible and what conditions must hold
- Audience: unknown
- Required artifacts: unknown
- Repeatability target: unknown

## Assumptions Ledger

| ID | Assumption | Source | Impact If Wrong | How To Verify | Status |
| --- | --- | --- | --- | --- | --- |
| A1 | Source is Apache Kafka 3.7.x in KRaft mode. | Seed fixture | Research paths differ by version/mode. | User confirmation or source evidence. | source-backed |
| A2 | Source has 6 brokers with co-located controllers. | Seed fixture | Reduced-broker restore constraints depend on source topology. | User confirmation or source evidence. | source-backed |
| A3 | Target is a 3-broker local recovery cluster. | Seed fixture | Feasibility and reassignment strategy depend on target size. | User confirmation. | source-backed |
| A4 | Snapshot is filesystem-level broker data directory capture at a common maintenance point. | Seed fixture | Different snapshot mechanisms imply different consistency and metadata risks. | User confirmation or artifact inspection. | source-backed |
BRIEF

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/REFERENCE_ARCHITECTURE.md" <<'"'"'ARCH'"'"'
# Reference Architecture

## Current State

Apache Kafka 3.7.x source cluster in KRaft mode. The source has 6 brokers with co-located controllers in a single region. Filesystem-level broker data directory snapshots were captured at a common maintenance point. Business topics and consumer groups matter, but exact topic and partition layout is still unknown.

## Target State

Restore copied snapshot data into a 3-broker local recovery cluster for feasibility testing.

## Ownership And Invariants

- Write ownership: unknown
- Metadata ownership: KRaft
- Offset ownership: consumer group offsets likely matter, exact groups unknown
- Transaction state ownership: unknown
- Data integrity invariants: unknown until acceptable loss/degradation is defined

## Failure Boundary

- In scope: reduced-broker snapshot restore feasibility and local recovery behavior
- Out of scope: mutation of original snapshots or source evidence
- Assumed available: copied filesystem snapshots and local recovery workspace
- Assumed unavailable: production access

## Local Test Surrogate

The local surrogate must preserve KRaft mode, broker-count reduction from 6 to 3, and filesystem-snapshot restore semantics. Topic scale can be reduced only after the important topic, partition, offset, and transaction behaviors are identified.
ARCH

    python3 - "$TARGET_DIR/docs/kafka-architecture-investigation/TRACKER.md" <<'"'"'PY'"'"'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("- YYYY-MM-DD: Initialized tracker.", "- 2026-06-16: Seeded partial S01 fixture with source and target architecture facts.")
path.write_text(text)
PY
  ' >/dev/null
}

prepare_ready_workspace() {
  local target_dir="$1"

  log "Preparing research-ready S01 workspace: $target_dir"
  sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" SKILL_DEST="$SKILL_DEST" sh -lc '
    set -eu
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    bash "$SKILL_DEST/scripts/bootstrap-investigation.sh" "$TARGET_DIR" INVESTIGATION_BRIEF.md REFERENCE_ARCHITECTURE.md

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/INVESTIGATION_BRIEF.md" <<'"'"'BRIEF'"'"'
# Kafka Architecture Investigation Brief

## Objective

Determine whether copied filesystem-level Kafka broker data snapshots from an Apache Kafka 3.7 KRaft source cluster can be restored into a smaller local recovery cluster, and identify the failure modes that must be tested before relying on the process.

## Source Architecture

- Kafka distribution/version: Apache Kafka 3.7.x
- Mode: KRaft
- Broker/controller count: 6 brokers, controllers co-located with brokers
- Regions/sites: single production region
- Storage/snapshot model: filesystem-level broker data directory snapshots captured at a common maintenance point
- Topics/data classes: critical `orders`, `payments`, and `customer-profile` topics; representative partition counts are 24 partitions for `orders`/`payments` and 12 compacted partitions for `customer-profile`; replication factor 3
- Producers: idempotent producers for `orders`; transactional producers for `payments`
- Consumers/groups: `order-service`, `payment-ledger`, and `analytics-replay`; `payment-ledger` uses `read_committed`
- Internal features: KRaft metadata, consumer offsets, transaction state, producer IDs, and broker log state are in scope
- Likely Kafka tracks: KRaft quorum metadata, broker and replica identity, log directory metadata, partition leadership/replicas, consumer offsets, transaction markers/state, and reduced-broker partition placement

## Target State

- Intended topology: 3-broker Apache Kafka 3.7.x local recovery cluster
- Data movement or recovery mechanism: restore from copied filesystem snapshots into a reduced-broker recovery environment
- Client behavior: clients stay disconnected until validation passes; later client routing is out of scope for this proof
- Ownership/write model: recovery cluster is validation-only/read-only until feasibility is proven
- Expected output: determine whether this restore shape is feasible, which rewrites or metadata repairs are required, and which cases fail

## Acceptability Boundaries

- Data loss: no committed business records may be silently lost for critical topics
- Duplication/reprocessing: bounded duplicates or replay are acceptable if documented and recoverable
- Ordering: per-partition ordering must be preserved for restored committed records
- Transactions: aborted records must remain invisible to `read_committed` consumers
- Consumer offsets: offset continuity is required for named groups, or the report must explicitly prove why it cannot be preserved
- Downtime/degraded mode: downtime is acceptable for the local proof; degraded read-only validation is acceptable
- Manual intervention: manual repair is acceptable only on disposable snapshot copies and must be documented
- Excluded actions: do not mutate original snapshots or source evidence; no production access

## Constraints And Safety

- Available locally: Docker/sbx, copied snapshot fixtures, public Kafka docs, Apache Kafka source clone during S02
- Off limits: production systems, credentials, destructive writes to original artifacts, licensed components not already available
- Scale limit: local lab can reduce topic sizes but must preserve the important metadata, offset, transaction, and reduced-broker behaviors
- Network: internet access is allowed for official docs and source clone during S02 only

## Evidence Required

- Decision supported: feasibility of reduced-broker snapshot restore and conditions/failure modes
- Audience: engineering team deciding whether to invest in automation
- Required artifacts: source research, ADR, scenario matrix, implementation spec, runnable local harness, report, and runbook
- Repeatability target: another engineer can rerun the harness from fixed commands and inspect artifacts

## Assumptions Ledger

| ID | Assumption | Source | Impact If Wrong | How To Verify | Status |
| --- | --- | --- | --- | --- | --- |
| A1 | Source is Apache Kafka 3.7.x in KRaft mode. | Seed fixture | Research paths differ by version/mode. | User confirmation or source evidence. | source-backed |
| A2 | Source has 6 brokers with co-located controllers. | Seed fixture | Reduced-broker restore constraints depend on source topology. | User confirmation or source evidence. | source-backed |
| A3 | Target is a 3-broker local recovery cluster. | Seed fixture | Feasibility and reassignment strategy depend on target size. | User confirmation. | source-backed |
| A4 | Snapshot is filesystem-level broker data directory capture at a common maintenance point. | Seed fixture | Different snapshot mechanisms imply different consistency and metadata risks. | User confirmation or artifact inspection. | source-backed |
| A5 | Critical workloads include offsets and transactions that must be represented in tests. | Seed fixture | Scenario design may miss key failure modes. | Source research and local fixtures. | source-backed |
BRIEF

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/REFERENCE_ARCHITECTURE.md" <<'"'"'ARCH'"'"'
# Reference Architecture

## Current State

Apache Kafka 3.7.x source cluster in KRaft mode. The source has 6 brokers with co-located controllers in a single region. Filesystem-level broker data directory snapshots were captured at a common maintenance point. Critical topics include `orders`, `payments`, and compacted `customer-profile`, with consumer groups `order-service`, `payment-ledger`, and `analytics-replay`. Transactional producers and `read_committed` consumers are in scope.

## Target State

Restore copied snapshot data into a 3-broker Apache Kafka 3.7.x local recovery cluster for validation. The recovery cluster is read-only until feasibility and failure modes are proven. Client cutover is out of scope except for validating consumer visibility, offsets, and transaction behavior.

## Ownership And Invariants

- Write ownership: source remains authoritative; recovery target is validation-only
- Metadata ownership: KRaft
- Offset ownership: named consumer groups must preserve or explicitly document offset discontinuity
- Transaction state ownership: restored transaction metadata and markers must keep aborted records invisible to `read_committed`
- Data integrity invariants: no silent committed-record loss for critical topics; per-partition ordering preserved for restored records; bounded replay is acceptable if documented

## Failure Boundary

- In scope: reduced-broker snapshot restore feasibility, metadata identity mismatch, partition placement, offsets, transactions, compaction, and local recovery behavior
- Out of scope: mutation of original snapshots, production access, client cutover automation, and licensed components
- Assumed available: copied filesystem snapshots, Docker/sbx, public Kafka docs, Apache Kafka source clone during S02
- Assumed unavailable: production credentials and live source cluster access

## Local Test Surrogate

The local surrogate must preserve KRaft mode, broker-count reduction from 6 to 3, filesystem-snapshot restore semantics, representative critical topics, consumer offsets, and transaction visibility. Topic scale can be reduced, but metadata, offset, transaction, and reduced-broker placement behaviors cannot be removed from the proof.
ARCH

    python3 - "$TARGET_DIR/docs/kafka-architecture-investigation/TRACKER.md" <<'"'"'PY'"'"'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("- YYYY-MM-DD: Initialized tracker.", "- 2026-06-16: Seeded research-ready S01 fixture with source, target, acceptability, constraints, evidence, and Kafka tracks.")
path.write_text(text)
PY
  ' >/dev/null
}

make_prompt() {
  local case_name="$1"
  local target_dir="$2"

  case "$case_name" in
    partial-s01)
      cat <<PROMPT
Use \$kafka-architecture-investigation to resume the existing Kafka investigation in $target_dir.

The workspace already contains a partial S01 intake with source architecture, target architecture, and snapshot mechanism details. Continue from the tracker. Do not research Kafka docs/source yet. Do not create Docker Compose, scripts, scenarios, or a harness yet. Preserve the existing facts, update only the active S01 documents if needed, and ask only the next missing intake questions required by the research-ready gate.
PROMPT
      ;;
    ready-s01)
      cat <<PROMPT
Use \$kafka-architecture-investigation to resume the existing Kafka investigation in $target_dir.

The workspace already contains a research-ready S01 intake: source estate, target state, acceptability boundaries, constraints, evidence needs, and likely Kafka tracks are all recorded. Continue from the tracker. Do not research Kafka docs/source in this run. Do not create Docker Compose, scripts, scenarios, a harness, ADR, or source research content yet. If the S01 gate is satisfied, update the tracker to mark S01 done, move the current cursor to S02, and stop with a concise status note. Do not ask more intake questions.
PROMPT
      ;;
    *)
      echo "Unknown Phase C case: $case_name" >&2
      exit 2
      ;;
  esac
}

score_run() {
  local case_name="$1"
  local host_run_dir="$2"
  local final="$host_run_dir/final.md"
  local trace="$host_run_dir/trace.log"
  local target_dump="$host_run_dir/target-files.txt"
  local tracker="$host_run_dir/TRACKER.md"
  local brief="$host_run_dir/INVESTIGATION_BRIEF.md"
  local arch="$host_run_dir/REFERENCE_ARCHITECTURE.md"

  local result tracker_exists brief_exists arch_exists facts_preserved s01_state_ok s02_state_ok cursor_ok
  local asks_questions q_count no_research no_harness no_extra_docs case_gate_ok

  tracker_exists="$(bool test -s "$tracker")"
  brief_exists="$(bool test -s "$brief")"
  arch_exists="$(bool test -s "$arch")"
  facts_preserved="$(bool sh -c '
    grep -Eiq "Apache Kafka 3\\.7|3\\.7\\.x" "$1" "$2" &&
    grep -Eiq "KRaft" "$1" "$2" &&
    grep -Eiq "6 brokers|6-broker|six brokers" "$1" "$2" &&
    grep -Eiq "3-broker|3 brokers|three-broker" "$1" "$2" &&
    grep -Eiq "filesystem|data directory|data dir" "$1" "$2"
  ' sh "$brief" "$arch")"
  if grep -Fq '?' "$final" ||
     grep -Eq '(^|[[:space:]])(What|Which|Could you|Can you|Please confirm)[[:space:]]' "$final"; then
    asks_questions="yes"
  else
    asks_questions="no"
  fi
  q_count="$(question_count "$final")"
  if grep -Eiq 'git clone|github.com/apache/kafka|https?://(kafka\.apache\.org|docs\.confluent\.io|www\.confluent\.io)' "$trace"; then
    no_research="no"
  else
    no_research="yes"
  fi
  if grep -Eq 'docker compose|docker-compose|reset.sh|seed.sh|capture.sh|mutate.sh|start.sh|assert.sh|report.sh' "$trace"; then
    no_harness="no"
  else
    no_harness="yes"
  fi
  if grep -Eq 'SOURCE_RESEARCH.md|SCENARIO_MATRIX.tsv|HARNESS_SPEC.md|IMPLEMENTATION_SPEC.md|ADR.md' "$target_dump"; then
    no_extra_docs="no"
  else
    no_extra_docs="yes"
  fi

  case "$case_name" in
    partial-s01)
      s01_state_ok="$(bool grep -Eq 'S01-user-sync[[:space:]]*\\|[[:space:]]*in_progress' "$tracker")"
      s02_state_ok="$(bool grep -Eq 'S02-source-research[[:space:]]*\\|[[:space:]]*pending' "$tracker")"
      cursor_ok="$(bool sh -c '
        grep -Eiq "Active step: S01-user-sync" "$1" &&
        grep -Eiq "Read now:.*references/intake\\.md" "$1" &&
        grep -Eiq "Read now:.*INVESTIGATION_BRIEF\\.md" "$1" &&
        grep -Eiq "Read now:.*REFERENCE_ARCHITECTURE\\.md" "$1"
      ' sh "$tracker")"
      case_gate_ok="$(bool sh -c '
        grep -Eiq "workload|topic|transaction|consumer|client|offset|loss|data loss|duplicate|reprocess|downtime|manual|degraded|evidence|artifact|ADR|report|runbook|scenario|harness" "$1"
      ' sh "$final")"
      ;;
    ready-s01)
      s01_state_ok="$(bool grep -Eq 'S01-user-sync[[:space:]]*\\|[[:space:]]*done' "$tracker")"
      s02_state_ok="$(bool grep -Eq 'S02-source-research[[:space:]]*\\|[[:space:]]*(pending|in_progress)' "$tracker")"
      cursor_ok="$(bool sh -c '
        grep -Eiq "Active step: S02-source-research" "$1" &&
        grep -Eiq "Read now:.*references/kafka-internals-checklist\\.md" "$1" &&
        grep -Eiq "Read now:.*INVESTIGATION_BRIEF\\.md" "$1" &&
        grep -Eiq "Read now:.*REFERENCE_ARCHITECTURE\\.md" "$1" &&
        grep -Eiq "Read now:.*SOURCE_RESEARCH\\.md" "$1"
      ' sh "$tracker")"
      case_gate_ok="$(bool sh -c '
        grep -Eiq "S02|source research|research-ready|research ready" "$1"
      ' sh "$final")"
      ;;
    *)
      echo "Unknown Phase C case: $case_name" >&2
      exit 2
      ;;
  esac

  result="fail"
  if [ "$tracker_exists" = "yes" ] &&
     [ "$brief_exists" = "yes" ] &&
     [ "$arch_exists" = "yes" ] &&
     [ "$facts_preserved" = "yes" ] &&
     [ "$s01_state_ok" = "yes" ] &&
     [ "$s02_state_ok" = "yes" ] &&
     [ "$cursor_ok" = "yes" ] &&
     [ "$no_research" = "yes" ] &&
     [ "$no_harness" = "yes" ] &&
     [ "$no_extra_docs" = "yes" ] &&
     [ "$case_gate_ok" = "yes" ]; then
    case "$case_name" in
      partial-s01)
        if [ "$asks_questions" = "yes" ] && [ "$q_count" -ge 1 ] && [ "$q_count" -le 5 ]; then
          result="pass"
        fi
        ;;
      ready-s01)
        if [ "$asks_questions" = "no" ] && [ "$q_count" -eq 0 ]; then
          result="pass"
        fi
        ;;
    esac
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$result" \
    "$tracker_exists" \
    "$brief_exists" \
    "$arch_exists" \
    "$facts_preserved" \
    "$s01_state_ok" \
    "$s02_state_ok" \
    "$cursor_ok" \
    "$asks_questions" \
    "$q_count" \
    "$no_research" \
    "$no_harness" \
    "$no_extra_docs" \
    "$case_gate_ok" \
    "$case_name" \
    "$host_run_dir"
}

write_markdown_summary() {
  local summary_tsv="$1"
  local summary_md="$2"

  {
    echo '# kafka-architecture-investigation Phase C Resume Summary'
    echo
    echo "Run set: \`$RUN_SET\`"
    echo
    echo '| Case | Model | Effort | Exit | Result | Seconds | Tokens | Tracker | Brief | Architecture | Facts Preserved | S01 State OK | S02 State OK | Cursor OK | Asked Questions | Question Count | No Research | No Harness | No Extra Docs | Case Gate OK |'
    echo '|---|---|---:|---:|---|---:|---:|---|---|---|---|---|---|---|---|---:|---|---|---|---|'
    awk -F '\t' 'NR > 1 {
      printf "| `%s` | `%s` | `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20
    }' "$summary_tsv"
  } > "$summary_md"
}

mkdir -p "$RESULTS_DIR"

summary_tsv="$RESULTS_DIR/summary.tsv"
summary_md="$RESULTS_DIR/summary.md"
any_fail=0

printf 'case\tmodel\teffort\texit_code\tresult\telapsed_seconds\ttokens_used\ttracker_exists\tbrief_exists\tarchitecture_exists\tfacts_preserved\ts01_state_ok\ts02_state_ok\tcursor_ok\tasks_questions\tquestion_count\tno_research\tno_harness\tno_extra_docs\tcase_gate_ok\tlog_dir\n' > "$summary_tsv"

if is_truthy "$SYNC_HOST_CODEX_AUTH"; then
  sync_host_codex_auth
fi

refresh_skill
check_ready

for case_name in partial-s01 ready-s01; do
  run_id="${case_name}-${MODEL}-${EFFORT}"
  host_run_dir="$RESULTS_DIR/$run_id"
  sandbox_run_dir="$SANDBOX_WORKSPACE/evaluation-runs/$RUN_SET/$run_id"
  target_dir="$SANDBOX_WORKSPACE/kafka-architecture-investigation-$RUN_SET-$case_name"

  mkdir -p "$host_run_dir"

  case "$case_name" in
    partial-s01)
      prepare_partial_workspace "$target_dir"
      ;;
    ready-s01)
      prepare_ready_workspace "$target_dir"
      ;;
  esac

  prompt="$(make_prompt "$case_name" "$target_dir")"
  printf '%s\n' "$prompt" > "$host_run_dir/prompt.txt"

  sbx exec "$SBX_NAME" -- env SANDBOX_RUN_DIR="$sandbox_run_dir" RUN_PROMPT="$prompt" sh -lc '
    rm -rf "$SANDBOX_RUN_DIR"
    mkdir -p "$SANDBOX_RUN_DIR"
    printf "%s\n" "$RUN_PROMPT" > "$SANDBOX_RUN_DIR/prompt.txt"
  ' >/dev/null

  log "Running $case_name resume model=$MODEL effort=$EFFORT target=$target_dir"
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
      find "$TARGET_DIR" -maxdepth 4 -type f -print | sort
    fi
  ' > "$host_run_dir/target-files.txt" 2>/dev/null || : > "$host_run_dir/target-files.txt"

  for doc in TRACKER.md INVESTIGATION_BRIEF.md REFERENCE_ARCHITECTURE.md SOURCE_RESEARCH.md SCENARIO_MATRIX.tsv HARNESS_SPEC.md IMPLEMENTATION_SPEC.md ADR.md REPORT.md RUNBOOK.md; do
    sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" DOC="$doc" sh -lc '
      path="$TARGET_DIR/docs/kafka-architecture-investigation/$DOC"
      test -f "$path" && cat "$path"
    ' > "$host_run_dir/$doc" 2>/dev/null || : > "$host_run_dir/$doc"
  done

  scores="$(score_run "$case_name" "$host_run_dir")"
  IFS=$'\t' read -r result tracker_exists brief_exists architecture_exists facts_preserved s01_state_ok s02_state_ok cursor_ok asks_questions q_count no_research no_harness no_extra_docs case_gate_ok scored_case log_dir <<< "$scores"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$case_name" \
    "$MODEL" \
    "$EFFORT" \
    "$exit_code" \
    "$result" \
    "$elapsed_seconds" \
    "$tokens_used" \
    "$tracker_exists" \
    "$brief_exists" \
    "$architecture_exists" \
    "$facts_preserved" \
    "$s01_state_ok" \
    "$s02_state_ok" \
    "$cursor_ok" \
    "$asks_questions" \
    "$q_count" \
    "$no_research" \
    "$no_harness" \
    "$no_extra_docs" \
    "$case_gate_ok" \
    "$log_dir" >> "$summary_tsv"

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
