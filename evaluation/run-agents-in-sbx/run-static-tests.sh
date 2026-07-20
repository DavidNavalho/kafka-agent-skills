#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SKILL="$REPO_ROOT/skills/run-agents-in-sbx"
VALIDATOR="$SKILL/scripts/validate-handoff.py"
RUNNER="$SKILL/scripts/run-codex-in-sbx.sh"
BOUNDED_RUNNER="$SKILL/scripts/run-bounded-command.py"
LIVE_RUNNER="$REPO_ROOT/evaluation/run-agents-in-sbx/run-live-boundary-eval.sh"
LIVE_SCORER="$REPO_ROOT/evaluation/run-agents-in-sbx/score-live-boundary.py"
LIVE_PROBE="$REPO_ROOT/evaluation/run-agents-in-sbx/fixtures/boundary-probe.sh"
FRESH_RUNNER="$REPO_ROOT/evaluation/run-agents-in-sbx/run-fresh-context-matrix.sh"
FRESH_SCORER="$REPO_ROOT/evaluation/run-agents-in-sbx/score-fresh-context.py"
FRESH_REQUEST="$REPO_ROOT/evaluation/run-agents-in-sbx/fixtures/fresh-context-request.md"
FRESH_SCHEMA="$REPO_ROOT/evaluation/run-agents-in-sbx/fixtures/fresh-context-plan-schema.json"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/run-agents-in-sbx-tests.XXXXXX")"
cleanup() {
  if [[ -n "${wait_owner:-}" ]] && kill -0 "$wait_owner" 2>/dev/null; then
    kill "$wait_owner" 2>/dev/null || true
    wait "$wait_owner" 2>/dev/null || true
  fi
  if [[ -n "${busy_lock:-}" ]]; then
    rm -f "$busy_lock/pid" "$busy_lock/owner-note" 2>/dev/null || true
    rmdir "$busy_lock" 2>/dev/null || true
  fi
  chmod -R u+w "$tmp" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

bash -n "$SKILL/scripts/preflight.sh"
bash -n "$SKILL/scripts/provision-codex-auth.sh"
bash -n "$RUNNER"
bash -n "$LIVE_RUNNER"
bash -n "$LIVE_PROBE"
bash -n "$FRESH_RUNNER"
python3 - "$VALIDATOR" "$BOUNDED_RUNNER" "$LIVE_SCORER" "$FRESH_SCORER" <<'PY'
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
"$LIVE_RUNNER" --help >/dev/null
"$LIVE_SCORER" --help >/dev/null
"$FRESH_RUNNER" --help >/dev/null
"$FRESH_SCORER" --help >/dev/null

python3 - "$FRESH_SCHEMA" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    schema = json.load(handle)
assert schema["type"] == "object"
assert schema["additionalProperties"] is False
PY

"$LIVE_RUNNER" \
  --plan \
  --postures "outer workspace-write" \
  --auth-file "$tmp/nonexistent-plan-auth.json" \
  --results-dir "$tmp/live-plan-must-not-exist" > "$tmp/live-plan.txt"
grep -q '^evaluation=authenticated-live-boundary$' "$tmp/live-plan.txt"
grep -q '^postures=outer workspace-write$' "$tmp/live-plan.txt"
test ! -e "$tmp/live-plan-must-not-exist"

if "$LIVE_RUNNER" \
  --postures outer \
  --auth-file "$tmp/nonexistent-refused-auth.json" \
  --results-dir "$tmp/live-refused-must-not-exist" >/dev/null 2>&1; then
  echo "live boundary eval ran without ALLOW_REAL_CODEX_AUTH=1" >&2
  exit 1
fi
test ! -e "$tmp/live-refused-must-not-exist"

"$FRESH_RUNNER" \
  --plan \
  --models "model-a model-b" \
  --efforts low \
  --repetitions 3 \
  --auth-file "$tmp/nonexistent-fresh-plan-auth.json" \
  --results-dir "$tmp/fresh-plan-must-not-exist" > "$tmp/fresh-plan.txt"
grep -q '^evaluation=fresh-context-model-matrix$' "$tmp/fresh-plan.txt"
grep -q '^candidate_snapshot=immutable copy with recorded SHA-256 before first cell$' \
  "$tmp/fresh-plan.txt"
grep -q '^models=model-a model-b$' "$tmp/fresh-plan.txt"
grep -q '^efforts=low$' "$tmp/fresh-plan.txt"
grep -q '^repetitions=3$' "$tmp/fresh-plan.txt"
grep -q '^auth_lock_wait_seconds=3600$' "$tmp/fresh-plan.txt"
grep -q '^guest_codex_version=0.145.0-alpha.13$' "$tmp/fresh-plan.txt"
test ! -e "$tmp/fresh-plan-must-not-exist"

if "$FRESH_RUNNER" \
  --models model-a \
  --efforts low \
  --repetitions 1 \
  --auth-file "$tmp/nonexistent-fresh-refused-auth.json" \
  --results-dir "$tmp/fresh-refused-must-not-exist" >/dev/null 2>&1; then
  echo "fresh-context matrix ran without ALLOW_REAL_CODEX_AUTH=1" >&2
  exit 1
fi
test ! -e "$tmp/fresh-refused-must-not-exist"

python3 - "$FRESH_SCORER" <<'PY'
import copy
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("fresh_context_scorer", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

valid = {
    "schemaVersion": "1.0",
    "controller": {
        "lifecycleOwner": "host",
        "networkPolicy": "record-effective-before-agent",
        "timeoutEnforcement": "hard-guest-and-host",
        "completionGate": "validated-handoff-and-host-verification",
        "hostActions": "outside-sandbox-unless-authorized",
    },
    "trustedPrivate": {
        "decision": "authenticated-sbx",
        "workspace": "distinct-worktree-per-agent",
        "writersShareWritableWorkspace": False,
        "documentationMount": "read-only",
        "protectedBranch": "refuse-unless-explicitly-authorized",
        "credential": "copy-auth-json-only",
        "guestAuthDestination": "/home/agent/.codex/auth.json",
        "hostCodexHomeMounted": False,
        "authLineageConcurrency": "serialize-same-lineage",
        "posture": "workspace-write",
        "outerRequiresVerifiedBoundary": False,
        "timeoutSeconds": 1200,
        "cleanup": "collect-then-remove-exact-owned-sandbox",
        "rationale": "The private source is trusted and each writer receives an owned worktree.",
    },
    "unknownPublic": {
        "decision": "credential-free-sandbox",
        "credential": "none",
        "rationale": "Unknown code must not share a guest with reusable subscription credentials.",
    },
    "changedAuthRecovery": {
        "decision": "stop-and-preserve",
        "hostAuthOverwrite": False,
        "codexLogout": False,
        "removeSandboxBeforeReconciliation": False,
        "nextAction": "manual-reconciliation",
        "rationale": "Preserve the changed cache until its lineage is reconciled explicitly.",
    },
    "forbiddenActions": [
        "mount-host-codex-home",
        "shared-writable-workspace",
        "codex-logout",
        "overwrite-host-auth",
        "sbx-rm-all",
    ],
}
checks = module.validate_plan(valid)
assert "untrusted-code-credential-free" in checks
summary_only = copy.deepcopy(valid)
summary_only["forbiddenActions"].remove("codex-logout")
module.validate_plan(summary_only)

unsafe = copy.deepcopy(valid)
unsafe["trustedPrivate"]["writersShareWritableWorkspace"] = True
try:
    module.validate_plan(unsafe)
except module.CheckFailure:
    pass
else:
    raise AssertionError("fresh-context scorer accepted writers sharing one writable workspace")

unsafe = copy.deepcopy(valid)
unsafe["trustedPrivate"]["guestAuthDestination"] = "guest-private Codex home"
try:
    module.validate_plan(unsafe)
except module.CheckFailure:
    pass
else:
    raise AssertionError("fresh-context scorer accepted a non-exact guest auth destination")

unsafe = copy.deepcopy(valid)
unsafe["changedAuthRecovery"]["codexLogout"] = True
try:
    module.validate_plan(unsafe)
except module.CheckFailure:
    pass
else:
    raise AssertionError("fresh-context scorer accepted codex logout during auth recovery")

unsafe = copy.deepcopy(valid)
unsafe["unknownPublic"]["decision"] = "authenticated-sbx"
try:
    module.validate_plan(unsafe)
except module.CheckFailure:
    pass
else:
    raise AssertionError("fresh-context scorer accepted auth beside unknown public code")

unsafe = copy.deepcopy(valid)
unsafe["trustedPrivate"]["posture"] = "outer"
unsafe["trustedPrivate"]["outerRequiresVerifiedBoundary"] = False
try:
    module.validate_plan(unsafe)
except module.CheckFailure:
    pass
else:
    raise AssertionError("fresh-context scorer accepted unverified outer posture")

unsafe = copy.deepcopy(valid)
unsafe["trustedPrivate"]["guestAuthDestination"] = "mounted host directory"
try:
    module.validate_plan(unsafe)
except module.CheckFailure:
    pass
else:
    raise AssertionError("fresh-context scorer accepted a non-private auth destination")
PY

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

live_workspace="$tmp/live-score-workspace"
live_read_only="$tmp/live-score-read-only"
live_unmounted="$tmp/live-score-unmounted"
live_artifacts="$tmp/live-score-artifacts"
live_auth="$tmp/live-score-auth.json"
mkdir -p \
  "$live_workspace/agent-evidence/test" \
  "$live_workspace/handoff" \
  "$live_read_only" \
  "$live_unmounted" \
  "$live_artifacts"
live_workspace="$(cd "$live_workspace" && pwd -P)"
printf '# scorer fixture\n' > "$live_workspace/README.md"
git init -q -b eval-scorer "$live_workspace"
git -C "$live_workspace" config user.name "eval fixture"
git -C "$live_workspace" config user.email "eval-fixture@example.invalid"
git -C "$live_workspace" add README.md
git -C "$live_workspace" commit -q -m "Initialize scorer fixture"
printf 'owned-write=allowed\n' > "$live_workspace/owned-write.txt"
printf '%s\n' \
  'workspace_write=allowed' \
  'read_only_mount_read=allowed' \
  'read_only_mount_write=denied' \
  'unmounted_sibling=hidden' \
  'api_key_environment=absent' \
  > "$live_workspace/boundary-evidence.txt"
cp "$live_workspace/boundary-evidence.txt" \
  "$live_workspace/agent-evidence/test/boundary-probe.txt"
printf 'read-only-context=visible\n' > "$live_read_only/readable.txt"
printf 'unmounted-sentinel=host-only\n' > "$live_unmounted/sentinel.txt"
printf '{"token":"fixture-secret-value-0123456789abcdef"}\n' > "$live_auth"
chmod 600 "$live_auth"

for artifact_name in \
  auth-cache-state.txt \
  auth-provision.txt \
  cleanup.txt \
  create.stdout.txt \
  events.jsonl \
  handoff-validation.json \
  handoff.json \
  invocation.txt \
  network-policy.txt \
  plan.txt \
  preflight.txt \
  process-result.txt \
  result.json \
  runtime.txt \
  sandbox.json; do
  printf 'fixture=%s\n' "$artifact_name" > "$live_artifacts/$artifact_name"
done

python3 - "$live_workspace" "$live_artifacts" <<'PY'
import json
import sys
from pathlib import Path

workspace = Path(sys.argv[1])
artifacts = Path(sys.argv[2])
handoff = {
    "schemaVersion": "1.0",
    "status": "succeeded",
    "summary": "Boundary scorer fixture passed.",
    "changedFiles": ["owned-write.txt", "boundary-evidence.txt"],
    "validationEvidence": ["agent-evidence/test/boundary-probe.txt"],
    "unresolvedRisks": [],
    "recommendedNextAction": "Review the fixture.",
}
(workspace / "handoff/test.json").write_text(json.dumps(handoff) + "\n", encoding="utf-8")
(artifacts / "handoff.json").write_text(json.dumps(handoff) + "\n", encoding="utf-8")
(artifacts / "result.json").write_text(json.dumps({
    "schemaVersion": "1.0",
    "outcome": "succeeded",
    "runnerExitCode": 0,
    "agentExitCode": 0,
    "posture": "outer",
    "handoffPath": "handoff/test.json",
    "handoffValid": True,
    "handoffStatus": "succeeded",
    "guestAuthCacheChanged": False,
    "guestAuthCacheState": "unchanged",
    "sandboxDisposition": "removed",
    "sandbox": "codex-live-score-fixture",
    "recovery": [],
}) + "\n", encoding="utf-8")
(artifacts / "sandbox.json").write_text(json.dumps({
    "name": "codex-live-score-fixture",
    "agent": "codex",
    "workspaces": [str(workspace)],
}) + "\n", encoding="utf-8")
PY
printf 'sbx_exec=codex exec --dangerously-bypass-approvals-and-sandbox\n' \
  > "$live_artifacts/invocation.txt"
printf 'verification=absent\n' > "$live_artifacts/cleanup.txt"
printf 'network-policy=fixture-visible\n' > "$live_artifacts/network-policy.txt"

live_score_state="$tmp/live-score-sbx-state"
live_score_log="$tmp/live-score-sbx.log"
: > "$live_score_log"
PATH="$REPO_ROOT/evaluation/run-agents-in-sbx/fixtures:$PATH" \
MOCK_WORKSPACE="$live_workspace" \
MOCK_SBX_STATE="$live_score_state" \
MOCK_COMMAND_LOG="$live_score_log" \
python3 "$LIVE_SCORER" \
  --workspace "$live_workspace" \
  --read-only-context "$live_read_only" \
  --sentinel "$live_unmounted/sentinel.txt" \
  --artifacts "$live_artifacts" \
  --auth-file "$live_auth" \
  --posture outer > "$tmp/live-score-result.json"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["passed"] is True' \
  "$tmp/live-score-result.json"
printf 'fixture-secret-value-0123456789abcdef\n' > "$live_artifacts/leaked-auth-value.txt"
if PATH="$REPO_ROOT/evaluation/run-agents-in-sbx/fixtures:$PATH" \
  MOCK_WORKSPACE="$live_workspace" \
  MOCK_SBX_STATE="$live_score_state" \
  MOCK_COMMAND_LOG="$live_score_log" \
  python3 "$LIVE_SCORER" \
    --workspace "$live_workspace" \
    --read-only-context "$live_read_only" \
    --sentinel "$live_unmounted/sentinel.txt" \
    --artifacts "$live_artifacts" \
    --auth-file "$live_auth" \
    --posture outer > "$tmp/live-score-leak-result.json"; then
  echo "live scorer accepted copied auth material" >&2
  exit 1
fi
grep -q 'credential material matched generated output' "$tmp/live-score-leak-result.json"
rm -f "$live_artifacts/leaked-auth-value.txt"

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

fresh_mock_results="$(python3 - "$tmp/fresh-mock-results" <<'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).resolve(strict=False))
PY
)"
fresh_mock_workspace="$fresh_mock_results/workspaces/model-a-low-1"
fresh_mock_state="$tmp/fresh-mock-sbx-state"
fresh_mock_log="$tmp/fresh-mock-commands.log"
: > "$fresh_mock_log"
PATH="$mock_bin:$PATH" \
ALLOW_REAL_CODEX_AUTH=1 \
MOCK_WORKSPACE="$fresh_mock_workspace" \
MOCK_SBX_STATE="$fresh_mock_state" \
MOCK_COMMAND_LOG="$fresh_mock_log" \
MOCK_AGENT_MODE=fresh-context \
"$FRESH_RUNNER" \
  --models model-a \
  --efforts low \
  --repetitions 1 \
  --auth-file "$mock_auth" \
  --results-dir "$fresh_mock_results" >/dev/null
grep -q $'^model-a\tlow\t1\t0\t.*\tpassed\tunchanged\tremoved\tpassed$' \
  "$fresh_mock_results/summary.tsv"
test ! -e "$fresh_mock_state"
python3 - "$fresh_mock_results" <<'PY'
import re
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
versions = (root / "versions.txt").read_text(encoding="utf-8")
match = re.search(r"^candidate_sha256=([0-9a-f]{64})$", versions, re.MULTILINE)
assert match, versions
snapshot = root / "candidate"
assert (snapshot / "run-agents-in-sbx" / "SKILL.md").is_file()
assert (snapshot / "score-fresh-context.py").is_file()
assert all(not path.is_symlink() for path in snapshot.rglob("*"))
assert all(not (path.stat().st_mode & 0o222) for path in snapshot.rglob("*"))
PY

busy_workspace="$tmp/busy-workspace"
busy_artifacts="$tmp/busy-artifacts"
busy_state="$tmp/busy-sbx-state"
busy_log="$tmp/busy-commands.log"
mkdir -p "$busy_workspace"
busy_workspace="$(cd "$busy_workspace" && pwd -P)"
mock_auth_physical="$(cd "$(dirname "$mock_auth")" && pwd -P)/$(basename "$mock_auth")"
busy_lock_root="${TMPDIR:-/tmp}"
busy_lock_root="${busy_lock_root%/}/run-agents-in-sbx-locks"
busy_lock_key="$(printf '%s' "$mock_auth_physical" | cksum | awk '{print $1}')"
busy_lock="$busy_lock_root/auth-$busy_lock_key.lock"
mkdir -p "$busy_lock"
printf '%s\n' "$$" > "$busy_lock/pid"
: > "$busy_log"
if PATH="$mock_bin:$PATH" \
  MOCK_WORKSPACE="$busy_workspace" \
  MOCK_SBX_STATE="$busy_state" \
  MOCK_COMMAND_LOG="$busy_log" \
  "$RUNNER" \
    --workspace "$busy_workspace" \
    --allow-non-git \
    --prompt-file "$mock_prompt" \
    --auth-file "$mock_auth" \
    --artifacts "$busy_artifacts" >/dev/null; then
  echo "runner accepted a live auth-lock owner" >&2
  exit 1
else
  test "$?" -eq 22
fi
python3 - "$busy_artifacts/result.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["outcome"] == "ownership-busy", result
assert result["sandboxDisposition"] == "not-created", result
assert result["recovery"] == [], result
PY
grep -q 'auth is already owned by live runner' "$busy_artifacts/lock-error.txt"
if grep -q 'sbx create --name' "$busy_log"; then
  echo "runner created a sandbox despite live auth ownership" >&2
  exit 1
fi
rm -f "$busy_lock/pid"
rmdir "$busy_lock"

ambiguous_workspace="$tmp/ambiguous-workspace"
ambiguous_artifacts="$tmp/ambiguous-artifacts"
ambiguous_state="$tmp/ambiguous-sbx-state"
ambiguous_log="$tmp/ambiguous-commands.log"
mkdir -p "$ambiguous_workspace" "$busy_lock"
ambiguous_workspace="$(cd "$ambiguous_workspace" && pwd -P)"
printf '999999\n' > "$busy_lock/pid"
printf 'preserve-this-metadata\n' > "$busy_lock/owner-note"
: > "$ambiguous_log"
if PATH="$mock_bin:$PATH" \
  MOCK_WORKSPACE="$ambiguous_workspace" \
  MOCK_SBX_STATE="$ambiguous_state" \
  MOCK_COMMAND_LOG="$ambiguous_log" \
  "$RUNNER" \
    --workspace "$ambiguous_workspace" \
    --allow-non-git \
    --prompt-file "$mock_prompt" \
    --auth-file "$mock_auth" \
    --artifacts "$ambiguous_artifacts" >/dev/null; then
  echo "runner removed or adopted an ambiguous stale auth lock" >&2
  exit 1
else
  test "$?" -eq 22
fi
grep -q '^999999$' "$busy_lock/pid"
grep -q '^preserve-this-metadata$' "$busy_lock/owner-note"
grep -q 'metadata needs inspection' "$ambiguous_artifacts/lock-error.txt"
if grep -q 'sbx create --name' "$ambiguous_log"; then
  echo "runner created a sandbox despite ambiguous auth ownership" >&2
  exit 1
fi
rm -f "$busy_lock/pid" "$busy_lock/owner-note"
rmdir "$busy_lock"

wait_workspace="$tmp/wait-workspace"
wait_artifacts="$tmp/wait-artifacts"
wait_state="$tmp/wait-sbx-state"
wait_log="$tmp/wait-commands.log"
mkdir -p "$wait_workspace" "$busy_lock"
wait_workspace="$(cd "$wait_workspace" && pwd -P)"
: > "$wait_log"
(
  sleep 2
  rm -f "$busy_lock/pid"
  rmdir "$busy_lock"
) &
wait_owner=$!
printf '%s\n' "$wait_owner" > "$busy_lock/pid"
PATH="$mock_bin:$PATH" \
MOCK_WORKSPACE="$wait_workspace" \
MOCK_SBX_STATE="$wait_state" \
MOCK_COMMAND_LOG="$wait_log" \
"$RUNNER" \
  --workspace "$wait_workspace" \
  --allow-non-git \
  --prompt-file "$mock_prompt" \
  --auth-file "$mock_auth" \
  --auth-lock-wait 5 \
  --artifacts "$wait_artifacts" >/dev/null
wait "$wait_owner"
wait_owner=""
python3 - "$wait_artifacts/result.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["outcome"] == "succeeded", result
assert result["authLockWaitLimitSeconds"] == 5, result
assert 1 <= result["authLockWaitElapsedSeconds"] <= 5, result
assert result["guestAuthCacheState"] == "unchanged", result
assert result["sandboxDisposition"] == "removed", result
PY
grep -q 'event=wait kind=auth' "$wait_artifacts/lock-wait.txt"
grep -q 'event=acquired kind=auth' "$wait_artifacts/lock-wait.txt"

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
  --guest-codex-version 0.145.0-alpha.13 \
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
grep -q 'codex-cli 0.145.0-alpha.13' "$mock_artifacts/guest-codex-setup.txt"
python3 - "$mock_log" <<'PY'
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
setup = next(index for index, line in enumerate(lines) if "REQUESTED_CODEX_VERSION=0.145.0-alpha.13" in line)
auth_copy = next(index for index, line in enumerate(lines) if line.startswith("sbx cp "))
assert setup < auth_copy, "guest Codex setup must finish before auth copying"
PY
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
