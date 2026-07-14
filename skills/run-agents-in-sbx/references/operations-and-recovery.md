# Operations, Handoff, and Recovery

Use this reference when reviewing run artifacts, handling nonzero outcomes, recovering authentication, or deciding whether to remove a sandbox or worktree.

## Run artifact bundle

The one-shot runner writes a private artifact directory containing, when reachable:

```text
preflight.txt
plan.txt
create.stdout.txt
create.stderr.txt
sandbox.json
network-policy.txt
runtime.txt
auth-provision.txt
invocation.txt
events.jsonl
stderr.txt
process-result.txt
final.md
handoff.json
handoff-validation.json
auth-cache-state.txt
host-timeout-stop.txt
cleanup.txt
result.json
```

An absent file means the lifecycle did not reach that step. `result.json` is the summary; raw command artifacts remain the evidence. Keep artifact directories out of public commits unless explicitly reviewed and redacted.

`result.json` reports `guestAuthCacheState` as `not-checked`, `unchanged`,
`changed`, or `unknown`. The compatibility boolean `guestAuthCacheChanged` is
true only for a demonstrated change; both `changed` and `unknown` require
credential recovery before the preserved sandbox is removed.

## Handoff contract 1.0

The agent must write the run-specific path named in its runner contract. Unknown fields are refused.

```json
{
  "schemaVersion": "1.0",
  "status": "succeeded",
  "summary": "Implemented the bounded task and verified the focused tests.",
  "changedFiles": ["src/example.ts", "tests/example.test.ts"],
  "validationEvidence": ["agent-evidence/RUN_ID/focused-tests.txt"],
  "unresolvedRisks": [],
  "recommendedNextAction": "Review the diff and rerun the full suite."
}
```

Rules:

- `status` is `succeeded`, `partial`, `blocked`, or `failed`.
- `summary` is nonempty and reviewable.
- All file references are workspace-relative, contain no `.` or `..` components, and do not name credential paths.
- `validationEvidence` must be nonempty for `succeeded`; every cited file must exist, be a regular non-symlink file inside the workspace, be nonempty, and stay under the validator's size cap.
- `recommendedNextAction` is a nonempty string or `null`.
- A blocked or failed run may cite no evidence, but must name the reason in `summary` and unresolved risk or next action.

The handoff is a claim with evidence pointers, not independent proof. The host verifier still inspects changes and reruns critical checks.

## Outcome model

| Outcome | Meaning | Default disposition |
| --- | --- | --- |
| `succeeded` | Exec zero, valid handoff, unchanged guest auth, cleanup succeeded | Verify workspace, then continue workflow. |
| `preflight-failed` | Tool, auth, workspace, or daemon prerequisite failed | No sandbox created; fix the named prerequisite. |
| `sandbox-create-failed` | `sbx create` failed | Preserve workspace; if error `-50` occurred under Codex/Seatbelt, use host controller. |
| `boundary-unavailable` | Created identity, exact workspace, runtime, or listing could not be verified | Stop and preserve any created sandbox; do not run Codex. |
| `policy-unavailable` | Effective network policy could not be recorded | Do not run the agent; repair policy visibility. |
| `auth-provision-failed` | Copy, ownership repair, or ChatGPT-mode check failed | Remove disposable guest cache or owned sandbox; never logout. |
| `timed-out` | In-guest hard timeout returned 124 | Preserve workspace; inspect events and stderr; retry only with a justified new bound. |
| `cancelled` | Sandbox stop or signal ended exec, commonly 137 | Preserve workspace and sandbox until state is inspected. |
| `agent-failed` | Codex exited nonzero for a non-timeout reason | Preserve workspace; distinguish auth/setup from task failure. |
| `handoff-invalid` | Handoff missing, malformed, unsafe, or cites missing evidence | Run remains incomplete even if Codex exited zero. |
| `auth-refresh-recovery-required` | Guest auth changed or its post-run state could not be verified | Stop and preserve sandbox; reconcile credential before cleanup. |
| `cleanup-failed` | Owned sandbox could not be removed or absence not verified | Report recovery command and leave ownership explicit. |

## Recovery playbooks

### `sbx` authentication error `-50`

If read-only commands work on the host but `sbx create` fails only inside a `codex exec` lane, treat the cause as nested host sandbox/Keychain context. Do not loop retries or loosen the agent's sandbox. Move creation, auth provisioning, and live integration to an unsandboxed host controller.

If the same error occurs in the host shell, record `sbx version`, check `sbx ls`, and allow for an update/authentication incident. A found executable is not proof that create/start is healthy.

### Timeout or cancellation

1. Stop the sandbox if still running: `sbx stop NAME`.
2. Record `sbx ls --json` and the sandbox network policy.
3. Collect guest-local final output if present and validate any host-visible handoff without assuming completion.
4. Inspect the owned workspace; do not reset, stash, or delete it automatically.
5. Resume only when ownership, branch, task state, and credential state are unambiguous.

### Missing or invalid handoff

Keep transcript and raw handoff bytes if any. Do not scan for alternate completion files and do not convert a convincing final message into success. A new run may repair the handoff only after inspecting whether the first run already changed the workspace.

### Leftover sandbox

Correlate by exact name and workspace in `sbx ls --json`. If both match the recorded run and evidence has been collected:

```bash
sbx rm --force NAME
```

Do not delete unknown or merely similarly named sandboxes. Never use `sbx rm --all` in an agent workflow.

### Stale runner lock

The runner uses host lock directories keyed by auth-file path and workspace path. It removes a lock automatically only when the recorded process no longer exists. If a live process owns the lock, wait or stop that run; do not delete the lock to create concurrent writers.

### Dirty or ambiguous workspace

Dirty owned work can be continued only by the same known owner after inspection. Missing workspace metadata, missing directories, mismatched branches or commits, shared ownership, symlink ambiguity, and unavailable Git facts block all writers. Inspection must not mutate, clean, adopt, or delete the workspace.

Remove a worktree only after all project-specific eligibility checks pass. Prefer safe `git worktree remove PATH` and `git branch -d BRANCH`; refusal is a safety signal, not a reason to add force.

## Independent verification

After any agent run:

1. compare the actual workspace path, branch, and baseline with the run plan;
2. inspect every changed file and unexpected untracked file;
3. rerun focused tests, then broader checks proportional to risk;
4. check cited evidence against the commands it claims;
5. scan artifacts for credential-shaped content before publishing;
6. verify the sandbox is removed or explicitly preserved with one recovery owner;
7. record deviations and unresolved risks before committing or landing work.
