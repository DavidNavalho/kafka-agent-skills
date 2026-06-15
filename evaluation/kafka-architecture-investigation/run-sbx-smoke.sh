#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run-sbx-smoke.sh [options]

Run a low-cost sbx evaluation for kafka-architecture-investigation.

Options:
  --sbx NAME           sbx sandbox name. Defaults to agent-skills-eval.
  --model NAME         Codex model. Defaults to gpt-5.3-codex-spark.
  --effort NAME        Reasoning effort. Defaults to low.
  --results-dir DIR    Host results directory.
  -h, --help           Show this help.

Environment:
  SBX_NAME             agent-skills-eval
  MODEL                gpt-5.3-codex-spark
  EFFORT               low
  SANDBOX_WORKSPACE    /home/agent/workspace
  SKILL_SOURCE         Repo-local skills/kafka-architecture-investigation
  SKILL_DEST           /home/agent/.codex/skills/kafka-architecture-investigation
  PROMPT_TEXT          Optional prompt. Use {{TARGET_DIR}} for insertion.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SBX_NAME="${SBX_NAME:-agent-skills-eval}"
MODEL="${MODEL:-gpt-5.3-codex-spark}"
EFFORT="${EFFORT:-low}"
SANDBOX_WORKSPACE="${SANDBOX_WORKSPACE:-/home/agent/workspace}"
SKILL_SOURCE="${SKILL_SOURCE:-$REPO_ROOT/skills/kafka-architecture-investigation}"
SKILL_DEST="${SKILL_DEST:-/home/agent/.codex/skills/kafka-architecture-investigation}"
RUN_SET="${RUN_SET:-$(date +%Y%m%d-%H%M%S)}"
RESULTS_DIR="${RESULTS_DIR:-$SCRIPT_DIR/evaluation-runs/$RUN_SET}"
PROMPT_TEXT="${PROMPT_TEXT:-}"

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
  log "Checking Codex runner inside sbx"
  sbx exec "$SBX_NAME" -- sh -lc '
    command -v codex >/dev/null 2>&1 || {
      echo "codex is not installed in sbx" >&2
      exit 1
    }
    codex login status >/dev/null 2>&1 || {
      echo "codex is not authenticated in sbx" >&2
      exit 1
    }
  ' >/dev/null
}

make_prompt() {
  local target_dir="$1"

  if [ -n "$PROMPT_TEXT" ]; then
    printf '%s\n' "${PROMPT_TEXT//\{\{TARGET_DIR\}\}/$target_dir}"
    return 0
  fi

  cat <<PROMPT
Use \$kafka-architecture-investigation to start investigating this Kafka architecture question in $target_dir: can we restore a Kafka snapshot into a smaller local recovery cluster?

Known context:
- The source Kafka estate used KRaft.
- The target recovery cluster has fewer brokers than the source.
- I do not yet know the Kafka version, topic layout, snapshot mechanism, acceptable loss/degradation, or evidence requirements.

Do not research Kafka docs or source yet. Do not create Docker Compose, scripts, scenarios, or a harness yet. Start the investigation properly with the tracker-first workflow and ask the next focused intake questions.
PROMPT
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

score_run() {
  local host_run_dir="$1"
  local target_dump="$host_run_dir/target-files.txt"
  local final="$host_run_dir/final.md"
  local trace="$host_run_dir/trace.log"
  local brief="$host_run_dir/INVESTIGATION_BRIEF.md"
  local arch="$host_run_dir/REFERENCE_ARCHITECTURE.md"
  local tracker="$host_run_dir/TRACKER.md"

  local tracker_exists brief_exists arch_exists source_research_absent scenarios_absent harness_absent
  local asks_questions no_research no_harness question_count mentions_tracker_first read_now_present auth_failed result

  tracker_exists="$(bool test -s "$tracker")"
  brief_exists="$(bool test -s "$brief")"
  arch_exists="$(bool test -s "$arch")"
  if grep -q 'SOURCE_RESEARCH.md' "$target_dump"; then
    source_research_absent="no"
  else
    source_research_absent="yes"
  fi
  if grep -q 'SCENARIO_MATRIX.tsv' "$target_dump"; then
    scenarios_absent="no"
  else
    scenarios_absent="yes"
  fi
  if grep -Eq 'docker-compose|scripts/kafka-architecture-investigation|HARNESS_SPEC.md' "$target_dump"; then
    harness_absent="no"
  else
    harness_absent="yes"
  fi
  asks_questions="$(bool grep -Eq '\\?|What |Which |Could you|Can you|Please confirm' "$final")"
  if grep -Eiq 'git clone|github.com/apache/kafka|kafka.apache.org|confluent.io|SOURCE_RESEARCH' "$trace"; then
    no_research="no"
  else
    no_research="yes"
  fi
  if grep -Eq 'docker compose|docker-compose|reset.sh|seed.sh|capture.sh|mutate.sh|start.sh|assert.sh|report.sh' "$trace"; then
    no_harness="no"
  else
    no_harness="yes"
  fi
  mentions_tracker_first="$(bool grep -Eiq 'tracker|TRACKER.md' "$final")"
  read_now_present="$(bool grep -q 'Read now:' "$tracker")"
  auth_failed="$(bool grep -Eq '401 Unauthorized|Incorrect API key' "$trace")"
  question_count="$(grep -Eo '\\?' "$final" | wc -l | tr -d ' ')"

  result="fail"
  if [ "$tracker_exists" = "yes" ] &&
     [ "$brief_exists" = "yes" ] &&
     [ "$arch_exists" = "yes" ] &&
     [ "$source_research_absent" = "yes" ] &&
     [ "$scenarios_absent" = "yes" ] &&
     [ "$harness_absent" = "yes" ] &&
     [ "$asks_questions" = "yes" ] &&
     [ "$no_research" = "yes" ] &&
     [ "$no_harness" = "yes" ] &&
     [ "$read_now_present" = "yes" ] &&
     [ "$question_count" -ge 1 ] &&
     [ "$question_count" -le 5 ]; then
    result="pass"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$result" \
    "$auth_failed" \
    "$tracker_exists" \
    "$brief_exists" \
    "$arch_exists" \
    "$source_research_absent" \
    "$scenarios_absent" \
    "$harness_absent" \
    "$asks_questions" \
    "$question_count" \
    "$no_research" \
    "$no_harness" \
    "$mentions_tracker_first"
}

write_markdown_summary() {
  local summary_tsv="$1"
  local summary_md="$2"

  {
    echo '# kafka-architecture-investigation sbx Smoke Summary'
    echo
    echo "Run set: \`$RUN_SET\`"
    echo
    echo '| Model | Effort | Exit | Result | Seconds | Tokens | Auth Failed | Tracker | Brief | Architecture | No Research Doc | No Scenarios | No Harness | Asked Questions | Question Count | No Research Commands | No Harness Commands | Mentions Tracker |'
    echo '|---|---:|---:|---|---:|---:|---|---|---|---|---|---|---|---|---:|---|---|---|'
    awk -F '\t' 'NR > 1 {
      printf "| `%s` | `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18
    }' "$summary_tsv"
  } > "$summary_md"
}

mkdir -p "$RESULTS_DIR"

run_id="tracker-smoke-${MODEL}-${EFFORT}"
host_run_dir="$RESULTS_DIR/$run_id"
sandbox_run_dir="$SANDBOX_WORKSPACE/evaluation-runs/$RUN_SET/$run_id"
target_dir="$SANDBOX_WORKSPACE/kafka-architecture-investigation-smoke-$RUN_SET"
summary_tsv="$RESULTS_DIR/summary.tsv"
summary_md="$RESULTS_DIR/summary.md"

mkdir -p "$host_run_dir"
printf 'model\teffort\texit_code\tresult\telapsed_seconds\ttokens_used\tauth_failed\ttracker_exists\tbrief_exists\tarchitecture_exists\tsource_research_absent\tscenarios_absent\tharness_absent\tasks_questions\tquestion_count\tno_research\tno_harness\tmentions_tracker_first\ttarget_dir\tlog_dir\n' > "$summary_tsv"

refresh_skill
check_ready

prompt="$(make_prompt "$target_dir")"
printf '%s\n' "$prompt" > "$host_run_dir/prompt.txt"

sbx exec "$SBX_NAME" -- env SANDBOX_RUN_DIR="$sandbox_run_dir" TARGET_DIR="$target_dir" RUN_PROMPT="$prompt" sh -lc '
  rm -rf "$SANDBOX_RUN_DIR" "$TARGET_DIR"
  mkdir -p "$SANDBOX_RUN_DIR" "$TARGET_DIR"
  printf "%s\n" "$RUN_PROMPT" > "$SANDBOX_RUN_DIR/prompt.txt"
' >/dev/null

log "Running tracker-smoke model=$MODEL effort=$EFFORT target=$target_dir"
started_at="$(date +%s)"
set +e
sbx exec "$SBX_NAME" -- env MODEL="$MODEL" EFFORT="$EFFORT" SANDBOX_WORKSPACE="$SANDBOX_WORKSPACE" SANDBOX_RUN_DIR="$sandbox_run_dir" sh -lc '
  codex exec \
    --skip-git-repo-check \
    --cd "$SANDBOX_WORKSPACE" \
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

scores="$(score_run "$host_run_dir")"
IFS=$'\t' read -r result auth_failed tracker_exists brief_exists architecture_exists source_research_absent scenarios_absent harness_absent asks_questions question_count no_research no_harness mentions_tracker_first <<< "$scores"

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$MODEL" \
  "$EFFORT" \
  "$exit_code" \
  "$result" \
  "$elapsed_seconds" \
  "$tokens_used" \
  "$auth_failed" \
  "$tracker_exists" \
  "$brief_exists" \
  "$architecture_exists" \
  "$source_research_absent" \
  "$scenarios_absent" \
  "$harness_absent" \
  "$asks_questions" \
  "$question_count" \
  "$no_research" \
  "$no_harness" \
  "$mentions_tracker_first" \
  "$target_dir" \
  "$host_run_dir" >> "$summary_tsv"

write_markdown_summary "$summary_tsv" "$summary_md"

log "Result: $result exit=$exit_code seconds=$elapsed_seconds tokens=$tokens_used"
log "Summary: $summary_md"

if [ "$result" != "pass" ]; then
  exit 1
fi
