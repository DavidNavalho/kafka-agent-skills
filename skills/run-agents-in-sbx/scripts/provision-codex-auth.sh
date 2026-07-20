#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'USAGE'
Usage: provision-codex-auth.sh --sbx NAME [options]

Copy a host file-backed ChatGPT Codex auth cache to an owned sbx sandbox.
The credential bytes are passed only through `sbx cp` and are never printed.

Options:
  --sbx NAME          Owned sandbox name (required).
  --auth-file PATH    Host auth cache. Defaults to $CODEX_HOME/auth.json or
                      $HOME/.codex/auth.json.
  --guest-user USER   Guest Codex user. Default: agent.
  --guest-home PATH   Guest home. Default: /home/agent.
  -h, --help          Show this help.

Never run `codex logout` in a sandbox containing a copied ChatGPT session.
USAGE
}

fail() {
  printf '[run-agents-in-sbx auth] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[run-agents-in-sbx auth] %s\n' "$*" >&2
}

sandbox=""
guest_user="agent"
guest_home="/home/agent"
if [[ -n "${CODEX_HOME:-}" ]]; then
  auth_file="${CODEX_HOME%/}/auth.json"
else
  auth_file="$HOME/.codex/auth.json"
fi

while (($#)); do
  case "$1" in
    --sbx)
      sandbox="${2:?Missing value for --sbx}"
      shift 2
      ;;
    --auth-file)
      auth_file="${2:?Missing value for --auth-file}"
      shift 2
      ;;
    --guest-user)
      guest_user="${2:?Missing value for --guest-user}"
      shift 2
      ;;
    --guest-home)
      guest_home="${2:?Missing value for --guest-home}"
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

[[ -n "$sandbox" ]] || fail "--sbx is required"
[[ "$guest_home" == /* ]] || fail "--guest-home must be absolute"
[[ "$guest_user" =~ ^[a-z_][a-z0-9_-]*$ ]] || fail "--guest-user has an unsupported shape"
[[ "$guest_home" =~ ^/[A-Za-z0-9._/-]+$ ]] || fail "--guest-home has an unsupported shape"
case "/$guest_home/" in
  */../*|*/./*) fail "--guest-home must not contain dot path components" ;;
esac
command -v sbx >/dev/null 2>&1 || fail "sbx is not installed or not on PATH"
command -v codex >/dev/null 2>&1 || fail "host codex is not installed or not on PATH"

host_status="$(codex login status 2>&1 || true)"
case "$host_status" in
  *"Logged in using ChatGPT"*) ;;
  *) fail "host Codex is not logged in using ChatGPT: $host_status" ;;
esac

[[ -f "$auth_file" ]] || fail "auth cache is missing: $auth_file"
[[ ! -L "$auth_file" ]] || fail "auth cache must not be a symlink"
[[ -s "$auth_file" ]] || fail "auth cache is empty"
if mode="$(stat -f '%Lp' "$auth_file" 2>/dev/null)"; then
  :
elif mode="$(stat -c '%a' "$auth_file" 2>/dev/null)"; then
  :
else
  fail "could not inspect auth cache permissions"
fi
mode_value=$((8#$mode))
(( (mode_value & 077) == 0 )) || fail "auth cache has group/other permission bits: mode=$mode"

codex_home="${guest_home%/}/.codex"
auth_path="$codex_home/auth.json"
staged_path="$codex_home/.auth.json.host-copy.$$.${RANDOM}${RANDOM}"

cleanup_staged() {
  sbx exec "$sandbox" /bin/sh -lc "rm -f '$staged_path'" >/dev/null 2>&1 || true
}
trap cleanup_staged EXIT

sbx exec "$sandbox" /bin/sh -lc "
  set -eu
  test \"\$(id -un)\" = '$guest_user'
  test -d '$guest_home'
  test ! -L '$guest_home'
  test \"\$(readlink -f '$guest_home')\" = '$guest_home'
  if test -e '$codex_home' || test -L '$codex_home'; then
    test -d '$codex_home'
    test ! -L '$codex_home'
  else
    install -d -m 700 '$codex_home'
  fi
  test \"\$(readlink -f '$codex_home')\" = '$codex_home'
  test \"\$(stat -c %U '$codex_home')\" = '$guest_user'
  chmod 700 '$codex_home'
  test ! -e '$staged_path'
  test ! -L '$staged_path'
" >/dev/null || fail "could not prepare guest-private Codex home"

log "copying the host ChatGPT cache by path reference into sandbox=$sandbox"
sbx cp "$auth_file" "$sandbox:$staged_path" >/dev/null || fail "sbx cp failed"

sbx exec "$sandbox" /bin/sh -lc "
  set -eu
  sudo -n chown '$guest_user:$guest_user' '$staged_path'
  chmod 600 '$staged_path'
  mv -f '$staged_path' '$auth_path'
  chmod 600 '$auth_path'
  test -f '$auth_path'
  test ! -L '$auth_path'
  test -s '$auth_path'
  test \"\$(stat -c %U '$auth_path')\" = '$guest_user'
" >/dev/null || fail "guest ownership or atomic placement failed"

guest_status="$(
  sbx exec "$sandbox" /usr/bin/env \
    -u OPENAI_API_KEY \
    -u CODEX_API_KEY \
    CODEX_HOME="$codex_home" \
    codex login status </dev/null 2>&1 || true
)"
case "$guest_status" in
  *"Logged in using ChatGPT"*)
    printf '%s\n' "$guest_status"
    log "guest auth mode verified as ChatGPT"
    ;;
  *)
    fail "guest auth is not ChatGPT after provisioning: $guest_status"
    ;;
esac

trap - EXIT
