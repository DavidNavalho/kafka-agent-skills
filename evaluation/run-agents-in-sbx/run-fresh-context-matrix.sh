#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL_DIR="$REPO_ROOT/skills/run-agents-in-sbx"
RUNNER="$SKILL_DIR/scripts/run-codex-in-sbx.sh"
SCORER="$SCRIPT_DIR/score-fresh-context.py"
REQUEST_FIXTURE="$SCRIPT_DIR/fixtures/fresh-context-request.md"
SCHEMA_FIXTURE="$SCRIPT_DIR/fixtures/fresh-context-plan-schema.json"
ACTIVE_SKILL_DIR="$SKILL_DIR"
ACTIVE_RUNNER="$RUNNER"
ACTIVE_SCORER="$SCORER"
ACTIVE_REQUEST_FIXTURE="$REQUEST_FIXTURE"
ACTIVE_SCHEMA_FIXTURE="$SCHEMA_FIXTURE"

usage() {
  cat <<'USAGE'
Usage: run-fresh-context-matrix.sh [options]

Run fresh Codex agents against a natural operating request using only the
published run-agents-in-sbx skill as decision guidance. Each agent creates a
machine-scored plan; it does not launch another coding agent or sandbox.

Real execution requires ALLOW_REAL_CODEX_AUTH=1 because each matrix cell uses
the one-shot runner's copied file-backed ChatGPT subscription authentication.
Cells run serially to preserve one auth lineage.

Options:
  --models LIST            Space-separated models. Default:
                           "gpt-5.6-sol gpt-5.5 gpt-5.3-codex-spark".
  --efforts LIST           Space-separated reasoning efforts. Default: "low".
  --repetitions COUNT      Runs per model/effort cell. Default: 3.
  --timeout SECONDS        Per-agent guest timeout. Default: 600.
  --auth-lock-wait SECONDS Wait per cell for the serialized auth lineage.
                           Default: 3600.
  --guest-codex-version V  Exact guest @openai/codex version. Default:
                           0.145.0-alpha.13.
  --auth-file PATH         Host file-backed ChatGPT auth cache.
  --results-dir PATH       New results directory. Default: a timestamped
                           evaluation/run-agents-in-sbx/evaluation-runs path.
  --plan                   Print the credential, model, and lifecycle plan;
                           create no files, sandbox, or credential copy.
  -h, --help               Show this help.
USAGE
}

fail() {
  printf '[run-agents-in-sbx fresh-context] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[run-agents-in-sbx fresh-context] %s\n' "$*" >&2
}

if [[ -n "${CODEX_HOME:-}" ]]; then
  auth_file="${CODEX_HOME%/}/auth.json"
else
  auth_file="$HOME/.codex/auth.json"
fi
models="gpt-5.6-sol gpt-5.5 gpt-5.3-codex-spark"
efforts="low"
repetitions=3
timeout_seconds=600
auth_lock_wait_seconds=3600
guest_codex_version="0.145.0-alpha.13"
results_dir=""
plan_only=0

while (($#)); do
  case "$1" in
    --models)
      models="${2:?Missing value for --models}"
      shift 2
      ;;
    --efforts)
      efforts="${2:?Missing value for --efforts}"
      shift 2
      ;;
    --repetitions)
      repetitions="${2:?Missing value for --repetitions}"
      shift 2
      ;;
    --timeout)
      timeout_seconds="${2:?Missing value for --timeout}"
      shift 2
      ;;
    --auth-lock-wait)
      auth_lock_wait_seconds="${2:?Missing value for --auth-lock-wait}"
      shift 2
      ;;
    --guest-codex-version)
      guest_codex_version="${2:?Missing value for --guest-codex-version}"
      shift 2
      ;;
    --auth-file)
      auth_file="${2:?Missing value for --auth-file}"
      shift 2
      ;;
    --results-dir)
      results_dir="${2:?Missing value for --results-dir}"
      shift 2
      ;;
    --plan)
      plan_only=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ "$repetitions" =~ ^[1-9][0-9]*$ ]] || fail "--repetitions must be a positive integer"
[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || fail "--timeout must be a positive integer"
[[ "$auth_lock_wait_seconds" =~ ^(0|[1-9][0-9]*)$ ]] || \
  fail "--auth-lock-wait must be a canonical nonnegative integer"
if ((${#auth_lock_wait_seconds} > 5)) || ((10#$auth_lock_wait_seconds > 86400)); then
  fail "--auth-lock-wait must not exceed 86400 seconds"
fi
[[ "$guest_codex_version" =~ ^[0-9A-Za-z.+-]+$ ]] || \
  fail "--guest-codex-version contains unsupported characters"

models_array=()
model_count=0
for model in $models; do
  [[ "$model" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || fail "unsupported model name shape: $model"
  if ((model_count > 0)); then
    for existing in "${models_array[@]}"; do
      [[ "$existing" != "$model" ]] || fail "model is duplicated: $model"
    done
  fi
  models_array+=("$model")
  model_count=$((model_count + 1))
done
((model_count > 0)) || fail "at least one model is required"

efforts_array=()
effort_count=0
for effort in $efforts; do
  case "$effort" in
    minimal|low|medium|high|xhigh|max|ultra) ;;
    *) fail "unsupported reasoning effort: $effort" ;;
  esac
  if ((effort_count > 0)); then
    for existing in "${efforts_array[@]}"; do
      [[ "$existing" != "$effort" ]] || fail "reasoning effort is duplicated: $effort"
    done
  fi
  efforts_array+=("$effort")
  effort_count=$((effort_count + 1))
done
((effort_count > 0)) || fail "at least one reasoning effort is required"

run_set="$(date -u +%Y%m%dT%H%M%SZ)-$$"
if [[ -z "$results_dir" ]]; then
  results_dir="$SCRIPT_DIR/evaluation-runs/fresh-context-$run_set"
fi
results_dir="$(python3 - "$results_dir" <<'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"
auth_file="$(python3 - "$auth_file" <<'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"

for sensitive_candidate in \
  "${CODEX_HOME:-$HOME/.codex}" \
  "$HOME/.codex" \
  "$HOME/.ssh" \
  "$HOME/.gnupg" \
  "$HOME/.aws" \
  "$HOME/.azure" \
  "$HOME/.kube" \
  "$HOME/.docker" \
  "$HOME/.config/gh" \
  "$HOME/.config/gcloud"; do
  if [[ -d "$sensitive_candidate" ]]; then
    sensitive_physical="$(cd "$sensitive_candidate" && pwd -P)"
    case "$results_dir" in
      "$sensitive_physical"|"$sensitive_physical"/*)
        fail "results directory overlaps a host credential directory: $sensitive_physical"
        ;;
    esac
    case "$sensitive_physical" in
      "$results_dir"|"$results_dir"/*)
        fail "results directory would contain a host credential directory: $sensitive_physical"
        ;;
    esac
  fi
done

print_plan() {
  printf 'evaluation=fresh-context-model-matrix\n'
  printf 'credential_source=%s\n' "$auth_file"
  printf 'credential_destination=/home/agent/.codex/auth.json\n'
  printf 'workspace_trust=generated-private-fixtures-only\n'
  printf 'skill_source=%s\n' "$SKILL_DIR"
  printf 'candidate_snapshot=immutable copy with recorded SHA-256 before first cell\n'
  printf 'scenario=%s\n' "$REQUEST_FIXTURE"
  printf 'agent_task=plan-only; no nested sbx or coding-agent launch\n'
  printf 'serialization=one-run-at-a-time-for-this-auth-cache\n'
  printf 'sandbox_lifetime=one-task; remove-on-success; preserve-on-auth-ambiguity\n'
  printf 'artifacts=%s\n' "$results_dir"
  printf 'models=%s\n' "${models_array[*]}"
  printf 'efforts=%s\n' "${efforts_array[*]}"
  printf 'repetitions=%s\n' "$repetitions"
  printf 'timeout_seconds=%s\n' "$timeout_seconds"
  printf 'auth_lock_wait_seconds=%s\n' "$auth_lock_wait_seconds"
  printf 'guest_codex_version=%s\n' "$guest_codex_version"
}

if ((plan_only == 1)); then
  print_plan
  exit 0
fi

[[ "${ALLOW_REAL_CODEX_AUTH:-0}" == "1" ]] || fail "set ALLOW_REAL_CODEX_AUTH=1 after reviewing --plan"
[[ -x "$RUNNER" ]] || fail "runner is missing or not executable: $RUNNER"
[[ -x "$SCORER" || -f "$SCORER" ]] || fail "scorer is missing: $SCORER"
[[ -f "$REQUEST_FIXTURE" && ! -L "$REQUEST_FIXTURE" ]] || fail "request fixture is missing or unsafe"
[[ -f "$SCHEMA_FIXTURE" && ! -L "$SCHEMA_FIXTURE" ]] || fail "schema fixture is missing or unsafe"
[[ -f "$auth_file" && ! -L "$auth_file" ]] || fail "auth cache must be a regular non-symlink file: $auth_file"
[[ ! -e "$results_dir" && ! -L "$results_dir" ]] || fail "results directory already exists: $results_dir"

mkdir -p "$results_dir/workspaces" "$results_dir/artifacts" "$results_dir/prompts" \
  "$results_dir/candidate"
ACTIVE_SKILL_DIR="$results_dir/candidate/run-agents-in-sbx"
ACTIVE_RUNNER="$ACTIVE_SKILL_DIR/scripts/run-codex-in-sbx.sh"
ACTIVE_SCORER="$results_dir/candidate/score-fresh-context.py"
ACTIVE_REQUEST_FIXTURE="$results_dir/candidate/fresh-context-request.md"
ACTIVE_SCHEMA_FIXTURE="$results_dir/candidate/fresh-context-plan-schema.json"
cp -R "$SKILL_DIR" "$ACTIVE_SKILL_DIR"
cp "$SCORER" "$ACTIVE_SCORER"
cp "$REQUEST_FIXTURE" "$ACTIVE_REQUEST_FIXTURE"
cp "$SCHEMA_FIXTURE" "$ACTIVE_SCHEMA_FIXTURE"
if [[ -n "$(find "$results_dir/candidate" -type l -print -quit)" ]]; then
  fail "candidate snapshot contains a symbolic link"
fi
candidate_digest="$(python3 - "$results_dir/candidate" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
digest = hashlib.sha256()
for path in sorted(candidate for candidate in root.rglob("*") if candidate.is_file()):
    relative = path.relative_to(root).as_posix().encode("utf-8")
    digest.update(len(relative).to_bytes(8, "big"))
    digest.update(relative)
    content = path.read_bytes()
    digest.update(len(content).to_bytes(8, "big"))
    digest.update(content)
print(digest.hexdigest())
PY
)"
[[ "$candidate_digest" =~ ^[0-9a-f]{64}$ ]] || fail "could not digest candidate snapshot"
chmod -R a-w "$results_dir/candidate"
print_plan | tee "$results_dir/plan.txt"
sbx_version="$(sbx version 2>&1)" || fail "sbx version failed: $sbx_version"
codex_version="$(codex --version 2>&1)" || fail "codex --version failed: $codex_version"
printf 'sbx=%s\ncodex=%s\nguest_codex=%s\ncandidate_sha256=%s\n' \
  "$sbx_version" "$codex_version" "$guest_codex_version" "$candidate_digest" \
  > "$results_dir/versions.txt"
printf 'model\teffort\trepetition\trunner_exit\tseconds\tresult\tauth_state\tsandbox_disposition\tscore\n' \
  > "$results_dir/summary.tsv"

render_summary() {
  SUMMARY_TSV="$results_dir/summary.tsv" \
  SUMMARY_MD="$results_dir/summary.md" \
  SUMMARY_RUN_SET="$run_set" \
  SUMMARY_VERSIONS="$results_dir/versions.txt" \
  python3 - <<'PY'
import os
from pathlib import Path

rows = [line.split("\t") for line in Path(os.environ["SUMMARY_TSV"]).read_text(encoding="utf-8").splitlines()]
header, data = rows[0], rows[1:]
lines = [
    "# run-agents-in-sbx Fresh-Context Model Matrix",
    "",
    f"- Run set: `{os.environ['SUMMARY_RUN_SET']}`",
]
for line in Path(os.environ["SUMMARY_VERSIONS"]).read_text(encoding="utf-8").splitlines():
    key, _, value = line.partition("=")
    lines.append(f"- {key}: `{value}`")
lines.extend(["", "| " + " | ".join(header) + " |", "| " + " | ".join("---" for _ in header) + " |"])
for row in data:
    lines.append("| " + " | ".join(row) + " |")
lines.extend([
    "",
    "A passing row means a fresh agent used only the published skill to choose safe workspace, credential, trust, concurrency, timeout, evidence, cleanup, and changed-auth recovery policies; the runner also verified unchanged guest auth and sandbox removal.",
    "",
])
Path(os.environ["SUMMARY_MD"]).write_text("\n".join(lines), encoding="utf-8")
PY
}

failures=0
for model in "${models_array[@]}"; do
  for effort in "${efforts_array[@]}"; do
    for ((repetition = 1; repetition <= repetitions; repetition++)); do
      model_slug="$(printf '%s' "$model" | tr -cd 'A-Za-z0-9._+-')"
      case_id="${model_slug}-${effort}-${repetition}"
      workspace="$results_dir/workspaces/$case_id"
      artifacts="$results_dir/artifacts/$case_id"
      prompt="$results_dir/prompts/$case_id.md"

      mkdir -p "$workspace"
      cp "$ACTIVE_REQUEST_FIXTURE" "$workspace/request.md"
      cp "$ACTIVE_SCHEMA_FIXTURE" "$workspace/plan-schema.json"
      git init -q -b "eval-$repetition" "$workspace"
      git -C "$workspace" config user.name "sbx fresh-context eval"
      git -C "$workspace" config user.email "sbx-fresh-context@example.invalid"
      git -C "$workspace" add request.md plan-schema.json
      git -C "$workspace" commit -q -m "Initialize fresh-context evaluation"

      PROMPT_PATH="$prompt" SKILL_PATH="$ACTIVE_SKILL_DIR/SKILL.md" python3 - <<'PY'
import os
from pathlib import Path

prompt = f"""Use `$run-agents-in-sbx` at `{os.environ['SKILL_PATH']}` to prepare the operating plan requested in `request.md`.

This is a planning task only. Do not invoke `sbx`, run another coding agent, inspect authentication files, use the network, install dependencies, or modify `request.md` or `plan-schema.json`.

Write the plan to `sandbox-agent-plan.json` and make it conform exactly to `plan-schema.json`. The schema deliberately contains both safe and unsafe enum choices; select values by applying the skill, not by assuming an enum's position is correct. Keep each rationale specific to the request.

Validate that the plan is parseable JSON using the Python standard library and save nonempty validation evidence under the exact run-specific evidence directory from the controller contract. In the required handoff, include `sandbox-agent-plan.json` in `changedFiles` and cite that evidence. Do not create or modify anything else.
"""
Path(os.environ["PROMPT_PATH"]).write_text(prompt, encoding="utf-8")
PY

      log "running model=$model effort=$effort repetition=$repetition"
      if "$ACTIVE_RUNNER" \
        --workspace "$workspace" \
        --prompt-file "$prompt" \
        --read-only-mount "$ACTIVE_SKILL_DIR" \
        --artifacts "$artifacts" \
        --auth-file "$auth_file" \
        --posture workspace-write \
        --auth-lock-wait "$auth_lock_wait_seconds" \
        --guest-codex-version "$guest_codex_version" \
        --timeout "$timeout_seconds" \
        --model "$model" \
        --reasoning-effort "$effort"; then
        runner_exit=0
      else
        runner_exit=$?
      fi

      if [[ "$runner_exit" -ne 0 ]]; then
        failure_result=runner-failed
        failure_auth=unknown
        failure_disposition=inspect-result
        duration=unknown
        if [[ -f "$artifacts/process-result.txt" ]]; then
          duration="$(sed -n 's/^duration_seconds=//p' "$artifacts/process-result.txt")"
          [[ "$duration" =~ ^[0-9]+$ ]] || duration=unknown
        fi
        if [[ -f "$artifacts/result.json" ]]; then
          failure_fields="$(python3 - "$artifacts/result.json" <<'PY'
import json
import sys

doc = json.load(open(sys.argv[1], encoding="utf-8"))
print("\t".join(str(doc.get(key, "unknown")) for key in (
    "outcome", "guestAuthCacheState", "sandboxDisposition"
)))
PY
)"
          IFS=$'\t' read -r failure_result failure_auth failure_disposition <<< "$failure_fields"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$model" "$effort" "$repetition" "$runner_exit" "$duration" "$failure_result" \
          "$failure_auth" "$failure_disposition" "not-scored" >> "$results_dir/summary.tsv"
        render_summary
        failures=$((failures + 1))
        if [[ "$failure_auth" != "unchanged" || "$failure_disposition" != "removed" ]]; then
          log "runner state requires inspection; stopping matrix before another auth use"
          exit "$runner_exit"
        fi
        continue
      fi

      duration="$(sed -n 's/^duration_seconds=//p' "$artifacts/process-result.txt")"
      [[ "$duration" =~ ^[0-9]+$ ]] || duration=unknown
      if python3 "$ACTIVE_SCORER" \
        --workspace "$workspace" \
        --artifacts "$artifacts" \
        --auth-file "$auth_file" \
        --request-fixture "$ACTIVE_REQUEST_FIXTURE" \
        --schema-fixture "$ACTIVE_SCHEMA_FIXTURE" \
        --model "$model" \
        --effort "$effort" \
        --auth-lock-wait "$auth_lock_wait_seconds" \
        --guest-codex-version "$guest_codex_version" > "$artifacts/fresh-context-score.json"; then
        printf '%s\t%s\t%s\t0\t%s\tpassed\tunchanged\tremoved\tpassed\n' \
          "$model" "$effort" "$repetition" "$duration" >> "$results_dir/summary.tsv"
      else
        printf '%s\t%s\t%s\t0\t%s\tfailed-score\tunchanged\tremoved\tfailed\n' \
          "$model" "$effort" "$repetition" "$duration" >> "$results_dir/summary.tsv"
        failures=$((failures + 1))
        log "score failed for model=$model effort=$effort repetition=$repetition"
        if grep -Eq 'credential material|auth file|sandbox is still listed|sbx listing unavailable' \
          "$artifacts/fresh-context-score.json"; then
          render_summary
          log "score failure affects credential or cleanup confidence; stopping matrix"
          exit 1
        fi
      fi
      render_summary
    done
  done
done

if ((failures > 0)); then
  log "matrix completed with failures=$failures; summary=$results_dir/summary.md"
  exit 1
fi
log "all fresh-context cells passed; summary=$results_dir/summary.md"
