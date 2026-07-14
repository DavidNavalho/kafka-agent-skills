#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: preflight.sh [options]

Check the host prerequisites for a Codex-in-sbx run without creating a
sandbox or reading credential values.

Options:
  --workspace PATH   Workspace/worktree to inspect.
  --auth-file PATH   File-backed ChatGPT auth cache. Defaults to
                     $CODEX_HOME/auth.json or $HOME/.codex/auth.json.
  -h, --help         Show this help.
USAGE
}

fail() {
  printf '[run-agents-in-sbx preflight] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[run-agents-in-sbx preflight] %s\n' "$*"
}

workspace=""
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
    --auth-file)
      auth_file="${2:?Missing value for --auth-file}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

command -v sbx >/dev/null 2>&1 || fail "sbx is not installed or not on PATH"
command -v codex >/dev/null 2>&1 || fail "codex is not installed or not on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 is required by the bundled runner"

sbx_version="$(sbx version 2>&1)" || fail "sbx version failed: $sbx_version"
codex_version="$(codex --version 2>&1)" || fail "codex --version failed: $codex_version"
codex_help="$(codex exec --help 2>&1)" || fail "codex exec --help failed"
for required_flag in \
  --dangerously-bypass-approvals-and-sandbox \
  --sandbox \
  --ephemeral \
  --ignore-user-config \
  --json \
  --output-last-message; do
  case "$codex_help" in
    *"$required_flag"*) ;;
    *) fail "installed Codex does not expose required flag: $required_flag" ;;
  esac
done

sbx_create_help="$(sbx create codex --help 2>&1)" || fail "sbx create codex --help failed"
case "$sbx_create_help" in
  *"PATH"*":ro"*) ;;
  *) fail "installed sbx create surface does not match the required mount contract" ;;
esac

sbx ls --json >/dev/null 2>&1 || fail "sbx daemon/auth is not reachable from this host context"
sbx policy ls --type network >/dev/null 2>&1 || fail "sbx network policy is not visible"

host_status="$(codex login status 2>&1 || true)"
case "$host_status" in
  *"Logged in using ChatGPT"*) ;;
  *) fail "host Codex is not logged in with ChatGPT: $host_status" ;;
esac

[[ -f "$auth_file" ]] || fail "file-backed auth cache is missing: $auth_file"
[[ ! -L "$auth_file" ]] || fail "auth cache must not be a symlink: $auth_file"
[[ -s "$auth_file" ]] || fail "auth cache is empty: $auth_file"

if mode="$(stat -f '%Lp' "$auth_file" 2>/dev/null)"; then
  :
elif mode="$(stat -c '%a' "$auth_file" 2>/dev/null)"; then
  :
else
  fail "could not inspect auth cache permissions"
fi
mode_value=$((8#$mode))
(( (mode_value & 077) == 0 )) || fail "auth cache has group/other permission bits: mode=$mode"

log "sbx=$sbx_version"
log "codex=$codex_version"
log "host-auth=ChatGPT file-backed mode=$mode"

if [[ -n "$workspace" ]]; then
  [[ -d "$workspace" ]] || fail "workspace is not a directory: $workspace"
  workspace="$(cd "$workspace" && pwd -P)"
  [[ "$workspace" != "/" ]] || fail "workspace must not be the filesystem root"
  [[ "$workspace" != "$HOME" ]] || fail "workspace must not be the host home directory"
  log "workspace=$workspace"

  if git -C "$workspace" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch="$(git -C "$workspace" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'detached')"
    commit="$(git -C "$workspace" rev-parse HEAD 2>/dev/null || printf 'unknown')"
    log "git-branch=$branch"
    log "git-head=$commit"
    case "$branch" in
      main|master)
        log "warning=protected branch; the runner refuses writes unless explicitly overridden"
        ;;
    esac
  else
    log "git=not-a-worktree; the runner requires an explicit override"
  fi
fi

log "network-policy=visible (inspect the per-sandbox policy before execution)"
log "preflight=passed"
