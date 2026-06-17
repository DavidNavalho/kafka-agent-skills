#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run-phase-e-toy-loop.sh [options]

Run the Phase E toy autonomous-loop evaluation for kafka-architecture-investigation.

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
RUN_SET="${RUN_SET:-phase-e-toy-loop-$(date +%Y%m%d-%H%M%S)}"
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
  local target_dir="$1"

  log "Preparing Phase E toy workspace: $target_dir"
  sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" SKILL_DEST="$SKILL_DEST" sh -lc '
    set -eu
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    bash "$SKILL_DEST/scripts/bootstrap-investigation.sh" "$TARGET_DIR" \
      INVESTIGATION_BRIEF.md REFERENCE_ARCHITECTURE.md SOURCE_RESEARCH.md ADR.md \
      SCENARIO_MATRIX.tsv IMPLEMENTATION_SPEC.md HARNESS_SPEC.md

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/INVESTIGATION_BRIEF.md" <<'"'"'BRIEF'"'"'
# Kafka Architecture Investigation Brief

## Objective

Toy Phase E validation: prove the autonomous implementation loop can execute pending shell-testable steps, validate evidence, update statuses, and continue without Kafka or Docker.

## Source Architecture

- Kafka distribution/version: toy fixture, no Kafka runtime.
- Likely Kafka tracks: autonomous execution mechanics only.

## Target State

- Execute the toy harness scripts in order on disposable files under `artifacts/kafka-architecture-investigation/`.

## Acceptability Boundaries

- All toy implementation steps must become `done`.
- Scenario `T001` must become `passed`.
- Evidence must be written under the fixed artifact root.

## Constraints And Safety

- No Docker, Kafka, network, or destructive host access.
- Generated state stays under `artifacts/kafka-architecture-investigation/`.

## Evidence Required

- Updated `IMPLEMENTATION_SPEC.md`
- Updated `SCENARIO_MATRIX.tsv`
- Toy artifact files and command log
BRIEF

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/REFERENCE_ARCHITECTURE.md" <<'"'"'ARCH'"'"'
# Reference Architecture

## Current State

Toy text fixture with deterministic shell scripts.

## Target State

Disposable toy run under `artifacts/kafka-architecture-investigation/runs/toy-autonomous-loop`.

## Ownership And Invariants

- Generated artifacts must remain project-local.
- The assertion script is authoritative for pass/fail.

## Failure Boundary

- In scope: autonomous loop behavior, status updates, and evidence capture.
- Out of scope: Kafka runtime behavior.

## Local Test Surrogate

The toy surrogate replaces Kafka with file transformations so the loop mechanics can be tested cheaply.
ARCH

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/SOURCE_RESEARCH.md" <<'"'"'RESEARCH'"'"'
# Source Research

## Scope

- Subsystems: autonomous loop mechanics only

## Claims

### Claim C1

- Subsystem: Toy harness
- Source/doc path: `scripts/kafka-architecture-investigation/*.sh`
- Evidence: The shell scripts are deterministic and write fixed artifacts.
- Implication for scenario design: The autonomous loop can be validated without Kafka.
- Confidence: locally-tested
RESEARCH

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/ADR.md" <<'"'"'ADR'"'"'
# ADR: Validate autonomous loop with toy shell harness

## Status

Proposed

## Context

The skill must prove it can continue from a pending implementation spec, run deterministic commands, validate evidence, update statuses, and stop only when complete or blocked.

## Decision Drivers

- Avoid Kafka/Docker cost for loop validation.
- Use fixed artifact paths.
- Require status updates after execution.

## Options

- Real Kafka loop: deferred.
- Toy shell loop: selected for cheap validation.

## Decision

Use a toy shell harness that transforms a text fixture and asserts the result.

## Evidence

- Source research: C1 toy harness.
- Scenario results: pending.
- Harness run: pending.

## Scenario Coverage Plan

| Objective | ADR Claim | Scenario Family | Required Evidence |
| --- | --- | --- | --- |
| O1 autonomous loop completes pending steps | C1 | Toy file transform | command log, assertion file, summary TSV |

## Consequences

- This proves loop mechanics only, not Kafka behavior.
ADR

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/SCENARIO_MATRIX.tsv" <<'"'"'MATRIX'"'"'
scenario_id	track	objective_ids	adr_claim_ids	purpose	setup	fault_or_mutation	expected_result	assertions	artifacts	implementation_step_ids	status	notes
T001	toy-loop	O1	C1	Prove the autonomous loop executes all pending toy steps	Use project-local shell scripts and a deterministic text fixture	Transform lowercase fixture text to uppercase	Toy assertion passes and summary.tsv records pass	Expected transformed text equals ALPHA-BETA	artifacts/kafka-architecture-investigation/runs/toy-autonomous-loop/	I001,I002	planned	No Kafka or Docker
MATRIX

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/IMPLEMENTATION_SPEC.md" <<'"'"'SPEC'"'"'
# Implementation Specification

## Inputs

- Scenario matrix: `SCENARIO_MATRIX.tsv`
- Harness spec: `HARNESS_SPEC.md`

## Quality Gates

- ADR completion gate satisfied: yes
- Objective-to-scenario coverage complete: yes
- Deterministic construction defined for each implemented scenario: yes
- Harness artifact contract defined: yes
- Safety boundaries reviewed: yes

## Step Plan

| Step ID | Scenario IDs | Action | Expected Output | Validation Gate | Status |
| --- | --- | --- | --- | --- | --- |
| I001 | T001 | Run `reset.sh`, `seed.sh`, and `capture.sh` | Baseline toy input and snapshot exist | `artifacts/kafka-architecture-investigation/snapshots/toy/input.txt` contains `alpha-beta` | planned |
| I002 | T001 | Run `mutate.sh`, `start.sh`, `assert.sh`, and `report.sh` | Transformed toy output and report exist | `artifacts/kafka-architecture-investigation/runs/toy-autonomous-loop/assertions/result.txt` contains `pass` | planned |

## Autonomous Execution Rules

- Start with the first step whose status is not `done`.
- Execute one pending step, run its validation gate, update status and evidence, then continue to the next pending step.
- Stop only when every step is `done` or a real blocker is recorded.

## Open Implementation Questions

-
SPEC

    cat > "$TARGET_DIR/docs/kafka-architecture-investigation/HARNESS_SPEC.md" <<'"'"'HARNESS'"'"'
# Harness Specification

## Root

- Script root: `scripts/kafka-architecture-investigation/`
- Artifact root: `artifacts/kafka-architecture-investigation/`
- Lab root: `artifacts/kafka-architecture-investigation/runs/toy-autonomous-loop`
- Immutable input root: `artifacts/kafka-architecture-investigation/snapshots/toy`

## Commands

- Reset: `scripts/kafka-architecture-investigation/reset.sh`
- Seed: `scripts/kafka-architecture-investigation/seed.sh`
- Capture: `scripts/kafka-architecture-investigation/capture.sh`
- Mutate: `scripts/kafka-architecture-investigation/mutate.sh`
- Start: `scripts/kafka-architecture-investigation/start.sh`
- Assert: `scripts/kafka-architecture-investigation/assert.sh`
- Report: `scripts/kafka-architecture-investigation/report.sh`

## Scenario Execution

Run commands in the order required by the active implementation step. Evidence stays under the artifact root.

## Validation Gates

- I001: snapshot input contains `alpha-beta`
- I002: assertion result contains `pass`
HARNESS

    script_dir="$TARGET_DIR/scripts/kafka-architecture-investigation"
    mkdir -p "$script_dir"

    cat > "$script_dir/reset.sh" <<'"'"'SCRIPT'"'"'
#!/usr/bin/env bash
set -euo pipefail
root="artifacts/kafka-architecture-investigation"
run="$root/runs/toy-autonomous-loop"
rm -rf "$run" "$root/snapshots/toy"
mkdir -p "$run/inputs" "$run/working-copy" "$run/logs" "$run/assertions" "$root/snapshots/toy"
printf "reset\n" > "$run/command-log.txt"
SCRIPT

    cat > "$script_dir/seed.sh" <<'"'"'SCRIPT'"'"'
#!/usr/bin/env bash
set -euo pipefail
run="artifacts/kafka-architecture-investigation/runs/toy-autonomous-loop"
mkdir -p "$run/inputs"
printf "alpha-beta\n" > "$run/inputs/input.txt"
printf "seed\n" >> "$run/command-log.txt"
SCRIPT

    cat > "$script_dir/capture.sh" <<'"'"'SCRIPT'"'"'
#!/usr/bin/env bash
set -euo pipefail
root="artifacts/kafka-architecture-investigation"
run="$root/runs/toy-autonomous-loop"
mkdir -p "$root/snapshots/toy"
cp "$run/inputs/input.txt" "$root/snapshots/toy/input.txt"
printf "capture\n" >> "$run/command-log.txt"
SCRIPT

    cat > "$script_dir/mutate.sh" <<'"'"'SCRIPT'"'"'
#!/usr/bin/env bash
set -euo pipefail
root="artifacts/kafka-architecture-investigation"
run="$root/runs/toy-autonomous-loop"
tr "[:lower:]" "[:upper:]" < "$root/snapshots/toy/input.txt" > "$run/working-copy/output.txt"
printf "mutate\n" >> "$run/command-log.txt"
SCRIPT

    cat > "$script_dir/start.sh" <<'"'"'SCRIPT'"'"'
#!/usr/bin/env bash
set -euo pipefail
run="artifacts/kafka-architecture-investigation/runs/toy-autonomous-loop"
printf "toy target started\n" > "$run/logs/start.log"
printf "start\n" >> "$run/command-log.txt"
SCRIPT

    cat > "$script_dir/assert.sh" <<'"'"'SCRIPT'"'"'
#!/usr/bin/env bash
set -euo pipefail
run="artifacts/kafka-architecture-investigation/runs/toy-autonomous-loop"
test "$(cat "$run/working-copy/output.txt")" = "ALPHA-BETA"
printf "pass\n" > "$run/assertions/result.txt"
mkdir -p "$run/scenarios/T001/assertions"
cp "$run/assertions/result.txt" "$run/scenarios/T001/assertions/result.txt"
printf "T001\tpass\tALPHA-BETA\tALPHA-BETA\t%s\ttoy assertion passed\n" "$run/assertions/result.txt" > "$run/summary.tsv"
printf "assert\n" >> "$run/command-log.txt"
SCRIPT

    cat > "$script_dir/report.sh" <<'"'"'SCRIPT'"'"'
#!/usr/bin/env bash
set -euo pipefail
run="artifacts/kafka-architecture-investigation/runs/toy-autonomous-loop"
mkdir -p "$run/scenarios/T001"
cat > "$run/scenarios/T001/report.md" <<REPORT
# T001 Toy Report

Status: pass
Evidence: $run/assertions/result.txt
REPORT
printf "report\n" >> "$run/command-log.txt"
SCRIPT

    chmod +x "$script_dir"/*.sh

    python3 "$SKILL_DEST/scripts/update-tracker-state.py" "$TARGET_DIR" \
      --step-status S01-user-sync=done \
      --step-status S02-source-research=done \
      --step-status S03-adr=done \
      --step-status S04-scenarios-spec=done \
      --step-status S05-harness=done \
      --step-status S06-execute=pending \
      --cursor S06-execute \
      --cursor-status pending
  ' >/dev/null
}

make_prompt() {
  local target_dir="$1"

  cat <<PROMPT
Use \$kafka-architecture-investigation to resume the existing Kafka investigation in $target_dir.

The tracker is at S06-execute. This is a toy autonomous-loop fixture with shell-testable scripts only; do not use Kafka, Docker, network, or external tools. Start from the first pending implementation step in IMPLEMENTATION_SPEC.md, execute the listed commands, validate the gate, update IMPLEMENTATION_SPEC.md and SCENARIO_MATRIX.tsv statuses/evidence, then continue until all implementation steps are done or a real blocker is recorded. Use done for implementation step statuses, but use passed for the T001 scenario status when assertions pass; do not use done as a scenario status. When all steps are done, mark S06 done, move the tracker cursor to S07-report-runbook, and stop.
PROMPT
}

score_run() {
  local host_run_dir="$1"
  local trace="$host_run_dir/trace.log"
  local tracker="$host_run_dir/TRACKER.md"
  local matrix="$host_run_dir/SCENARIO_MATRIX.tsv"
  local spec="$host_run_dir/IMPLEMENTATION_SPEC.md"
  local target_dump="$host_run_dir/target-files.txt"
  local artifacts="$host_run_dir/artifact-files.txt"
  local command_log="$host_run_dir/artifacts/toy-autonomous-loop/command-log.txt"

  local result no_external scripts_executed artifacts_ok statuses_ok cursor_ok no_kafka

  if grep -Eiq 'git clone|curl[[:space:]]|https?://|docker compose|docker-compose|kafka-topics|kafka-console|kafka-storage|kafka-server-start' "$trace"; then
    no_external="no"
  else
    no_external="yes"
  fi
  if test -s "$command_log" &&
     grep -Fxq "reset" "$command_log" &&
     grep -Fxq "seed" "$command_log" &&
     grep -Fxq "capture" "$command_log" &&
     grep -Fxq "mutate" "$command_log" &&
     grep -Fxq "start" "$command_log" &&
     grep -Fxq "assert" "$command_log" &&
     grep -Fxq "report" "$command_log"; then
    scripts_executed="yes"
  else
    scripts_executed="no"
  fi
  artifacts_ok="$(bool sh -c '
    grep -Eq "runs/toy-autonomous-loop/assertions/result\\.txt" "$1" &&
    grep -Eq "runs/toy-autonomous-loop/summary\\.tsv" "$1" &&
    grep -Eq "runs/toy-autonomous-loop/scenarios/T001/report\\.md" "$1" &&
    test -s "$2/result.txt" &&
    grep -Fxq "pass" "$2/result.txt"
  ' sh "$artifacts" "$host_run_dir/artifacts/toy-autonomous-loop/assertions")"
  statuses_ok="$(bool sh -c '
    grep -Eq "\\| I001 \\| T001 \\|.*\\| done \\|" "$1" &&
    grep -Eq "\\| I002 \\| T001 \\|.*\\| done \\|" "$1" &&
    awk -F "\t" "NR > 1 && \$1 == \"T001\" && \$12 == \"passed\" { found=1 } END { exit(found ? 0 : 1) }" "$2"
  ' sh "$spec" "$matrix")"
  cursor_ok="$(bool sh -c '
    grep -Eiq "Active step: S07-report-runbook" "$1" &&
    grep -Eq "S06-execute[[:space:]]*\\|[[:space:]]*done" "$1"
  ' sh "$tracker")"
  if grep -Eiq 'docker-compose\.ya?ml|server\.properties|broker-[0-9]|kafka-server|kafka-topics|kafka-console|kafka-storage' "$target_dump"; then
    no_kafka="no"
  else
    no_kafka="yes"
  fi

  result="fail"
  if [ "$no_external" = "yes" ] &&
     [ "$scripts_executed" = "yes" ] &&
     [ "$artifacts_ok" = "yes" ] &&
     [ "$statuses_ok" = "yes" ] &&
     [ "$cursor_ok" = "yes" ] &&
     [ "$no_kafka" = "yes" ]; then
    result="pass"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$result" \
    "$no_external" \
    "$scripts_executed" \
    "$artifacts_ok" \
    "$statuses_ok" \
    "$cursor_ok" \
    "$no_kafka"
}

write_markdown_summary() {
  local summary_tsv="$1"
  local summary_md="$2"

  {
    echo '# kafka-architecture-investigation Phase E Toy Loop Summary'
    echo
    echo "Run set: \`$RUN_SET\`"
    echo
    echo '| Model | Effort | Exit | Result | Seconds | Tokens | No External | Scripts Executed | Artifacts OK | Statuses OK | Cursor OK | No Kafka/Docker Files |'
    echo '|---|---:|---:|---|---:|---:|---|---|---|---|---|---|'
    awk -F '\t' 'NR > 1 {
      printf "| `%s` | `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12
    }' "$summary_tsv"
  } > "$summary_md"
}

mkdir -p "$RESULTS_DIR"

run_id="toy-loop-${MODEL}-${EFFORT}"
host_run_dir="$RESULTS_DIR/$run_id"
sandbox_run_dir="$SANDBOX_WORKSPACE/evaluation-runs/$RUN_SET/$run_id"
target_dir="$SANDBOX_WORKSPACE/kafka-architecture-investigation-$RUN_SET"
summary_tsv="$RESULTS_DIR/summary.tsv"
summary_md="$RESULTS_DIR/summary.md"

mkdir -p "$host_run_dir"
printf 'model\teffort\texit_code\tresult\telapsed_seconds\ttokens_used\tno_external\tscripts_executed\tartifacts_ok\tstatuses_ok\tcursor_ok\tno_kafka_files\tlog_dir\n' > "$summary_tsv"

if is_truthy "$SYNC_HOST_CODEX_AUTH"; then
  sync_host_codex_auth
fi

refresh_skill
check_ready
prepare_workspace "$target_dir"

prompt="$(make_prompt "$target_dir")"
printf '%s\n' "$prompt" > "$host_run_dir/prompt.txt"

sbx exec "$SBX_NAME" -- env SANDBOX_RUN_DIR="$sandbox_run_dir" RUN_PROMPT="$prompt" sh -lc '
  rm -rf "$SANDBOX_RUN_DIR"
  mkdir -p "$SANDBOX_RUN_DIR"
  printf "%s\n" "$RUN_PROMPT" > "$SANDBOX_RUN_DIR/prompt.txt"
' >/dev/null

log "Running Phase E toy loop model=$MODEL effort=$EFFORT target=$target_dir"
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
    find "$TARGET_DIR" -maxdepth 6 -type f -print | sort
  fi
' > "$host_run_dir/target-files.txt" 2>/dev/null || : > "$host_run_dir/target-files.txt"

sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" sh -lc '
  root="$TARGET_DIR/artifacts/kafka-architecture-investigation"
  if [ -d "$root" ]; then
    find "$root" -type f -print | sort
  fi
' > "$host_run_dir/artifact-files.txt" 2>/dev/null || : > "$host_run_dir/artifact-files.txt"

for doc in TRACKER.md SCENARIO_MATRIX.tsv IMPLEMENTATION_SPEC.md HARNESS_SPEC.md; do
  sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" DOC="$doc" sh -lc '
    path="$TARGET_DIR/docs/kafka-architecture-investigation/$DOC"
    test -f "$path" && cat "$path"
  ' > "$host_run_dir/$doc" 2>/dev/null || : > "$host_run_dir/$doc"
done

mkdir -p "$host_run_dir/artifacts/toy-autonomous-loop/assertions"
sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" sh -lc '
  path="$TARGET_DIR/artifacts/kafka-architecture-investigation/runs/toy-autonomous-loop/assertions/result.txt"
  test -f "$path" && cat "$path"
' > "$host_run_dir/artifacts/toy-autonomous-loop/assertions/result.txt" 2>/dev/null || : > "$host_run_dir/artifacts/toy-autonomous-loop/assertions/result.txt"

sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" sh -lc '
  path="$TARGET_DIR/artifacts/kafka-architecture-investigation/runs/toy-autonomous-loop/command-log.txt"
  test -f "$path" && cat "$path"
' > "$host_run_dir/artifacts/toy-autonomous-loop/command-log.txt" 2>/dev/null || : > "$host_run_dir/artifacts/toy-autonomous-loop/command-log.txt"

scores="$(score_run "$host_run_dir")"
IFS=$'\t' read -r result no_external scripts_executed artifacts_ok statuses_ok cursor_ok no_kafka_files <<< "$scores"

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$MODEL" \
  "$EFFORT" \
  "$exit_code" \
  "$result" \
  "$elapsed_seconds" \
  "$tokens_used" \
  "$no_external" \
  "$scripts_executed" \
  "$artifacts_ok" \
  "$statuses_ok" \
  "$cursor_ok" \
  "$no_kafka_files" \
  "$host_run_dir" >> "$summary_tsv"

write_markdown_summary "$summary_tsv" "$summary_md"

log "Result: $result exit=$exit_code seconds=$elapsed_seconds tokens=$tokens_used"
log "Summary: $summary_md"

if [ "$result" != "pass" ]; then
  exit 1
fi
