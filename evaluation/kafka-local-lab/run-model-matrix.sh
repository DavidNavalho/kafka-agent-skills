#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run-model-matrix.sh [options]

Run kafka-local-lab skill evaluations inside an sbx sandbox.

The runner executes serially because the default Kafka lab uses fixed host ports.

Options:
  --runner NAME        Agent runner: codex or claude. Defaults to codex.
  --sbx NAME           sbx sandbox name. Defaults to agent-skills-eval.
  --scenarios "LIST"  Space-separated scenarios: default, confluent, schema-registry, connect, akhq, full, custom.
  --models "LIST"     Space-separated model names.
  --efforts "LIST"    Space-separated reasoning efforts.
  --results-dir DIR   Host directory for transcripts and summaries.
  --keep-labs         Do not remove generated target directories after cleanup.
  -h, --help          Show this help.

Environment defaults:
  SBX_NAME            agent-skills-eval
  RUNNER              codex
  CODEX_MODELS        "gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex-spark gpt-5.2"
  CLAUDE_MODELS       "haiku sonnet"
  CODEX_EFFORTS       "low medium"
  CLAUDE_EFFORTS      "low medium"
  SCENARIOS           Defaults to "default", or "custom" when PROMPT_TEXT is set.
  CLAUDE_PERMISSION_MODE  bypassPermissions
  SANDBOX_WORKSPACE   /home/agent/workspace
  SKILL_SOURCE        Repo-local skills/kafka-local-lab
  CODEX_SKILL_DEST    /home/agent/.codex/skills/kafka-local-lab
  CLAUDE_SKILL_DEST   /home/agent/.claude/skills/kafka-local-lab
  PROMPT_TEXT         Optional prompt template. Use {{TARGET_DIR}} for the generated target path.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SBX_NAME="${SBX_NAME:-agent-skills-eval}"
RUNNER="${RUNNER:-codex}"
CODEX_MODELS="${CODEX_MODELS:-gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex-spark gpt-5.2}"
CLAUDE_MODELS="${CLAUDE_MODELS:-haiku sonnet}"
CODEX_EFFORTS="${CODEX_EFFORTS:-low medium}"
CLAUDE_EFFORTS="${CLAUDE_EFFORTS:-low medium}"
CLAUDE_PERMISSION_MODE="${CLAUDE_PERMISSION_MODE:-bypassPermissions}"
MODELS="${MODELS:-}"
EFFORTS="${EFFORTS:-}"
SCENARIOS="${SCENARIOS:-}"
SANDBOX_WORKSPACE="${SANDBOX_WORKSPACE:-/home/agent/workspace}"
SKILL_SOURCE="${SKILL_SOURCE:-$REPO_ROOT/skills/kafka-local-lab}"
CODEX_SKILL_DEST="${CODEX_SKILL_DEST:-/home/agent/.codex/skills/kafka-local-lab}"
CLAUDE_SKILL_DEST="${CLAUDE_SKILL_DEST:-/home/agent/.claude/skills/kafka-local-lab}"
SKILL_DEST="${SKILL_DEST:-}"
RUN_SET="${RUN_SET:-$(date +%Y%m%d-%H%M%S)}"
RESULTS_DIR="${RESULTS_DIR:-$SCRIPT_DIR/evaluation-runs/$RUN_SET}"
SANDBOX_RUN_ROOT="$SANDBOX_WORKSPACE/evaluation-runs/$RUN_SET"
KEEP_LABS=0
PROMPT_TEXT="${PROMPT_TEXT:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --runner)
      RUNNER="${2:?Missing value for --runner}"
      shift 2
      ;;
    --sbx)
      SBX_NAME="${2:?Missing value for --sbx}"
      shift 2
      ;;
    --scenarios)
      SCENARIOS="${2:?Missing value for --scenarios}"
      shift 2
      ;;
    --models)
      MODELS="${2:?Missing value for --models}"
      shift 2
      ;;
    --efforts)
      EFFORTS="${2:?Missing value for --efforts}"
      shift 2
      ;;
    --results-dir)
      RESULTS_DIR="${2:?Missing value for --results-dir}"
      shift 2
      ;;
    --keep-labs)
      KEEP_LABS=1
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

case "$RUNNER" in
  codex)
    MODELS="${MODELS:-$CODEX_MODELS}"
    EFFORTS="${EFFORTS:-$CODEX_EFFORTS}"
    SKILL_DEST="${SKILL_DEST:-$CODEX_SKILL_DEST}"
    ;;
  claude)
    MODELS="${MODELS:-$CLAUDE_MODELS}"
    EFFORTS="${EFFORTS:-$CLAUDE_EFFORTS}"
    SKILL_DEST="${SKILL_DEST:-$CLAUDE_SKILL_DEST}"
    ;;
  *)
    echo "Unknown runner: $RUNNER" >&2
    usage >&2
    exit 2
    ;;
esac

if [ -z "$SCENARIOS" ]; then
  if [ -n "$PROMPT_TEXT" ]; then
    SCENARIOS="custom"
  else
    SCENARIOS="default"
  fi
fi

log() {
  printf '[matrix] %s\n' "$*"
}

slug() {
  printf '%s' "$1" | tr ' /:' '---' | tr -cd '[:alnum:]._-'
}

bool() {
  if "$@"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

refresh_skill() {
  log "Refreshing skill in sandbox: $SKILL_DEST"
  sbx exec "$SBX_NAME" -- env SKILL_SOURCE="$SKILL_SOURCE" SKILL_DEST="$SKILL_DEST" sh -lc '
    if [ ! -f "$SKILL_SOURCE/SKILL.md" ]; then
      echo "Skill source is not visible inside the sandbox: $SKILL_SOURCE" >&2
      echo "Create the sbx sandbox with the agent-skills repository mounted, or set SKILL_SOURCE to a visible path." >&2
      exit 1
    fi
    rm -rf "$SKILL_DEST"
    mkdir -p "$SKILL_DEST"
    for item in SKILL.md assets references scripts agents; do
      if [ -e "$SKILL_SOURCE/$item" ]; then
        cp -R "$SKILL_SOURCE/$item" "$SKILL_DEST/"
      fi
    done
    chmod +x "$SKILL_DEST"/scripts/*.sh
  ' >/dev/null
}

make_prompt() {
  local scenario="$1"
  local target_dir="$2"
  local prompt

  if [ -n "$PROMPT_TEXT" ]; then
    prompt="${PROMPT_TEXT//\{\{TARGET_DIR\}\}/$target_dir}"
    printf '%s\n' "$prompt"
    return 0
  fi

  case "$RUNNER:$scenario" in
    claude:default)
      prompt="/kafka-local-lab create a quick local Kafka lab in $target_dir. This is a non-interactive regression run: use the defaults and do not ask setup questions."
      ;;
    codex:default)
      prompt="Use kafka-local-lab to create a quick local Kafka lab in $target_dir. This is a non-interactive regression run: use the defaults and do not ask setup questions."
      ;;
    claude:confluent)
      prompt="/kafka-local-lab create a Confluent Kafka lab in $target_dir. Use no extras. This is a non-interactive regression run: do not ask setup questions."
      ;;
    codex:confluent)
      prompt="Use kafka-local-lab to create a Confluent Kafka lab in $target_dir. Use no extras. This is a non-interactive regression run: do not ask setup questions."
      ;;
    claude:schema-registry)
      prompt="/kafka-local-lab create a Confluent Kafka lab with Schema Registry in $target_dir. Run the full validation. This is a non-interactive regression run: do not ask setup questions."
      ;;
    codex:schema-registry)
      prompt="Use kafka-local-lab to create a Confluent Kafka lab with Schema Registry in $target_dir. Run the full validation. This is a non-interactive regression run: do not ask setup questions."
      ;;
    claude:connect)
      prompt="/kafka-local-lab create a Confluent Kafka lab with Kafka Connect in $target_dir. Run the full validation. This is a non-interactive regression run: do not ask setup questions."
      ;;
    codex:connect)
      prompt="Use kafka-local-lab to create a Confluent Kafka lab with Kafka Connect in $target_dir. Run the full validation. This is a non-interactive regression run: do not ask setup questions."
      ;;
    claude:akhq)
      prompt="/kafka-local-lab create a Confluent Kafka lab with AKHQ UI in $target_dir. Run the full validation. This is a non-interactive regression run: do not ask setup questions."
      ;;
    codex:akhq)
      prompt="Use kafka-local-lab to create a Confluent Kafka lab with AKHQ UI in $target_dir. Run the full validation. This is a non-interactive regression run: do not ask setup questions."
      ;;
    claude:full)
      prompt="/kafka-local-lab create a Confluent Kafka lab with Schema Registry, Kafka Connect, and AKHQ UI in $target_dir. Run the full validation. This is a non-interactive regression run: do not ask setup questions."
      ;;
    codex:full)
      prompt="Use kafka-local-lab to create a Confluent Kafka lab with Schema Registry, Kafka Connect, and AKHQ UI in $target_dir. Run the full validation. This is a non-interactive regression run: do not ask setup questions."
      ;;
    *:custom)
      echo "Scenario 'custom' requires PROMPT_TEXT with {{TARGET_DIR}}." >&2
      return 2
      ;;
    *)
      echo "Unknown scenario: $scenario" >&2
      echo "Supported scenarios: default, confluent, schema-registry, connect, akhq, full, custom" >&2
      return 2
      ;;
  esac

  printf '%s\n' "$prompt"
}

scenario_expectations() {
  local scenario="$1"
  local prompt_file="${2:-}"

  case "$scenario" in
    default)
      printf 'apache\tno\tno\tno\n'
      ;;
    confluent)
      printf 'confluent\tno\tno\tno\n'
      ;;
    schema-registry)
      printf 'confluent\tyes\tno\tno\n'
      ;;
    connect)
      printf 'confluent\tno\tyes\tno\n'
      ;;
    akhq)
      printf 'confluent\tno\tno\tyes\n'
      ;;
    full)
      printf 'confluent\tyes\tyes\tyes\n'
      ;;
    custom)
      if [ -z "$prompt_file" ] || [ ! -f "$prompt_file" ]; then
        printf 'any\tany\tany\tany\n'
        return 0
      fi

      local expected_stack expected_schema expected_connect expected_akhq
      expected_stack="any"
      expected_schema="any"
      expected_connect="any"
      expected_akhq="any"

      if grep -Eiq 'confluent' "$prompt_file"; then
        expected_stack="confluent"
      fi
      if grep -Eiq 'apache kafka|defaults|default lab|quick local kafka' "$prompt_file"; then
        expected_stack="apache"
      fi
      if grep -Eiq 'schema registry|schema-registry|--with-schema-registry' "$prompt_file"; then
        expected_schema="yes"
      fi
      if grep -Eiq 'kafka connect|--with-connect' "$prompt_file"; then
        expected_connect="yes"
      fi
      if grep -Eiq 'akhq|ui tooling|user interface|--ui' "$prompt_file"; then
        expected_akhq="yes"
      fi

      printf '%s\t%s\t%s\t%s\n' "$expected_stack" "$expected_schema" "$expected_connect" "$expected_akhq"
      ;;
    *)
      echo "Unknown scenario: $scenario" >&2
      return 2
      ;;
  esac
}

expect_matches() {
  local expected="$1"
  local actual="$2"

  if [ "$expected" = "any" ]; then
    return 0
  fi
  [ "$expected" = "$actual" ]
}

evaluate_result() {
  local exit_code="$1"
  local used_create="$2"
  local used_preflight="$3"
  local used_smoke="$4"
  local smoke_passed="$5"
  local final_has_host="$6"
  local final_has_docker="$7"
  local final_has_cleanup="$8"
  local expected_stack="$9"
  local expected_schema="${10}"
  local expected_connect="${11}"
  local expected_akhq="${12}"
  local generated_stack="${13}"
  local generated_schema="${14}"
  local generated_connect="${15}"
  local generated_akhq="${16}"
  local schema_passed="${17}"
  local connect_passed="${18}"
  local akhq_passed="${19}"

  [ "$exit_code" -eq 0 ] || return 1
  [ "$used_create" = "yes" ] || return 1
  [ "$used_preflight" = "yes" ] || return 1
  [ "$used_smoke" = "yes" ] || return 1
  [ "$smoke_passed" = "yes" ] || return 1
  [ "$final_has_host" = "yes" ] || return 1
  [ "$final_has_docker" = "yes" ] || return 1
  [ "$final_has_cleanup" = "yes" ] || return 1

  expect_matches "$expected_stack" "$generated_stack" || return 1
  expect_matches "$expected_schema" "$generated_schema" || return 1
  expect_matches "$expected_connect" "$generated_connect" || return 1
  expect_matches "$expected_akhq" "$generated_akhq" || return 1

  if [ "$expected_schema" = "yes" ] && [ "$schema_passed" != "yes" ]; then
    return 1
  fi
  if [ "$expected_connect" = "yes" ] && [ "$connect_passed" != "yes" ]; then
    return 1
  fi
  if [ "$expected_akhq" = "yes" ] && [ "$akhq_passed" != "yes" ]; then
    return 1
  fi

  return 0
}

cleanup_lab() {
  local target_dir="$1"

  sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" KEEP_LABS="$KEEP_LABS" sh -lc '
    if [ -f "$TARGET_DIR/docker-compose.yml" ]; then
      cd "$TARGET_DIR" && docker compose down -v >/dev/null 2>&1 || true
    fi
    project_name="$(basename "$TARGET_DIR" | tr -cd "[:alnum:]_-")"
    container_ids="$(
      {
        docker ps -aq --filter "label=com.docker.compose.project.working_dir=$TARGET_DIR" 2>/dev/null || true
        docker ps -aq --filter "name=$project_name" 2>/dev/null || true
      } | sort -u
    )"
    if [ -n "$container_ids" ]; then
      docker rm -f -v $container_ids >/dev/null 2>&1 || true
    fi
    if [ "$KEEP_LABS" != "1" ]; then
      rm -rf "$TARGET_DIR"
    fi
  ' >/dev/null || true
}

score_run() {
  local run_dir="$1"
  local trace="$run_dir/trace.log"
  local final="$run_dir/final.md"

  local used_create used_preflight used_smoke smoke_passed read_script_body final_has_host final_has_docker final_has_cleanup

  used_create="$(bool grep -q 'create-lab.sh' "$trace")"
  used_preflight="$(bool grep -q 'preflight.sh' "$trace")"
  used_smoke="$(bool grep -q 'smoke-test.sh' "$trace")"
  smoke_passed="$(bool grep -q 'Kafka smoke test passed' "$trace")"
  read_script_body="$(bool grep -q '#!/usr/bin/env bash' "$trace")"
  final_has_host="$(bool grep -q 'localhost:29092' "$final")"
  final_has_docker="$(bool grep -q 'kafka-1:19092' "$final")"
  final_has_cleanup="$(bool grep -Eq 'docker compose( .*)? down' "$final")"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$used_create" \
    "$used_preflight" \
    "$used_smoke" \
    "$smoke_passed" \
    "$read_script_body" \
    "$final_has_host" \
    "$final_has_docker" \
    "$final_has_cleanup"
}

env_stack() {
  local env_file="$1"

  if grep -q '^STACK=apache$' "$env_file"; then
    printf 'apache'
  elif grep -q '^STACK=confluent$' "$env_file"; then
    printf 'confluent'
  else
    printf 'missing'
  fi
}

env_yes_no() {
  local env_file="$1"
  local name="$2"

  if grep -q "^${name}=1$" "$env_file"; then
    printf 'yes'
  elif grep -q "^${name}=0$" "$env_file"; then
    printf 'no'
  else
    printf 'missing'
  fi
}

env_ui() {
  local env_file="$1"

  if grep -q '^UI=akhq$' "$env_file"; then
    printf 'yes'
  elif grep -q '^UI=none$' "$env_file"; then
    printf 'no'
  else
    printf 'missing'
  fi
}

extract_tokens_used() {
  local trace="$1"

  if [ "$RUNNER" = "claude" ]; then
    if command -v node >/dev/null 2>&1; then
      node - "$trace" <<'NODE'
const fs = require("fs");
const tracePath = process.argv[2];
let tokens = null;

for (const line of fs.readFileSync(tracePath, "utf8").split(/\n/)) {
  if (!line.trim().startsWith("{")) continue;
  try {
    const event = JSON.parse(line);
    if (event.type === "result" && event.usage) {
      tokens =
        (event.usage.input_tokens || 0) +
        (event.usage.output_tokens || 0) +
        (event.usage.cache_creation_input_tokens || 0) +
        (event.usage.cache_read_input_tokens || 0);
    }
  } catch (_) {
  }
}

process.stdout.write(tokens === null ? "unknown\n" : `${tokens}\n`);
NODE
    else
      printf 'unknown\n'
    fi
    return 0
  fi

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

extract_cost_usd() {
  local trace="$1"

  if [ "$RUNNER" != "claude" ]; then
    printf 'unknown\n'
    return 0
  fi

  if command -v node >/dev/null 2>&1; then
    node - "$trace" <<'NODE'
const fs = require("fs");
const tracePath = process.argv[2];
let cost = null;

for (const line of fs.readFileSync(tracePath, "utf8").split(/\n/)) {
  if (!line.trim().startsWith("{")) continue;
  try {
    const event = JSON.parse(line);
    if (event.type === "result" && typeof event.total_cost_usd === "number") {
      cost = event.total_cost_usd;
    }
  } catch (_) {
  }
}

process.stdout.write(cost === null ? "unknown\n" : `${cost.toFixed(6)}\n`);
NODE
  else
    printf 'unknown\n'
  fi
}

run_agent() {
  local model="$1"
  local effort="$2"
  local sandbox_run_dir="$3"

  case "$RUNNER" in
    codex)
      sbx exec "$SBX_NAME" -- env \
        MODEL="$model" \
        EFFORT="$effort" \
        SANDBOX_WORKSPACE="$SANDBOX_WORKSPACE" \
        SANDBOX_RUN_DIR="$sandbox_run_dir" \
        sh -lc '
          codex exec \
            --skip-git-repo-check \
            --cd "$SANDBOX_WORKSPACE" \
            -m "$MODEL" \
            -c "model_reasoning_effort=\"$EFFORT\"" \
            -o "$SANDBOX_RUN_DIR/final.md" \
            < "$SANDBOX_RUN_DIR/prompt.txt"
        '
      ;;
    claude)
      sbx exec "$SBX_NAME" -- env \
        MODEL="$model" \
        EFFORT="$effort" \
        CLAUDE_PERMISSION_MODE="$CLAUDE_PERMISSION_MODE" \
        SANDBOX_WORKSPACE="$SANDBOX_WORKSPACE" \
        SANDBOX_RUN_DIR="$sandbox_run_dir" \
        bash -lc '
          set -o pipefail
          claude -p \
            --model "$MODEL" \
            --effort "$EFFORT" \
            --permission-mode "$CLAUDE_PERMISSION_MODE" \
            --output-format stream-json \
            --verbose \
            --add-dir "$SANDBOX_WORKSPACE" \
            < "$SANDBOX_RUN_DIR/prompt.txt" | tee "$SANDBOX_RUN_DIR/stream.jsonl"

          node - "$SANDBOX_RUN_DIR/stream.jsonl" <<'"'"'NODE'"'"' | tee "$SANDBOX_RUN_DIR/final.md"
const fs = require("fs");
const streamPath = process.argv[2];
let result = "";

for (const line of fs.readFileSync(streamPath, "utf8").split(/\n/)) {
  if (!line.trim().startsWith("{")) continue;
  try {
    const event = JSON.parse(line);
    if (event.type === "result" && typeof event.result === "string") {
      result = event.result;
    }
  } catch (_) {
  }
}

process.stdout.write(result);
NODE
        '
      ;;
  esac
}

write_markdown_summary() {
  local summary_tsv="$1"
  local summary_md="$2"

  {
    echo '# kafka-local-lab Model Matrix Summary'
    echo
    echo "Run set: \`$RUN_SET\`"
    echo "Runner: \`$RUNNER\`"
    echo "Scenarios: \`$SCENARIOS\`"
    echo
    echo '| Scenario | Model | Effort | Exit | Result | Seconds | Tokens | Cost USD | Expected Stack | Expected Schema | Expected Connect | Expected UI | Generated Stack | Schema Env | Connect Env | UI Env | Smoke Passed | Schema Passed | Connect Passed | AKHQ Passed | Create | Preflight | Smoke Script | Read Script Body | Host Bootstrap | Docker Bootstrap | Cleanup |'
    echo '|---|---|---:|---:|---|---:|---:|---:|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'
    awk -F '\t' 'NR > 1 {
      printf "| `%s` | `%s` | `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $20, $21, $22, $23, $17, $18, $19, $24, $25, $26, $27
    }' "$summary_tsv"
  } > "$summary_md"
}

mkdir -p "$RESULTS_DIR"

summary_tsv="$RESULTS_DIR/summary.tsv"
summary_md="$RESULTS_DIR/summary.md"

printf 'scenario\tmodel\teffort\texit_code\tresult\telapsed_seconds\ttokens_used\tcost_usd\texpected_stack\texpected_schema\texpected_connect\texpected_akhq\tgenerated_stack\tgenerated_schema\tgenerated_connect\tgenerated_akhq\tused_create\tused_preflight\tused_smoke\tsmoke_passed\tschema_passed\tconnect_passed\takhq_passed\tread_script_body\tfinal_has_host_bootstrap\tfinal_has_docker_bootstrap\tfinal_has_cleanup\ttarget_dir\tlog_dir\n' > "$summary_tsv"

log "Results directory: $RESULTS_DIR"
log "Runner: $RUNNER"
log "Scenarios: $SCENARIOS"
log "Models: $MODELS"
log "Efforts: $EFFORTS"
log "Sandbox run root: $SANDBOX_RUN_ROOT"
refresh_skill

for scenario in $SCENARIOS; do
  for model in $MODELS; do
    for effort in $EFFORTS; do
    scenario_slug="$(slug "$scenario")"
    model_slug="$(slug "$model")"
    effort_slug="$(slug "$effort")"
    run_id="${scenario_slug}-${model_slug}-${effort_slug}"
    host_run_dir="$RESULTS_DIR/$run_id"
    sandbox_run_dir="$SANDBOX_RUN_ROOT/$run_id"
    target_dir="/tmp/kafka-local-lab-matrix-$RUN_SET-$run_id"

    mkdir -p "$host_run_dir"
    prompt="$(make_prompt "$scenario" "$target_dir")"
    printf '%s\n' "$prompt" > "$host_run_dir/prompt.txt"
    expectations="$(scenario_expectations "$scenario" "$host_run_dir/prompt.txt")"
    IFS=$'\t' read -r expected_stack expected_schema expected_connect expected_akhq <<< "$expectations"
    sbx exec "$SBX_NAME" -- env SANDBOX_RUN_DIR="$sandbox_run_dir" RUN_PROMPT="$prompt" sh -lc '
      rm -rf "$SANDBOX_RUN_DIR"
      mkdir -p "$SANDBOX_RUN_DIR"
      printf "%s\n" "$RUN_PROMPT" > "$SANDBOX_RUN_DIR/prompt.txt"
    ' >/dev/null

    log "Running scenario=$scenario model=$model effort=$effort target=$target_dir"

    started_at="$(date +%s)"
    set +e
    run_agent "$model" "$effort" "$sandbox_run_dir" > "$host_run_dir/transcript.log" 2> "$host_run_dir/stderr.log"
    exit_code=$?
    set -e
    finished_at="$(date +%s)"
    elapsed_seconds=$((finished_at - started_at))

    sbx exec "$SBX_NAME" -- env SANDBOX_RUN_DIR="$sandbox_run_dir" sh -lc '
      test -f "$SANDBOX_RUN_DIR/final.md" && cat "$SANDBOX_RUN_DIR/final.md"
    ' > "$host_run_dir/final.md" 2>/dev/null || : > "$host_run_dir/final.md"
    cat "$host_run_dir/transcript.log" "$host_run_dir/stderr.log" > "$host_run_dir/trace.log"
    tokens_used="$(extract_tokens_used "$host_run_dir/trace.log")"
    cost_usd="$(extract_cost_usd "$host_run_dir/trace.log")"

    sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" sh -lc '
      if [ -d "$TARGET_DIR" ]; then
        find "$TARGET_DIR" -maxdepth 2 -type f -print | sort
      fi
    ' > "$host_run_dir/artifacts.txt" 2>/dev/null || true
    sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" sh -lc '
      test -f "$TARGET_DIR/.env" && cat "$TARGET_DIR/.env"
    ' > "$host_run_dir/generated.env" 2>/dev/null || : > "$host_run_dir/generated.env"
    sbx exec "$SBX_NAME" -- env TARGET_DIR="$target_dir" sh -lc '
      test -f "$TARGET_DIR/docker-compose.yml" && cat "$TARGET_DIR/docker-compose.yml"
    ' > "$host_run_dir/generated-docker-compose.yml" 2>/dev/null || : > "$host_run_dir/generated-docker-compose.yml"

    scores="$(score_run "$host_run_dir")"
    IFS=$'\t' read -r used_create used_preflight used_smoke smoke_passed read_script_body final_has_host final_has_docker final_has_cleanup <<< "$scores"
    schema_passed="$(bool grep -q 'Schema Registry smoke test passed' "$host_run_dir/trace.log")"
    connect_passed="$(bool grep -q 'Kafka Connect FileStream smoke test passed' "$host_run_dir/trace.log")"
    akhq_passed="$(bool grep -q 'AKHQ smoke test passed' "$host_run_dir/trace.log")"
    generated_stack="$(env_stack "$host_run_dir/generated.env")"
    generated_schema="$(env_yes_no "$host_run_dir/generated.env" WITH_SCHEMA_REGISTRY)"
    generated_connect="$(env_yes_no "$host_run_dir/generated.env" WITH_CONNECT)"
    generated_akhq="$(env_ui "$host_run_dir/generated.env")"

    result="fail"
    if evaluate_result \
      "$exit_code" \
      "$used_create" \
      "$used_preflight" \
      "$used_smoke" \
      "$smoke_passed" \
      "$final_has_host" \
      "$final_has_docker" \
      "$final_has_cleanup" \
      "$expected_stack" \
      "$expected_schema" \
      "$expected_connect" \
      "$expected_akhq" \
      "$generated_stack" \
      "$generated_schema" \
      "$generated_connect" \
      "$generated_akhq" \
      "$schema_passed" \
      "$connect_passed" \
      "$akhq_passed"; then
      result="pass"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$scenario" \
      "$model" \
      "$effort" \
      "$exit_code" \
      "$result" \
      "$elapsed_seconds" \
      "$tokens_used" \
      "$cost_usd" \
      "$expected_stack" \
      "$expected_schema" \
      "$expected_connect" \
      "$expected_akhq" \
      "$generated_stack" \
      "$generated_schema" \
      "$generated_connect" \
      "$generated_akhq" \
      "$used_create" \
      "$used_preflight" \
      "$used_smoke" \
      "$smoke_passed" \
      "$schema_passed" \
      "$connect_passed" \
      "$akhq_passed" \
      "$read_script_body" \
      "$final_has_host" \
      "$final_has_docker" \
      "$final_has_cleanup" \
      "$target_dir" \
      "$host_run_dir" >> "$summary_tsv"

    cleanup_lab "$target_dir"
    log "Finished scenario=$scenario model=$model effort=$effort result=$result exit=$exit_code"
    done
  done
done

write_markdown_summary "$summary_tsv" "$summary_md"

log "Summary: $summary_md"
