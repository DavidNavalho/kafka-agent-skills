#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CONTRACT_FILE="$SKILL_DIR/assets/runner-contract.md"
VALIDATOR="$SCRIPT_DIR/validate-handoff.py"
PREFLIGHT="$SCRIPT_DIR/preflight.sh"
AUTH_PROVISIONER="$SCRIPT_DIR/provision-codex-auth.sh"
BOUNDED_RUNNER="$SCRIPT_DIR/run-bounded-command.py"

usage() {
  cat <<'USAGE'
Usage: run-codex-in-sbx.sh --workspace PATH --prompt-file PATH|- [options]

Create one owned sbx sandbox, provision a copied ChatGPT-subscription Codex
session, run one bounded noninteractive task, validate its durable handoff,
collect evidence, and explicitly clean up or preserve for recovery.

Required:
  --workspace PATH         Owned writable workspace or worktree.
  --prompt-file PATH|-     Task prompt file, or '-' to read it from stdin.

Options:
  --name NAME              Unique sandbox name. Default: generated.
  --artifacts PATH         Host-only run artifact directory. Default: a unique
                           directory under the host temporary root.
  --auth-file PATH         Host file-backed ChatGPT auth cache.
  --read-only-mount PATH   Additional read-only context mount. Repeatable.
  --timeout SECONDS        Hard in-guest timeout. Default: 1800.
  --memory SIZE            sbx memory limit. Default: 8g.
  --cpus COUNT             sbx CPU count. Default: 4.
  --model MODEL            Explicit Codex model override.
  --reasoning-effort VALUE Explicit model_reasoning_effort override.
  --posture MODE           outer or workspace-write. Default: outer.
  --keep-sandbox           Stop and preserve the sandbox after collection.
  --allow-protected-branch Allow a writable run on main/master.
  --allow-non-git          Allow a workspace that is not a git worktree.
  --plan                   Record the plan, but create no sandbox and copy no
                           credential.
  -h, --help               Show this help.

Exit codes:
  0 success; 20 preflight; 21 create; 22 boundary/ownership/policy; 23 auth;
  24 timeout/cancel; 25 agent failure; 26 invalid handoff; 27 auth refresh
  recovery required; 28 cleanup failure; 29 partial/blocked agent outcome.
USAGE
}

log() {
  printf '[run-agents-in-sbx] %s\n' "$*" >&2
}

die() {
  log "ERROR: $*"
  exit 2
}

physical_dir() {
  local path="$1"
  [[ -d "$path" ]] || return 1
  (cd "$path" && pwd -P)
}

reject_sensitive_path() {
  local candidate="$1"
  local label="$2"
  local sensitive
  for sensitive in "${sensitive_host_dirs[@]}"; do
    case "$candidate" in
      "$sensitive"|"$sensitive"/*)
        die "$label overlaps a host credential directory: $sensitive"
        ;;
    esac
    case "$sensitive" in
      "$candidate"|"$candidate"/*)
        die "$label would expose a host credential directory: $sensitive"
        ;;
    esac
  done
}

default_temp_root() {
  if [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]]; then
    printf '%s\n' "${TMPDIR%/}"
  elif [[ -d /private/tmp ]]; then
    printf '%s\n' /private/tmp
  else
    printf '%s\n' /tmp
  fi
}

workspace=""
prompt_file=""
sandbox_name=""
artifacts_requested=""
timeout_seconds=1800
memory=8g
cpus=4
model=""
reasoning_effort=""
posture=outer
keep_sandbox=0
allow_protected_branch=0
allow_non_git=0
plan_only=0
read_only_mounts=()

if [[ -n "${CODEX_HOME:-}" ]]; then
  auth_file="${CODEX_HOME%/}/auth.json"
else
  auth_file="$HOME/.codex/auth.json"
fi

while (($#)); do
  case "$1" in
    --workspace)
      workspace="${2:?Missing value for --workspace}"
      shift 2
      ;;
    --prompt-file)
      prompt_file="${2:?Missing value for --prompt-file}"
      shift 2
      ;;
    --name)
      sandbox_name="${2:?Missing value for --name}"
      shift 2
      ;;
    --artifacts)
      artifacts_requested="${2:?Missing value for --artifacts}"
      shift 2
      ;;
    --auth-file)
      auth_file="${2:?Missing value for --auth-file}"
      shift 2
      ;;
    --read-only-mount)
      read_only_mounts+=("${2:?Missing value for --read-only-mount}")
      shift 2
      ;;
    --timeout)
      timeout_seconds="${2:?Missing value for --timeout}"
      shift 2
      ;;
    --memory)
      memory="${2:?Missing value for --memory}"
      shift 2
      ;;
    --cpus)
      cpus="${2:?Missing value for --cpus}"
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
    --posture)
      posture="${2:?Missing value for --posture}"
      shift 2
      ;;
    --keep-sandbox)
      keep_sandbox=1
      shift
      ;;
    --allow-protected-branch)
      allow_protected_branch=1
      shift
      ;;
    --allow-non-git)
      allow_non_git=1
      shift
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
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$workspace" ]] || die "--workspace is required"
[[ -n "$prompt_file" ]] || die "--prompt-file is required"
[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || die "--timeout must be a positive integer"
[[ "$cpus" =~ ^[1-9][0-9]*$ ]] || die "--cpus must be a positive integer"
case "$posture" in
  outer|workspace-write) ;;
  *) die "--posture must be outer or workspace-write" ;;
esac
[[ -f "$CONTRACT_FILE" ]] || die "runner contract is missing: $CONTRACT_FILE"
[[ -x "$VALIDATOR" || -f "$VALIDATOR" ]] || die "handoff validator is missing"
[[ -x "$BOUNDED_RUNNER" || -f "$BOUNDED_RUNNER" ]] || die "host bounded-command helper is missing"

workspace="$(physical_dir "$workspace")" || die "workspace is not a directory"
[[ "$workspace" != "/" ]] || die "workspace must not be the filesystem root"
[[ "$workspace" != "$HOME" ]] || die "workspace must not be the host home directory"
[[ "$workspace" != *:* ]] || die "workspace paths containing ':' are not supported by the mount syntax"

git_branch="not-a-worktree"
git_head="unknown"
if git -C "$workspace" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_branch="$(git -C "$workspace" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'detached')"
  git_head="$(git -C "$workspace" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  case "$git_branch" in
    main|master)
      (( allow_protected_branch == 1 )) || die "refusing a writable run on protected branch $git_branch"
      ;;
  esac
else
  (( allow_non_git == 1 )) || die "workspace is not a git worktree; pass --allow-non-git only for an intentional scratch task"
fi

[[ -f "$auth_file" ]] || die "auth file is missing: $auth_file"
[[ ! -L "$auth_file" ]] || die "auth file must not be a symlink"
auth_file="$(cd "$(dirname "$auth_file")" && pwd -P)/$(basename "$auth_file")"
case "$auth_file" in
  "$workspace"|"$workspace"/*)
    die "auth file must not live inside the writable workspace"
    ;;
esac

sensitive_host_dirs=()
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
    sensitive_physical="$(physical_dir "$sensitive_candidate")" || die "cannot resolve sensitive host directory"
    sensitive_host_dirs+=("$sensitive_physical")
  fi
done
reject_sensitive_path "$workspace" "workspace"

resolved_read_only_mounts=()
if ((${#read_only_mounts[@]})); then
  for mount in "${read_only_mounts[@]}"; do
    resolved="$(physical_dir "$mount")" || die "read-only mount is not a directory: $mount"
    [[ "$resolved" != *:* ]] || die "read-only mount paths containing ':' are not supported"
    reject_sensitive_path "$resolved" "read-only mount"
    case "$resolved" in
      "$workspace"|"$workspace"/*)
        die "read-only mount overlaps the writable workspace: $resolved"
        ;;
    esac
    case "$workspace" in
      "$resolved"/*)
        die "read-only mount is an ancestor of the writable workspace: $resolved"
        ;;
    esac
    case "$auth_file" in
      "$resolved"|"$resolved"/*)
        die "a read-only mount would expose the auth file or its ancestor: $resolved"
        ;;
    esac
    resolved_read_only_mounts+=("$resolved")
  done
fi

temp_root="$(default_temp_root)"
run_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_id="sbx-codex-${run_stamp}-$$"
slug="$(basename "$workspace" | tr '[:upper:]_' '[:lower:]-' | tr -cd 'a-z0-9.+-')"
slug="${slug:0:24}"
[[ -n "$slug" ]] || slug=workspace
if [[ -z "$sandbox_name" ]]; then
  sandbox_name="codex-${slug}-${run_stamp}-$$"
  sandbox_name="${sandbox_name:0:63}"
fi
[[ "$sandbox_name" =~ ^[A-Za-z0-9.+-]+$ ]] || die "sandbox name contains unsupported characters"

if [[ -n "$artifacts_requested" ]]; then
  artifacts_requested="$(python3 - "$artifacts_requested" <<'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"
  reject_sensitive_path "$artifacts_requested" "artifact path"
  artifacts_parent="$(dirname "$artifacts_requested")"
  artifacts_leaf="$(basename "$artifacts_requested")"
  mkdir -p "$artifacts_parent"
  artifacts_parent="$(physical_dir "$artifacts_parent")" || die "cannot resolve artifact parent"
  artifacts="$artifacts_parent/$artifacts_leaf"
else
  artifacts="$temp_root/run-agents-in-sbx-runs/$run_id"
fi
case "$artifacts" in
  "$workspace"|"$workspace"/*)
    die "host run artifacts must be outside the agent-writable workspace"
    ;;
esac
reject_sensitive_path "$artifacts" "artifact path"
[[ ! -e "$artifacts" && ! -L "$artifacts" ]] || die "artifact path already exists: $artifacts"
mkdir -p "$artifacts"

scratch="$(mktemp -d "$temp_root/run-agents-in-sbx.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
prompt_input="$scratch/task.md"
combined_prompt="$scratch/combined-prompt.md"
if [[ "$prompt_file" == "-" ]]; then
  cat > "$prompt_input"
else
  [[ -f "$prompt_file" ]] || die "prompt file is missing: $prompt_file"
  [[ ! -L "$prompt_file" ]] || die "prompt file must not be a symlink"
  prompt_file="$(cd "$(dirname "$prompt_file")" && pwd -P)/$(basename "$prompt_file")"
  [[ "$prompt_file" != "$auth_file" ]] || die "auth file cannot be used as the task prompt"
  reject_sensitive_path "$prompt_file" "prompt file"
  cp "$prompt_file" "$prompt_input"
fi
[[ -s "$prompt_input" ]] || die "prompt must not be empty"

handoff_relative="handoff/$run_id.json"
evidence_relative="agent-evidence/$run_id"
python3 - "$CONTRACT_FILE" "$prompt_input" "$combined_prompt" \
  "$run_id" "$workspace" "$handoff_relative" "$evidence_relative" <<'PY'
from pathlib import Path
import sys

contract = Path(sys.argv[1]).read_text(encoding="utf-8")
task = Path(sys.argv[2]).read_text(encoding="utf-8")
replacements = {
    "{{RUN_ID}}": sys.argv[4],
    "{{WORKSPACE}}": sys.argv[5],
    "{{HANDOFF_PATH}}": sys.argv[6],
    "{{EVIDENCE_DIR}}": sys.argv[7],
}
for key, value in replacements.items():
    contract = contract.replace(key, value)
Path(sys.argv[3]).write_text(contract + "\n\n" + task + "\n", encoding="utf-8")
PY

create_args=(create --name "$sandbox_name" --memory "$memory" --cpus "$cpus" codex "$workspace")
if ((${#resolved_read_only_mounts[@]})); then
  for mount in "${resolved_read_only_mounts[@]}"; do
    create_args+=("$mount:ro")
  done
fi

guest_home=/home/agent
guest_codex_home="$guest_home/.codex"
guest_run_dir="$guest_home/.codex-run/$run_id"
guest_final="$guest_run_dir/final.md"

{
  printf 'run_id=%s\n' "$run_id"
  printf 'sandbox=%s\n' "$sandbox_name"
  printf 'workspace=%s\n' "$workspace"
  printf 'git_branch=%s\n' "$git_branch"
  printf 'git_head=%s\n' "$git_head"
  printf 'artifacts=%s\n' "$artifacts"
  printf 'auth_source=%s\n' "$auth_file"
  printf 'auth_destination=%s\n' "$guest_codex_home/auth.json"
  printf 'posture=%s\n' "$posture"
  printf 'timeout_seconds=%s\n' "$timeout_seconds"
  printf 'memory=%s\n' "$memory"
  printf 'cpus=%s\n' "$cpus"
  printf 'model=%s\n' "${model:-configured-default}"
  printf 'reasoning_effort=%s\n' "${reasoning_effort:-configured-default}"
  printf 'handoff=%s\n' "$handoff_relative"
  printf 'sbx_create='
  printf '%q ' sbx "${create_args[@]}"
  printf '\n'
} | tee "$artifacts/plan.txt"

if (( plan_only == 1 )); then
  log "plan only; no sandbox or credential copy created"
  exit 0
fi

sandbox_created=0
sandbox_finalized=0
sandbox_stopped=0
preserve_sandbox=$keep_sandbox
cleanup_disposition=not-created
outcome=internal-error
agent_exit=""
handoff_valid=0
handoff_status=""
auth_cache_changed=0
auth_cache_state=not-checked
auth_recovery_required=0
auth_provisioned=0
host_deadline_reached=0
result_written=0
lock_dirs=()
lock_error=""

lock_key() {
  printf '%s' "$1" | cksum | awk '{print $1}'
}

acquire_lock() {
  local kind="$1"
  local key="$2"
  local lock_root="$temp_root/run-agents-in-sbx-locks"
  local lock_dir="$lock_root/${kind}-$(lock_key "$key").lock"
  local owner=""
  mkdir -p "$lock_root"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    if [[ -f "$lock_dir/pid" ]]; then
      owner="$(sed -n '1p' "$lock_dir/pid" 2>/dev/null || true)"
    fi
    if [[ "$owner" =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
      lock_error="$kind is already owned by live runner pid=$owner"
      return 1
    fi
    rm -f "$lock_dir/pid" 2>/dev/null || true
    if ! rmdir "$lock_dir" 2>/dev/null; then
      lock_error="stale $kind lock needs inspection: $lock_dir"
      return 1
    fi
    if ! mkdir "$lock_dir"; then
      lock_error="could not acquire $kind lock"
      return 1
    fi
  fi
  printf '%s\n' "$$" > "$lock_dir/pid"
  lock_dirs+=("$lock_dir")
}

release_locks() {
  local lock_dir
  if ((${#lock_dirs[@]})); then
    for lock_dir in "${lock_dirs[@]}"; do
      rm -f "$lock_dir/pid" 2>/dev/null || true
      rmdir "$lock_dir" 2>/dev/null || true
    done
  fi
}

sandbox_present() {
  sbx ls --json 2>/dev/null | python3 -c '
import json, sys
name = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(2)
raise SystemExit(0 if any(s.get("name") == name for s in data.get("sandboxes", [])) else 1)
' "$sandbox_name"
}

record_sandbox() {
  sbx ls --json | python3 -c '
import json, sys
name = sys.argv[1]
workspace = sys.argv[2]
data = json.load(sys.stdin)
matches = [s for s in data.get("sandboxes", []) if s.get("name") == name]
if len(matches) != 1:
    raise SystemExit(f"expected one sandbox named {name}, found {len(matches)}")
sandbox = matches[0]
actual_agent = sandbox.get("agent")
if actual_agent != "codex":
    raise SystemExit(f"sandbox {name} has unexpected agent {actual_agent!r}")
workspaces = sandbox.get("workspaces")
if not isinstance(workspaces, list) or workspace not in workspaces:
    raise SystemExit(f"sandbox {name} does not expose the exact owned workspace")
json.dump(sandbox, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")
' "$sandbox_name" "$workspace" > "$artifacts/sandbox.json"
}

host_file_stamp() {
  if stat -f '%m:%z' "$auth_file" 2>/dev/null; then
    return
  fi
  stat -c '%Y:%s' "$auth_file"
}

write_result() {
  local runner_exit="$1"
  RESULT_PATH="$artifacts/result.json" \
  RESULT_RUN_ID="$run_id" \
  RESULT_OUTCOME="$outcome" \
  RESULT_RUNNER_EXIT="$runner_exit" \
  RESULT_WORKSPACE="$workspace" \
  RESULT_SANDBOX="$sandbox_name" \
  RESULT_ARTIFACTS="$artifacts" \
  RESULT_POSTURE="$posture" \
  RESULT_AGENT_EXIT="$agent_exit" \
  RESULT_HANDOFF="$handoff_relative" \
  RESULT_HANDOFF_VALID="$handoff_valid" \
  RESULT_HANDOFF_STATUS="$handoff_status" \
  RESULT_AUTH_CHANGED="$auth_cache_changed" \
  RESULT_AUTH_STATE="$auth_cache_state" \
  RESULT_DISPOSITION="$cleanup_disposition" \
  RESULT_GUEST_AUTH="$guest_codex_home/auth.json" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

def boolean(name: str) -> bool:
    return os.environ[name] == "1"

agent_exit = os.environ["RESULT_AGENT_EXIT"]
doc = {
    "schemaVersion": "1.0",
    "runID": os.environ["RESULT_RUN_ID"],
    "outcome": os.environ["RESULT_OUTCOME"],
    "runnerExitCode": int(os.environ["RESULT_RUNNER_EXIT"]),
    "workspace": os.environ["RESULT_WORKSPACE"],
    "sandbox": os.environ["RESULT_SANDBOX"],
    "artifacts": os.environ["RESULT_ARTIFACTS"],
    "posture": os.environ["RESULT_POSTURE"],
    "agentExitCode": int(agent_exit) if agent_exit else None,
    "handoffPath": os.environ["RESULT_HANDOFF"],
    "handoffValid": boolean("RESULT_HANDOFF_VALID"),
    "handoffStatus": os.environ["RESULT_HANDOFF_STATUS"] or None,
    "guestAuthCacheChanged": boolean("RESULT_AUTH_CHANGED"),
    "guestAuthCacheState": os.environ["RESULT_AUTH_STATE"],
    "sandboxDisposition": os.environ["RESULT_DISPOSITION"],
    "recovery": [],
}
if doc["sandboxDisposition"] == "stopped-preserved":
    doc["recovery"].append(f"sbx run --name {doc['sandbox']}")
elif doc["sandboxDisposition"] in {"cleanup-failed", "ownership-unknown", "preserve-stop-failed"}:
    doc["recovery"].append(
        f"inspect sandbox ownership with sbx ls --json for {doc['sandbox']}"
    )
if doc["guestAuthCacheState"] in {"changed", "unknown"}:
    doc["recovery"].append(
        "reconcile the preserved guest auth cache at " + os.environ["RESULT_GUEST_AUTH"]
    )
Path(os.environ["RESULT_PATH"]).write_text(
    json.dumps(doc, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY
  result_written=1
}

finalize_sandbox() {
  if (( sandbox_created == 0 || sandbox_finalized == 1 )); then
    return 0
  fi

  if (( preserve_sandbox == 1 )); then
    if (( sandbox_stopped == 1 )); then
      printf 'action=already-stopped-and-preserved\nrecovery=sbx run --name %s\n' \
        "$sandbox_name" > "$artifacts/cleanup.txt"
      cleanup_disposition=stopped-preserved
      sandbox_finalized=1
      return 0
    fi
    if {
      printf 'action=stop-and-preserve\n'
      sbx stop "$sandbox_name"
      printf 'recovery=sbx run --name %s\n' "$sandbox_name"
    } > "$artifacts/cleanup.txt" 2>&1; then
      cleanup_disposition=stopped-preserved
      sandbox_finalized=1
      return 0
    fi
    printf 'verification=stop-failed; inspect exact sandbox ownership\n' >> "$artifacts/cleanup.txt"
    cleanup_disposition=preserve-stop-failed
    sandbox_finalized=1
    return 1
  fi

  if sbx rm --force "$sandbox_name" > "$artifacts/cleanup.txt" 2>&1; then
    local presence
    if sandbox_present; then
      presence=0
    else
      presence=$?
    fi
    case "$presence" in
      0)
        printf 'verification=sandbox-still-listed\n' >> "$artifacts/cleanup.txt"
        cleanup_disposition=cleanup-failed
        sandbox_finalized=1
        return 1
        ;;
      1)
        printf 'verification=absent\n' >> "$artifacts/cleanup.txt"
        cleanup_disposition=removed
        sandbox_finalized=1
        return 0
        ;;
      *)
        printf 'verification=listing-unavailable\n' >> "$artifacts/cleanup.txt"
        cleanup_disposition=cleanup-failed
        sandbox_finalized=1
        return 1
        ;;
    esac
  fi

  cleanup_disposition=cleanup-failed
  sandbox_finalized=1
  return 1
}

finish() {
  local requested_exit="$1"
  if ! finalize_sandbox; then
    outcome=cleanup-failed
    requested_exit=28
  fi
  write_result "$requested_exit"
  log "outcome=$outcome artifacts=$artifacts sandbox=$cleanup_disposition"
  exit "$requested_exit"
}

on_signal() {
  outcome=cancelled
  preserve_sandbox=1
  if (( auth_provisioned == 1 )); then
    auth_cache_state=unknown
    auth_recovery_required=1
  fi
  if (( sandbox_created == 1 )); then
    if sbx stop "$sandbox_name" >/dev/null 2>&1; then
      sandbox_stopped=1
    fi
  fi
  exit 130
}

on_exit() {
  local status=$?
  set +e
  if (( result_written == 0 && auth_provisioned == 1 )) && \
    [[ "$auth_cache_state" == "not-checked" ]]; then
    auth_cache_state=unknown
    auth_recovery_required=1
  fi
  if (( sandbox_created == 1 && sandbox_finalized == 0 )); then
    preserve_sandbox=1
    finalize_sandbox
  fi
  if (( result_written == 0 )) && [[ -d "$artifacts" ]]; then
    write_result "$status"
  fi
  release_locks
  rm -rf "$scratch"
}

trap on_signal INT TERM HUP
trap on_exit EXIT

if ! "$PREFLIGHT" --workspace "$workspace" --auth-file "$auth_file" \
  > "$artifacts/preflight.txt" 2>&1; then
  outcome=preflight-failed
  finish 20
fi

if ! acquire_lock auth "$auth_file"; then
  outcome=ownership-busy
  printf '%s\n' "$lock_error" > "$artifacts/lock-error.txt"
  finish 22
fi
if ! acquire_lock workspace "$workspace"; then
  outcome=ownership-busy
  printf '%s\n' "$lock_error" > "$artifacts/lock-error.txt"
  finish 22
fi

if sandbox_present; then
  presence=0
else
  presence=$?
fi
case "$presence" in
  0)
    outcome=sandbox-create-failed
    printf 'sandbox name already exists; refusing adoption\n' > "$artifacts/create.stderr.txt"
    finish 21
    ;;
  1) ;;
  *)
    outcome=boundary-unavailable
    printf 'could not establish whether the sandbox name already exists\n' > "$artifacts/create.stderr.txt"
    finish 22
    ;;
esac

log "creating owned sandbox=$sandbox_name workspace=$workspace"
if sbx "${create_args[@]}" > "$artifacts/create.stdout.txt" 2> "$artifacts/create.stderr.txt"; then
  sandbox_created=1
else
  outcome=sandbox-create-failed
  if sandbox_present; then
    sandbox_created=1
    preserve_sandbox=1
    printf 'post-failure=owned name is listed; stop and preserve for inspection\n' \
      >> "$artifacts/create.stderr.txt"
  else
    presence=$?
    if [[ "$presence" -ne 1 ]]; then
      cleanup_disposition=ownership-unknown
      printf 'post-failure=sandbox listing unavailable; inspect ownership manually\n' \
        >> "$artifacts/create.stderr.txt"
    fi
  fi
  finish 21
fi

if ! record_sandbox; then
  outcome=boundary-unavailable
  preserve_sandbox=1
  finish 22
fi

if ! sbx policy ls "$sandbox_name" --type network --wide \
  > "$artifacts/network-policy.txt" 2>&1; then
  outcome=policy-unavailable
  finish 22
fi

if ! sbx exec \
  --workdir "$workspace" \
  --env EXPECTED_WORKSPACE="$workspace" \
  "$sandbox_name" /bin/sh -lc '
    set -eu
    test "$(pwd -P)" = "$EXPECTED_WORKSPACE"
    printf "user=%s\n" "$(id -un)"
    printf "uid=%s\n" "$(id -u)"
    printf "cwd=%s\n" "$(pwd -P)"
    printf "arch=%s\n" "$(uname -m)"
    printf "kernel=%s\n" "$(uname -s)"
    command -v codex
    codex --version
    command -v timeout
    timeout --version | sed -n "1p"
    command -v sha256sum
  ' > "$artifacts/runtime.txt" 2>&1; then
  outcome=boundary-unavailable
  preserve_sandbox=1
  finish 22
fi

if ! "$AUTH_PROVISIONER" --sbx "$sandbox_name" --auth-file "$auth_file" \
  > "$artifacts/auth-provision.txt" 2>&1; then
  outcome=auth-provision-failed
  finish 23
fi
auth_provisioned=1

if ! guest_auth_before="$(
  sbx exec \
    --env RUN_DIR="$guest_run_dir" \
    --env CODEX_HOME="$guest_codex_home" \
    "$sandbox_name" /bin/sh -lc '
      set -eu
      run_root="${RUN_DIR%/*}"
      if test -e "$run_root" || test -L "$run_root"; then
        test -d "$run_root"
        test ! -L "$run_root"
      else
        install -d -m 700 "$run_root"
      fi
      test "$(readlink -f "$run_root")" = "$run_root"
      test "$(stat -c %U "$run_root")" = "$(id -un)"
      test ! -e "$RUN_DIR"
      test ! -L "$RUN_DIR"
      install -d -m 700 "$RUN_DIR"
      test "$(readlink -f "$RUN_DIR")" = "$RUN_DIR"
      # auth-baseline
      sha256sum "$CODEX_HOME/auth.json" | awk "{print \$1}"
    ' 2> "$scratch/auth-baseline.stderr"
)"; then
  outcome=auth-provision-failed
  finish 23
fi
[[ "$guest_auth_before" =~ ^[0-9a-fA-F]{64}$ ]] || {
  outcome=auth-provision-failed
  printf 'guest-auth-before=invalid-hash-shape\n' > "$artifacts/auth-cache-state.txt"
  finish 23
}
printf 'guest-auth-before=recorded-transiently-by-host-controller\n' \
  > "$artifacts/auth-cache-state.txt"
if [[ -s "$scratch/auth-baseline.stderr" ]]; then
  cp "$scratch/auth-baseline.stderr" "$artifacts/auth-baseline.stderr.txt"
fi

host_auth_before="$(host_file_stamp)"

codex_args=(
  timeout --signal=TERM --kill-after=10s "${timeout_seconds}s"
  /usr/bin/env -u OPENAI_API_KEY -u CODEX_API_KEY
  CODEX_HOME="$guest_codex_home"
  codex exec
  --cd "$workspace"
  --skip-git-repo-check
  --ephemeral
  --ignore-user-config
  --json
  --output-last-message "$guest_final"
)
case "$posture" in
  outer)
    codex_args+=(--dangerously-bypass-approvals-and-sandbox)
    ;;
  workspace-write)
    codex_args+=(--sandbox workspace-write --config 'approval_policy="never"')
    ;;
esac
if [[ -n "$model" ]]; then
  codex_args+=(--model "$model")
fi
if [[ -n "$reasoning_effort" ]]; then
  codex_args+=(--config "model_reasoning_effort=\"$reasoning_effort\"")
fi
codex_args+=(-)

{
  printf 'sbx_exec='
  printf '%q ' sbx exec --interactive --workdir "$workspace" "$sandbox_name" "${codex_args[@]}"
  printf '\n'
} > "$artifacts/invocation.txt"

log "running Codex with hard timeout=${timeout_seconds}s posture=$posture"
started_epoch="$(date +%s)"
host_timeout_seconds=$((timeout_seconds + 60))
if "$BOUNDED_RUNNER" \
  --stdin-file "$combined_prompt" \
  --stdout-file "$artifacts/events.jsonl" \
  --stderr-file "$artifacts/stderr.txt" \
  --timeout "$host_timeout_seconds" \
  -- \
  sbx exec \
    --interactive \
    --workdir "$workspace" \
    "$sandbox_name" \
    "${codex_args[@]}"; then
  agent_exit=0
else
  agent_exit=$?
fi
finished_epoch="$(date +%s)"
printf 'duration_seconds=%s\nagent_exit=%s\n' \
  "$((finished_epoch - started_epoch))" "$agent_exit" > "$artifacts/process-result.txt"

if grep -Fq '[run-bounded-command] host timeout after' "$artifacts/stderr.txt"; then
  host_deadline_reached=1
  auth_cache_state=unknown
  auth_recovery_required=1
  preserve_sandbox=1
  printf 'guest-auth-after=unknown-host-deadline-preserve-and-reconcile\n' \
    >> "$artifacts/auth-cache-state.txt"
  if sbx stop "$sandbox_name" > "$artifacts/host-timeout-stop.txt" 2>&1; then
    sandbox_stopped=1
  else
    printf 'stop=failed; finalize will retry\n' >> "$artifacts/host-timeout-stop.txt"
  fi
else
  guest_auth_after="$(
    sbx exec \
      --env CODEX_HOME="$guest_codex_home" \
      "$sandbox_name" /bin/sh -lc '
        set -eu
        # auth-after
        sha256sum "$CODEX_HOME/auth.json" | awk "{print \$1}"
      ' 2>/dev/null || true
  )"
  if [[ "$guest_auth_after" =~ ^[0-9a-fA-F]{64}$ ]] && \
    [[ "$guest_auth_before" == "$guest_auth_after" ]]; then
      auth_cache_state=unchanged
      printf 'guest-auth-after=unchanged\n' >> "$artifacts/auth-cache-state.txt"
  elif [[ "$guest_auth_after" =~ ^[0-9a-fA-F]{64}$ ]]; then
      auth_cache_state=changed
      auth_cache_changed=1
      auth_recovery_required=1
      preserve_sandbox=1
      printf 'guest-auth-after=changed-preserve-and-reconcile\n' >> "$artifacts/auth-cache-state.txt"
  else
      auth_cache_state=unknown
      auth_recovery_required=1
      preserve_sandbox=1
      printf 'guest-auth-after=unknown-preserve-and-reconcile\n' >> "$artifacts/auth-cache-state.txt"
  fi
fi

host_auth_after="$(host_file_stamp)"
if [[ "$host_auth_before" == "$host_auth_after" ]]; then
  printf 'host-auth-metadata=unchanged\n' >> "$artifacts/auth-cache-state.txt"
else
  printf 'host-auth-metadata=changed-by-external-host-activity\n' >> "$artifacts/auth-cache-state.txt"
fi

if (( host_deadline_reached == 0 )) && \
  sbx exec "$sandbox_name" /bin/sh -c \
    'test -f "$1" && test ! -L "$1" && test "$(stat -c %s "$1")" -le 1048576' \
    sh "$guest_final" >/dev/null 2>&1; then
  sbx cp "$sandbox_name:$guest_final" "$artifacts/final.md" \
    > "$artifacts/final-copy.txt" 2>&1 || true
fi

if "$VALIDATOR" \
  --workspace "$workspace" \
  --handoff "$handoff_relative" \
  --preserve-raw-to "$artifacts/handoff.json" \
  --json > "$artifacts/handoff-validation.json" 2>&1; then
  handoff_valid=1
  handoff_status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$artifacts/handoff-validation.json")"
else
  handoff_valid=0
fi

if (( auth_recovery_required == 1 && host_deadline_reached == 0 )); then
  outcome=auth-refresh-recovery-required
  finish 27
fi

case "$agent_exit" in
  0) ;;
  124)
    outcome=timed-out
    preserve_sandbox=1
    finish 24
    ;;
  137|143)
    outcome=cancelled
    preserve_sandbox=1
    finish 24
    ;;
  *)
    outcome=agent-failed
    finish 25
    ;;
esac

if (( handoff_valid == 0 )); then
  outcome=handoff-invalid
  finish 26
fi

case "$handoff_status" in
  succeeded)
    outcome=succeeded
    finish 0
    ;;
  partial)
    outcome=agent-partial
    finish 29
    ;;
  blocked)
    outcome=agent-blocked
    finish 29
    ;;
  failed)
    outcome=agent-reported-failure
    finish 29
    ;;
  *)
    outcome=handoff-invalid
    finish 26
    ;;
esac
