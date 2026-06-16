#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: copy-codex-auth-to-sbx.sh [options]

Copy the host Codex ChatGPT auth cache into an sbx sandbox.

Options:
  --sbx NAME          sbx sandbox name. Defaults to agent-skills-eval.
  --auth-file PATH    Host Codex auth file. Defaults to $CODEX_HOME/auth.json
                      when CODEX_HOME is set, otherwise $HOME/.codex/auth.json.
  -h, --help          Show this help.

This copies a bearer credential. Use only for a trusted sandbox and do not
capture auth.json in logs, prompts, commits, or evaluation artifacts.
USAGE
}

SBX_NAME="${SBX_NAME:-agent-skills-eval}"
if [ -n "${CODEX_HOME:-}" ]; then
  HOST_AUTH="${CODEX_HOME%/}/auth.json"
else
  HOST_AUTH="$HOME/.codex/auth.json"
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sbx)
      SBX_NAME="${2:?Missing value for --sbx}"
      shift 2
      ;;
    --auth-file)
      HOST_AUTH="${2:?Missing value for --auth-file}"
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
  printf '[sbx-codex-auth] %s\n' "$*" >&2
}

fail() {
  printf '[sbx-codex-auth] ERROR: %s\n' "$*" >&2
  exit 1
}

command -v sbx >/dev/null 2>&1 || fail "sbx is not installed or not on PATH"
command -v codex >/dev/null 2>&1 || fail "codex is not installed or not on PATH"
[ -s "$HOST_AUTH" ] || fail "Host Codex auth file is missing or empty: $HOST_AUTH"

host_status="$(codex login status 2>&1 || true)"
case "$host_status" in
  *"Logged in using ChatGPT"*) ;;
  *)
    fail "Host Codex is not logged in using ChatGPT. Current status: $host_status"
    ;;
esac

log "Clearing sandbox Codex auth cache in $SBX_NAME"
sbx exec "$SBX_NAME" sh -lc '
  rm -f "$HOME/.codex/auth.json" "$HOME/.codex/auth.json.tmp"
' >/dev/null

log "Copying host ChatGPT auth cache into $SBX_NAME"
sbx exec -i "$SBX_NAME" sh -lc '
  set -eu
  mkdir -p "$HOME/.codex"
  umask 077
  tmp="$HOME/.codex/auth.json.tmp"
  cat > "$tmp"
  test -s "$tmp"
  mv "$tmp" "$HOME/.codex/auth.json"
  chmod 600 "$HOME/.codex/auth.json"
' < "$HOST_AUTH"

sandbox_status="$(sbx exec "$SBX_NAME" codex login status 2>&1 || true)"
printf '%s\n' "$sandbox_status"
case "$sandbox_status" in
  *"Logged in using ChatGPT"*)
    log "Sandbox Codex auth is ChatGPT-backed"
    ;;
  *)
    fail "Sandbox Codex auth is not ChatGPT-backed after copy"
    ;;
esac
