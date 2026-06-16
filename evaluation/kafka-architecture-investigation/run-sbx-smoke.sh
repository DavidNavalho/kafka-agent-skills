#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run-sbx-smoke.sh [options]

Run a low-cost sbx evaluation for kafka-architecture-investigation.

Options:
  --sbx NAME           sbx sandbox name. Defaults to agent-skills-eval.
  --model NAME         Codex model. Defaults to gpt-5.4-mini.
  --effort NAME        Reasoning effort. Defaults to low.
  --results-dir DIR    Host results directory.
  --sync-host-codex-auth
                      Copy host ChatGPT Codex auth into sbx before running.
  -h, --help           Show this help.

Environment:
  SBX_NAME             agent-skills-eval
  MODEL                gpt-5.4-mini
  EFFORT               low
  SANDBOX_WORKSPACE    /home/agent/workspace
  SKILL_SOURCE         Repo-local skills/kafka-architecture-investigation
  SKILL_DEST           /home/agent/.codex/skills/kafka-architecture-investigation
  SYNC_HOST_CODEX_AUTH 1 to copy host ChatGPT Codex auth into sbx first.
  PROMPT_TEXT          Optional prompt. Use {{TARGET_DIR}} for insertion.
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
    *"Logged in using ChatGPT"*)
      ;;
    *"API key"*)
      printf '%s\n' "$status" >&2
      echo "Codex in sbx is authenticated with an API key. Re-run with --sync-host-codex-auth or use codex login --device-auth inside sbx." >&2
      exit 1
      ;;
    *)
      printf '%s\n' "$status" >&2
      echo "Codex in sbx is not authenticated with ChatGPT." >&2
      exit 1
      ;;
  esac
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
  local asks_questions no_research no_harness question_count mentions_tracker_first read_now_present auth_failed known_facts_captured s01_cursor_complete result

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
  mentions_tracker_first="$(bool grep -Eiq 'tracker|TRACKER.md' "$final")"
  read_now_present="$(bool grep -q 'Read now:' "$tracker")"
  s01_cursor_complete="$(bool sh -c '
    grep -Eiq "Read now:.*references/intake\\.md" "$1" &&
    grep -Eiq "Read now:.*INVESTIGATION_BRIEF\\.md" "$1" &&
    grep -Eiq "Read now:.*REFERENCE_ARCHITECTURE\\.md" "$1"
  ' sh "$tracker")"
  auth_failed="$(bool grep -Eq '401 Unauthorized|Incorrect API key' "$trace")"
  question_count="$(awk '
    /^[[:space:]]*[0-9]+[.)][[:space:]]+/ { numbered++ }
    { qmarks += gsub(/\?/, "?") }
    END {
      if (qmarks > 0) {
        print qmarks
      } else {
        print numbered + 0
      }
    }
  ' "$final")"
  known_facts_captured="$(bool sh -c '
    grep -Eiq "kraft" "$1" "$2" &&
    grep -Eiq "fewer brokers|smaller|reduced|less brokers|target.*fewer|fewer.*broker" "$1" "$2"
  ' sh "$brief" "$arch")"

  result="fail"
  if [ "$tracker_exists" = "yes" ] &&
     [ "$brief_exists" = "yes" ] &&
     [ "$arch_exists" = "yes" ] &&
     [ "$known_facts_captured" = "yes" ] &&
     [ "$source_research_absent" = "yes" ] &&
     [ "$scenarios_absent" = "yes" ] &&
     [ "$harness_absent" = "yes" ] &&
     [ "$asks_questions" = "yes" ] &&
     [ "$no_research" = "yes" ] &&
     [ "$no_harness" = "yes" ] &&
     [ "$read_now_present" = "yes" ] &&
     [ "$s01_cursor_complete" = "yes" ] &&
     [ "$question_count" -ge 1 ] &&
     [ "$question_count" -le 5 ]; then
    result="pass"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$result" \
    "$auth_failed" \
    "$tracker_exists" \
    "$brief_exists" \
    "$arch_exists" \
    "$known_facts_captured" \
    "$read_now_present" \
    "$s01_cursor_complete" \
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
    echo '| Model | Effort | Exit | Result | Seconds | Tokens | Auth Failed | Tracker | Brief | Architecture | Known Facts Captured | Read Now Present | S01 Cursor Complete | No Research Doc | No Scenarios | No Harness | Asked Questions | Question Count | No Research Commands | No Harness Commands | Mentions Tracker |'
    echo '|---|---:|---:|---|---:|---:|---|---|---|---|---|---|---|---|---|---|---|---:|---|---|---|'
    awk -F '\t' 'NR > 1 {
      printf "| `%s` | `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21
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
printf 'model\teffort\texit_code\tresult\telapsed_seconds\ttokens_used\tauth_failed\ttracker_exists\tbrief_exists\tarchitecture_exists\tknown_facts_captured\tread_now_present\ts01_cursor_complete\tsource_research_absent\tscenarios_absent\tharness_absent\tasks_questions\tquestion_count\tno_research\tno_harness\tmentions_tracker_first\ttarget_dir\tlog_dir\n' > "$summary_tsv"

if is_truthy "$SYNC_HOST_CODEX_AUTH"; then
  sync_host_codex_auth
fi

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
IFS=$'\t' read -r result auth_failed tracker_exists brief_exists architecture_exists known_facts_captured read_now_present s01_cursor_complete source_research_absent scenarios_absent harness_absent asks_questions question_count no_research no_harness mentions_tracker_first <<< "$scores"

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
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
  "$known_facts_captured" \
  "$read_now_present" \
  "$s01_cursor_complete" \
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
