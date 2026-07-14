#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SKILL="$REPO_ROOT/skills/run-agents-in-sbx"
VALIDATOR="$SKILL/scripts/validate-handoff.py"
RUNNER="$SKILL/scripts/run-codex-in-sbx.sh"
BOUNDED_RUNNER="$SKILL/scripts/run-bounded-command.py"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/run-agents-in-sbx-tests.XXXXXX")"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

bash -n "$SKILL/scripts/preflight.sh"
bash -n "$SKILL/scripts/provision-codex-auth.sh"
bash -n "$RUNNER"
python3 - "$VALIDATOR" "$BOUNDED_RUNNER" <<'PY'
import sys
from pathlib import Path

for path_string in sys.argv[1:]:
    source = Path(path_string).read_text(encoding="utf-8")
    compile(source, path_string, "exec")
PY

"$SKILL/scripts/preflight.sh" --help >/dev/null
"$SKILL/scripts/provision-codex-auth.sh" --help >/dev/null
"$RUNNER" --help >/dev/null
"$VALIDATOR" --help >/dev/null
"$BOUNDED_RUNNER" --help >/dev/null

printf '{"mock":"bad-mode"}\n' > "$tmp/bad-mode-auth.json"
chmod 644 "$tmp/bad-mode-auth.json"
: > "$tmp/bad-mode-commands.log"
if PATH="$REPO_ROOT/evaluation/run-agents-in-sbx/fixtures:$PATH" \
  MOCK_COMMAND_LOG="$tmp/bad-mode-commands.log" \
  "$SKILL/scripts/provision-codex-auth.sh" \
    --sbx unused-mock \
    --auth-file "$tmp/bad-mode-auth.json" >/dev/null 2>&1; then
  echo "auth provisioner accepted a group/other-readable cache" >&2
  exit 1
fi
if grep -q '^sbx ' "$tmp/bad-mode-commands.log"; then
  echo "auth provisioner touched sbx before rejecting insecure permissions" >&2
  exit 1
fi

printf 'bounded input\n' > "$tmp/bounded-input.txt"
"$BOUNDED_RUNNER" \
  --stdin-file "$tmp/bounded-input.txt" \
  --stdout-file "$tmp/bounded-output.txt" \
  --stderr-file "$tmp/bounded-stderr.txt" \
  --timeout 2 \
  -- /bin/sh -c 'cat; printf bounded-stderr >&2'
grep -q 'bounded input' "$tmp/bounded-output.txt"
grep -q 'bounded-stderr' "$tmp/bounded-stderr.txt"

if "$BOUNDED_RUNNER" \
  --stdin-file "$tmp/bounded-input.txt" \
  --stdout-file "$tmp/timeout-output.txt" \
  --stderr-file "$tmp/timeout-stderr.txt" \
  --timeout 1 \
  --kill-grace 1 \
  -- /bin/sh -c 'sleep 5'; then
  echo "host bounded-command helper accepted a timeout" >&2
  exit 1
else
  test "$?" -eq 124
fi
grep -q 'host timeout' "$tmp/timeout-stderr.txt"

workspace="$tmp/workspace"
mkdir -p "$workspace/agent-evidence/test" "$workspace/handoff"
printf 'focused tests passed\n' > "$workspace/agent-evidence/test/focused.txt"

python3 - "$workspace/handoff/valid.json" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "schemaVersion": "1.0",
    "status": "succeeded",
    "summary": "Implemented and validated the bounded test task.",
    "changedFiles": ["src/example.ts"],
    "validationEvidence": ["agent-evidence/test/focused.txt"],
    "unresolvedRisks": [],
    "recommendedNextAction": "Review the diff."
}) + "\n", encoding="utf-8")
PY

"$VALIDATOR" \
  --workspace "$workspace" \
  --handoff handoff/valid.json \
  --json > "$tmp/valid-result.json"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["valid"] is True' "$tmp/valid-result.json"

python3 - "$workspace/handoff/traversal.json" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "schemaVersion": "1.0",
    "status": "succeeded",
    "summary": "Invalid traversal fixture.",
    "changedFiles": [],
    "validationEvidence": ["../outside.txt"],
    "unresolvedRisks": [],
    "recommendedNextAction": None
}) + "\n", encoding="utf-8")
PY
if "$VALIDATOR" --workspace "$workspace" --handoff handoff/traversal.json >/dev/null 2>&1; then
  echo "validator accepted traversal evidence" >&2
  exit 1
fi

python3 - "$workspace/handoff/missing.json" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "schemaVersion": "1.0",
    "status": "succeeded",
    "summary": "Invalid missing-evidence fixture.",
    "changedFiles": [],
    "validationEvidence": ["agent-evidence/test/missing.txt"],
    "unresolvedRisks": [],
    "recommendedNextAction": None
}) + "\n", encoding="utf-8")
PY
if "$VALIDATOR" --workspace "$workspace" --handoff handoff/missing.json >/dev/null 2>&1; then
  echo "validator accepted missing evidence" >&2
  exit 1
fi

printf '{malformed-json\n' > "$workspace/handoff/malformed.json"
if "$VALIDATOR" \
  --workspace "$workspace" \
  --handoff handoff/malformed.json \
  --preserve-raw-to "$tmp/preserved-malformed.json" >/dev/null 2>&1; then
  echo "validator accepted malformed JSON" >&2
  exit 1
fi
cmp "$workspace/handoff/malformed.json" "$tmp/preserved-malformed.json"
python3 -c 'import os,stat,sys; assert stat.S_IMODE(os.stat(sys.argv[1]).st_mode) == 0o600' \
  "$tmp/preserved-malformed.json"

mock_bin="$REPO_ROOT/evaluation/run-agents-in-sbx/fixtures"
mock_workspace="$tmp/mock-workspace"
mock_artifacts="$tmp/mock-artifacts"
mock_auth="$tmp/mock-auth.json"
mock_state="$tmp/mock-sbx-state"
mock_log="$tmp/mock-commands.log"
mock_prompt="$tmp/mock-prompt.md"
mkdir -p "$mock_workspace"
mock_workspace="$(cd "$mock_workspace" && pwd -P)"
printf '{"mock":"credential-bytes-never-logged"}\n' > "$mock_auth"
chmod 600 "$mock_auth"
printf 'Perform the bounded mock task.\n' > "$mock_prompt"
: > "$mock_log"

boundary_workspace="$tmp/boundary-workspace"
boundary_artifacts="$tmp/boundary-artifacts"
boundary_state="$tmp/boundary-sbx-state"
boundary_log="$tmp/boundary-commands.log"
mkdir -p "$boundary_workspace"
boundary_workspace="$(cd "$boundary_workspace" && pwd -P)"
: > "$boundary_log"
if PATH="$mock_bin:$PATH" \
  MOCK_WORKSPACE="$boundary_workspace" \
  MOCK_SBX_STATE="$boundary_state" \
  MOCK_COMMAND_LOG="$boundary_log" \
  MOCK_LIST_AGENT=shell \
  "$RUNNER" \
    --workspace "$boundary_workspace" \
    --allow-non-git \
    --prompt-file "$mock_prompt" \
    --auth-file "$mock_auth" \
    --artifacts "$boundary_artifacts" >/dev/null; then
  echo "runner accepted a sandbox with mismatched agent identity" >&2
  exit 1
else
  test "$?" -eq 22
fi
python3 - "$boundary_artifacts/result.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["outcome"] == "boundary-unavailable", result
assert result["sandboxDisposition"] == "stopped-preserved", result
PY
test -s "$boundary_state"
rm -f "$boundary_state"

PATH="$mock_bin:$PATH" \
MOCK_WORKSPACE="$mock_workspace" \
MOCK_SBX_STATE="$mock_state" \
MOCK_COMMAND_LOG="$mock_log" \
"$RUNNER" \
  --workspace "$mock_workspace" \
  --allow-non-git \
  --prompt-file "$mock_prompt" \
  --auth-file "$mock_auth" \
  --artifacts "$mock_artifacts" >/dev/null

python3 - "$mock_artifacts/result.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["outcome"] == "succeeded", result
assert result["runnerExitCode"] == 0, result
assert result["handoffValid"] is True, result
assert result["guestAuthCacheChanged"] is False, result
assert result["guestAuthCacheState"] == "unchanged", result
assert result["sandboxDisposition"] == "removed", result
PY
test ! -e "$mock_state"
grep -q 'sbx cp ' "$mock_log"
grep -q 'sudo -n chown' "$mock_log"
grep -q 'mv -f' "$mock_log"
grep -q 'chmod 600' "$mock_log"
grep -q 'dangerously-bypass-approvals-and-sandbox' "$mock_log"
if grep -q 'credential-bytes-never-logged' "$mock_log" "$mock_artifacts"/* 2>/dev/null; then
  echo "mock credential bytes leaked into commands or artifacts" >&2
  exit 1
fi

refresh_workspace="$tmp/refresh-workspace"
refresh_artifacts="$tmp/refresh-artifacts"
refresh_state="$tmp/refresh-sbx-state"
refresh_log="$tmp/refresh-commands.log"
mkdir -p "$refresh_workspace"
refresh_workspace="$(cd "$refresh_workspace" && pwd -P)"
: > "$refresh_log"
if PATH="$mock_bin:$PATH" \
  MOCK_WORKSPACE="$refresh_workspace" \
  MOCK_SBX_STATE="$refresh_state" \
  MOCK_COMMAND_LOG="$refresh_log" \
  MOCK_AUTH_STATE=changed \
  "$RUNNER" \
    --workspace "$refresh_workspace" \
    --allow-non-git \
    --prompt-file "$mock_prompt" \
    --auth-file "$mock_auth" \
    --artifacts "$refresh_artifacts" >/dev/null; then
  echo "runner accepted a changed guest auth cache" >&2
  exit 1
else
  test "$?" -eq 27
fi
python3 - "$refresh_artifacts/result.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["outcome"] == "auth-refresh-recovery-required", result
assert result["guestAuthCacheChanged"] is True, result
assert result["guestAuthCacheState"] == "changed", result
assert result["sandboxDisposition"] == "stopped-preserved", result
PY
test -s "$refresh_state"
rm -f "$refresh_state"

timeout_workspace="$tmp/timeout-workspace"
timeout_artifacts="$tmp/timeout-artifacts"
timeout_state="$tmp/timeout-sbx-state"
timeout_log="$tmp/timeout-commands.log"
mkdir -p "$timeout_workspace"
timeout_workspace="$(cd "$timeout_workspace" && pwd -P)"
: > "$timeout_log"
if PATH="$mock_bin:$PATH" \
  MOCK_WORKSPACE="$timeout_workspace" \
  MOCK_SBX_STATE="$timeout_state" \
  MOCK_COMMAND_LOG="$timeout_log" \
  MOCK_AGENT_MODE=timeout \
  "$RUNNER" \
    --workspace "$timeout_workspace" \
    --allow-non-git \
    --prompt-file "$mock_prompt" \
    --auth-file "$mock_auth" \
    --artifacts "$timeout_artifacts" >/dev/null; then
  echo "runner accepted a timed-out agent" >&2
  exit 1
else
  test "$?" -eq 24
fi
python3 - "$timeout_artifacts/result.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["outcome"] == "timed-out", result
assert result["agentExitCode"] == 124, result
assert result["guestAuthCacheState"] == "unchanged", result
assert result["sandboxDisposition"] == "stopped-preserved", result
PY
test -s "$timeout_state"
rm -f "$timeout_state"

missing_workspace="$tmp/missing-workspace"
missing_artifacts="$tmp/missing-artifacts"
missing_state="$tmp/missing-sbx-state"
missing_log="$tmp/missing-commands.log"
mkdir -p "$missing_workspace"
missing_workspace="$(cd "$missing_workspace" && pwd -P)"
: > "$missing_log"
if PATH="$mock_bin:$PATH" \
  MOCK_WORKSPACE="$missing_workspace" \
  MOCK_SBX_STATE="$missing_state" \
  MOCK_COMMAND_LOG="$missing_log" \
  MOCK_AGENT_MODE=missing-handoff \
  "$RUNNER" \
    --workspace "$missing_workspace" \
    --allow-non-git \
    --prompt-file "$mock_prompt" \
    --auth-file "$mock_auth" \
    --artifacts "$missing_artifacts" >/dev/null; then
  echo "runner accepted a missing handoff" >&2
  exit 1
else
  test "$?" -eq 26
fi
python3 - "$missing_artifacts/result.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["outcome"] == "handoff-invalid", result
assert result["handoffValid"] is False, result
assert result["guestAuthCacheState"] == "unchanged", result
assert result["sandboxDisposition"] == "removed", result
PY
test ! -e "$missing_state"

if [[ "${RUN_HOST_CHECKS:-0}" == "1" ]]; then
  "$SKILL/scripts/preflight.sh" --workspace "$REPO_ROOT"
  plan_dir="$tmp/plan"
  printf 'Inspect only; do not change files.\n' | "$RUNNER" \
    --workspace "$REPO_ROOT" \
    --prompt-file - \
    --allow-protected-branch \
    --plan \
    --artifacts "$plan_dir" >/dev/null
  test -s "$plan_dir/plan.txt"
  test ! -e "$plan_dir/result.json"
fi

printf 'run-agents-in-sbx static tests passed\n'
