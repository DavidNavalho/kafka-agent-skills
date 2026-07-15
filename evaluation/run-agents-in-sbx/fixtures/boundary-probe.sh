#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 4 ]]; then
  echo "Usage: boundary-probe.sh WORKSPACE READ_ONLY_CONTEXT UNMOUNTED_SENTINEL EVIDENCE" >&2
  exit 2
fi

workspace="$1"
read_only_context="$2"
unmounted_sentinel="$3"
evidence="$4"

[[ "$workspace" == /* ]] || { echo "workspace must be absolute" >&2; exit 2; }
[[ "$read_only_context" == /* ]] || { echo "read-only context must be absolute" >&2; exit 2; }
[[ "$unmounted_sentinel" == /* ]] || { echo "sentinel must be absolute" >&2; exit 2; }
[[ "$evidence" == "$workspace"/* ]] || { echo "evidence must be inside workspace" >&2; exit 2; }

[[ "$(pwd -P)" == "$workspace" ]] || {
  echo "probe was not run from the owned workspace" >&2
  exit 1
}

printf 'owned-write=allowed\n' > "$workspace/owned-write.txt"
grep -qx 'read-only-context=visible' "$read_only_context/readable.txt"

if (printf 'write-must-fail\n' > "$read_only_context/write-attempt.txt") 2>/dev/null; then
  echo "read-only context accepted a write" >&2
  exit 1
fi

if [[ -e "$unmounted_sentinel" ]]; then
  echo "unmounted sibling is visible inside the sandbox" >&2
  exit 1
fi

[[ -z "${OPENAI_API_KEY:-}" ]] || { echo "OPENAI_API_KEY leaked into task environment" >&2; exit 1; }
[[ -z "${CODEX_API_KEY:-}" ]] || { echo "CODEX_API_KEY leaked into task environment" >&2; exit 1; }

mkdir -p "$(dirname "$evidence")"
{
  printf 'workspace_write=allowed\n'
  printf 'read_only_mount_read=allowed\n'
  printf 'read_only_mount_write=denied\n'
  printf 'unmounted_sibling=hidden\n'
  printf 'api_key_environment=absent\n'
} > "$evidence"

printf 'boundary probe passed\n'
