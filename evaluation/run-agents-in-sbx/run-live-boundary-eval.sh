#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL_DIR="$REPO_ROOT/skills/run-agents-in-sbx"
RUNNER="$SKILL_DIR/scripts/run-codex-in-sbx.sh"
SCORER="$SCRIPT_DIR/score-live-boundary.py"
PROBE_FIXTURE="$SCRIPT_DIR/fixtures/boundary-probe.sh"

usage() {
  cat <<'USAGE'
Usage: run-live-boundary-eval.sh [options]

Run an authenticated end-to-end boundary evaluation of run-agents-in-sbx.
The harness creates only generated, trusted git repositories and retains its
results under an ignored evaluation-runs directory.

Real execution requires ALLOW_REAL_CODEX_AUTH=1 because the runner copies the
host's file-backed ChatGPT auth cache into each short-lived sandbox.

Options:
  --postures LIST          Space-separated postures. Default:
                           "outer workspace-write".
  --repetitions COUNT      Runs per posture. Default: 1.
  --model MODEL            Codex model. Default: gpt-5.4-mini.
  --reasoning-effort VALUE Codex reasoning effort. Default: low.
  --timeout SECONDS        Per-agent guest timeout. Default: 600.
  --auth-file PATH         Host file-backed ChatGPT auth cache.
  --results-dir PATH       New results directory. Default: a timestamped
                           evaluation/run-agents-in-sbx/evaluation-runs path.
  --plan                   Print the credential and lifecycle plan; create
                           no files, sandbox, or credential copy.
  -h, --help               Show this help.
USAGE
}

fail() {
  printf '[run-agents-in-sbx live eval] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[run-agents-in-sbx live eval] %s\n' "$*" >&2
}

if [[ -n "${CODEX_HOME:-}" ]]; then
  auth_file="${CODEX_HOME%/}/auth.json"
else
  auth_file="$HOME/.codex/auth.json"
fi
postures="outer workspace-write"
repetitions=1
model="gpt-5.4-mini"
reasoning_effort="low"
timeout_seconds=600
results_dir=""
plan_only=0

while (($#)); do
  case "$1" in
    --postures)
      postures="${2:?Missing value for --postures}"
      shift 2
      ;;
    --repetitions)
      repetitions="${2:?Missing value for --repetitions}"
      shift 2
      ;;
    --model)
      model="${2:?Missing value for --model}"
      shift 2
      ;;
    --reasoning-effort)
      reasoning_effort="${2:?Missing value for --reasoning-effort}"
      shift 2
      ;;
    --timeout)
      timeout_seconds="${2:?Missing value for --timeout}"
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
[[ -n "$model" ]] || fail "--model must not be empty"
[[ -n "$reasoning_effort" ]] || fail "--reasoning-effort must not be empty"

validated_postures=()
validated_posture_count=0
for posture in $postures; do
  case "$posture" in
    outer|workspace-write) ;;
    *) fail "unsupported posture: $posture" ;;
  esac
  if (( validated_posture_count > 0 )); then
    for existing in "${validated_postures[@]}"; do
      [[ "$existing" != "$posture" ]] || fail "posture is duplicated: $posture"
    done
  fi
  validated_postures+=("$posture")
  validated_posture_count=$((validated_posture_count + 1))
done
(( validated_posture_count > 0 )) || fail "at least one posture is required"

run_set="$(date -u +%Y%m%dT%H%M%SZ)-$$"
if [[ -z "$results_dir" ]]; then
  results_dir="$SCRIPT_DIR/evaluation-runs/live-boundary-$run_set"
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
  printf 'evaluation=authenticated-live-boundary\n'
  printf 'credential_source=%s\n' "$auth_file"
  printf 'credential_destination=/home/agent/.codex/auth.json\n'
  printf 'workspace_trust=generated-private-fixtures-only\n'
  printf 'network_policy=record-effective-policy-before-model-execution\n'
  printf 'serialization=one-run-at-a-time-for-this-auth-cache\n'
  printf 'sandbox_lifetime=one-task; remove-on-success; stop-and-preserve-on-auth-ambiguity\n'
  printf 'artifacts=%s\n' "$results_dir"
  printf 'postures=%s\n' "${validated_postures[*]}"
  printf 'repetitions=%s\n' "$repetitions"
  printf 'model=%s\n' "$model"
  printf 'reasoning_effort=%s\n' "$reasoning_effort"
  printf 'timeout_seconds=%s\n' "$timeout_seconds"
}

if (( plan_only == 1 )); then
  print_plan
  exit 0
fi

[[ "${ALLOW_REAL_CODEX_AUTH:-0}" == "1" ]] || fail "set ALLOW_REAL_CODEX_AUTH=1 after reviewing --plan"
[[ -x "$RUNNER" ]] || fail "runner is missing or not executable: $RUNNER"
[[ -x "$SCORER" || -f "$SCORER" ]] || fail "scorer is missing: $SCORER"
[[ -f "$PROBE_FIXTURE" ]] || fail "boundary probe fixture is missing: $PROBE_FIXTURE"
[[ -f "$auth_file" && ! -L "$auth_file" ]] || fail "auth cache must be a regular non-symlink file: $auth_file"
[[ ! -e "$results_dir" && ! -L "$results_dir" ]] || fail "results directory already exists: $results_dir"

mkdir -p "$results_dir/workspaces" "$results_dir/artifacts" "$results_dir/prompts"
read_only_context="$results_dir/read-only-context"
unmounted_dir="$results_dir/unmounted-host-only"
mkdir -p "$read_only_context" "$unmounted_dir"
cp "$PROBE_FIXTURE" "$read_only_context/boundary-probe.sh"
chmod 755 "$read_only_context/boundary-probe.sh"
printf 'read-only-context=visible\n' > "$read_only_context/readable.txt"
sentinel="$unmounted_dir/sentinel.txt"
printf 'unmounted-sentinel=host-only\n' > "$sentinel"

print_plan | tee "$results_dir/plan.txt"
sbx_version="$(sbx version 2>&1)" || fail "sbx version failed: $sbx_version"
codex_version="$(codex --version 2>&1)" || fail "codex --version failed: $codex_version"
printf 'sbx=%s\ncodex=%s\n' "$sbx_version" "$codex_version" > "$results_dir/versions.txt"
printf 'posture\trepetition\trunner_exit\tresult\tauth_state\tsandbox_disposition\tartifacts\n' \
  > "$results_dir/summary.tsv"

render_summary() {
  SUMMARY_TSV="$results_dir/summary.tsv" \
  SUMMARY_MD="$results_dir/summary.md" \
  SUMMARY_RUN_SET="$run_set" \
  SUMMARY_MODEL="$model" \
  SUMMARY_EFFORT="$reasoning_effort" \
  SUMMARY_VERSIONS="$results_dir/versions.txt" \
  python3 - <<'PY'
import os
from pathlib import Path

tsv = Path(os.environ["SUMMARY_TSV"])
rows = [line.split("\t") for line in tsv.read_text(encoding="utf-8").splitlines()]
header, data = rows[0], rows[1:]
lines = [
    "# run-agents-in-sbx Live Boundary Evaluation",
    "",
    f"- Run set: `{os.environ['SUMMARY_RUN_SET']}`",
    f"- Model: `{os.environ['SUMMARY_MODEL']}`",
    f"- Reasoning effort: `{os.environ['SUMMARY_EFFORT']}`",
]
for line in Path(os.environ["SUMMARY_VERSIONS"]).read_text(encoding="utf-8").splitlines():
    key, _, value = line.partition("=")
    lines.append(f"- {key}: `{value}`")
lines.extend(["", "| " + " | ".join(header) + " |", "| " + " | ".join("---" for _ in header) + " |"])
for row in data:
    lines.append("| " + " | ".join(row) + " |")
lines.extend([
    "",
    "Each passing row verifies owned writes, read-only mount enforcement, hidden unmounted state, absent API-key environment variables, recorded network policy, valid host-visible handoff evidence, unchanged guest auth, no credential material in generated outputs, and confirmed sandbox removal.",
    "",
])
Path(os.environ["SUMMARY_MD"]).write_text("\n".join(lines), encoding="utf-8")
PY
}

for posture in "${validated_postures[@]}"; do
  for ((repetition = 1; repetition <= repetitions; repetition++)); do
    case_id="${posture}-${repetition}"
    workspace="$results_dir/workspaces/$case_id"
    artifacts="$results_dir/artifacts/$case_id"
    prompt="$results_dir/prompts/$case_id.md"
    mkdir -p "$workspace"
    git init -q -b "eval-$case_id" "$workspace"
    git -C "$workspace" config user.name "sbx boundary eval"
    git -C "$workspace" config user.email "sbx-boundary-eval@example.invalid"
    printf '# Generated sbx boundary evaluation workspace\n' > "$workspace/README.md"
    git -C "$workspace" add README.md
    git -C "$workspace" commit -q -m "Initialize boundary evaluation workspace"

    PROMPT_PATH="$prompt" \
    PROMPT_WORKSPACE="$workspace" \
    PROMPT_READ_ONLY="$read_only_context" \
    PROMPT_SENTINEL="$sentinel" \
    python3 - <<'PY'
import os
import shlex
from pathlib import Path

workspace = os.environ["PROMPT_WORKSPACE"]
read_only = os.environ["PROMPT_READ_ONLY"]
sentinel = os.environ["PROMPT_SENTINEL"]
probe_output = f"{workspace}/boundary-evidence.txt"
command = " ".join(shlex.quote(value) for value in [
    "bash",
    f"{read_only}/boundary-probe.sh",
    workspace,
    read_only,
    sentinel,
    probe_output,
])
prompt = f"""Run this deterministic sandbox-boundary evaluation from the owned workspace:

```bash
{command}
```

Do not use the network, install dependencies, inspect authentication files, print environment-wide state, or modify the read-only context. After the command passes:

1. Copy `boundary-evidence.txt` into the exact run-specific validation-evidence directory named by the controller contract as `boundary-probe.txt`.
2. Write the exact required handoff JSON at the run-specific path named by the controller contract.
3. Report `succeeded`, cite the copied `boundary-probe.txt`, and list `owned-write.txt` and `boundary-evidence.txt` as changed files.
4. Do not create or modify anything else.
"""
Path(os.environ["PROMPT_PATH"]).write_text(prompt, encoding="utf-8")
PY

    runner_args=(
      --workspace "$workspace"
      --prompt-file "$prompt"
      --read-only-mount "$read_only_context"
      --artifacts "$artifacts"
      --auth-file "$auth_file"
      --posture "$posture"
      --timeout "$timeout_seconds"
      --model "$model"
      --reasoning-effort "$reasoning_effort"
    )

    log "running case=$case_id"
    if "$RUNNER" "${runner_args[@]}"; then
      runner_exit=0
    else
      runner_exit=$?
    fi

    if [[ "$runner_exit" -ne 0 ]]; then
      failure_result=runner-failed
      failure_auth=unknown
      failure_disposition=inspect-result
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
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$posture" "$repetition" "$runner_exit" "$failure_result" \
        "$failure_auth" "$failure_disposition" "$artifacts" >> "$results_dir/summary.tsv"
      render_summary
      if [[ "$failure_result" == "ownership-busy" ]]; then
        log "serialized auth or workspace is currently owned; rerun after that owner finishes"
      fi
      log "runner failed for case=$case_id; preserve all generated state and follow result.json recovery"
      exit "$runner_exit"
    fi

    if python3 "$SCORER" \
      --workspace "$workspace" \
      --read-only-context "$read_only_context" \
      --sentinel "$sentinel" \
      --artifacts "$artifacts" \
      --auth-file "$auth_file" \
      --posture "$posture" > "$artifacts/live-boundary-score.json"; then
      printf '%s\t%s\t0\tpassed\tunchanged\tremoved\t%s\n' \
        "$posture" "$repetition" "$artifacts" >> "$results_dir/summary.tsv"
    else
      printf '%s\t%s\t0\tfailed-score\tunknown\tinspect-result\t%s\n' \
        "$posture" "$repetition" "$artifacts" >> "$results_dir/summary.tsv"
      render_summary
      log "boundary score failed for case=$case_id"
      exit 1
    fi
  done
done

render_summary
log "all live boundary cases passed; summary=$results_dir/summary.md"
