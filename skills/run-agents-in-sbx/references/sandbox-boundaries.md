# sbx Agent Boundary Model

Use this reference when choosing mounts, network policy, Codex posture, or host-side capabilities, and whenever `sbx` or Codex versions materially change.

## Separate boundaries

| Boundary | Owned by | Required rule |
| --- | --- | --- |
| Outer containment | Host `sbx` controller | Create a uniquely named sandbox and record its identity. |
| Writable state | Workspace/worktree owner | Give one agent one writable workspace; mount extra context read-only. |
| Agent command policy | Codex invocation | Choose and record `workspace-write` or validated outer-only posture. |
| Credentials | Host auth strategy | Copy only the minimum credential into guest-private storage. |
| Network | `sbx` policy | Record the effective rules; never infer restriction from sandboxing. |
| Host capabilities | Host broker/controller | Keep Xcode, publishing, merge, and host secrets outside the agent. |
| Completion | Handoff gate + verifier | Require a valid file handoff and independent evidence checks. |
| Cleanup/recovery | Host controller | Collect first; remove only owned sandboxes; preserve ambiguous work. |

An outer sandbox does not imply least-privilege network, correct workspace ownership, safe credential scope, noninteractive Codex behavior, or authority for host actions.

The copied ChatGPT cache is outside host-visible mounts but inside the guest. This protects the host directory from direct sharing; it does not make the credential unreadable to the guest user. Treat authenticated sandboxes as trusted private runners, not malware-analysis chambers.

## Proven lifecycle

Use this order:

1. Diagnose with `command -v sbx`, `sbx version`, `sbx --help`, and a non-mutating daemon call such as `sbx ls --json`.
2. Reserve a unique sandbox name and one writable workspace.
3. Create with `sbx create --name NAME codex WORKSPACE [CONTEXT:ro ...]`.
4. Confirm the sandbox appears in `sbx ls --json` with the expected agent and exact workspace spelling.
5. Record guest user, architecture, current directory, Codex version, and hard-timeout availability.
6. Record `sbx policy ls NAME --type network` before agent execution.
7. If the template Codex CLI cannot support the selected model, install an explicit guest version and record it before credentials cross the boundary.
8. Provision isolated auth and verify `codex login status` reports ChatGPT.
9. Run a bounded command with stdin closed or fully supplied, capturing stdout and stderr from process start.
10. Collect the final message, JSONL events, handoff, evidence, exit status, and duration.
11. Validate the handoff and independently verify the workspace.
12. Stop on cancellation; after evidence collection, remove the owned sandbox with `sbx rm --force NAME`, or preserve it for a named recovery reason.

`sbx create` exposes the workspace at the same absolute path in the Linux guest. There is no separate mount step. `sbx exec` starts a stopped sandbox automatically.

## Path spelling

On macOS, `/tmp/x` and `/private/tmp/x` may name the same host directory. Inside the Linux guest they are distinct. `sbx` mounts the path spelling registered at creation. Preserve that exact physical spelling in all guest-facing commands.

Prefer:

```bash
workspace="$(cd "$workspace" && pwd -P)"
```

Then pass the same value to `sbx create`, `sbx exec --workdir`, Codex `--cd`, and the handoff validator. Do not standardize `/private/tmp` back to `/tmp` after creation. An agent can exit zero while writing to the wrong unmounted guest-local path, so verify host-visible files rather than trusting stdout.

## Codex posture

The conservative posture retains Codex's inner sandbox:

```text
codex exec --sandbox workspace-write -c approval_policy="never" ...
```

The externally sandboxed posture removes inner prompts and sandboxing:

```text
codex exec --dangerously-bypass-approvals-and-sandbox ...
```

Use the second form only inside an owned and validated outer `sbx`. Before using it after a Codex upgrade, confirm the flag still appears in `codex exec --help` and rerun the boundary matrix below. Never copy the command out of the outer runner.

Do not assume the agent template carries the same Codex CLI as the host. When a selected model requires a newer guest CLI, use the runner's exact `--guest-codex-version` pin. The runner installs it only after recording network policy and before provisioning ChatGPT auth, so package installation never runs beside the copied credential.

## Mandatory boundary matrix

On first adoption and after material tool drift, run paired trivial tasks under both postures and record each cell:

- owned workspace read and write: allowed;
- unmounted sibling host path: denied;
- host Codex and other credential paths: denied without reading bytes;
- direct GitHub, Xcode, merge, publish, or other host broker: denied;
- guest user, current directory, mount, and sandbox identity: visible;
- network policy: visible and equal across postures;
- valid handoff and cited artifact: host-visible and accepted;
- missing/invalid handoff and missing evidence: refused despite exit zero;
- hard timeout: exit 124 and classified as timeout;
- explicit cancellation: sandbox stops, host exec settles, workspace remains;
- cleanup: sandbox absent after explicit removal.

Do not place real secret bytes in boundary evidence. Probe only existence or denial. Use disposable sentinels and workspaces, never personal repositories or actual credential files.

## Network and dependencies

Observed local defaults may be permissive, including an allow-all rule. Record that fact in diagnostics and tell the user when network exposure matters. A sandbox with permissive egress still reduces host filesystem reach, but it does not prevent exfiltration of anything deliberately copied into the guest.

Install unfamiliar dependencies inside the sandbox. Keep caches and build outputs in the owned workspace or guest-local filesystem. Copy back only intentional artifacts.

Separate *unfamiliar but trusted* dependencies from intentionally adversarial code. Do not run untrusted lifecycle hooks in the same guest that contains reusable ChatGPT auth unless a proven policy or proxy prevents credential reads and egress.

## Host capabilities

`sbx` guests are Linux and may be a different architecture from the host. Host-only tools such as Xcode cannot be made available safely by merely widening mounts. Route such operations through a typed host request/result contract:

1. agent writes a request with operation, reason, target, expected blast radius, and evidence needs;
2. host controller validates authority and executes if allowed;
3. host writes a result artifact without exposing its credential;
4. agent reads only that result.

Agent permission prompts, workflow approvals, and host-action approval are separate. Disabling inner Codex prompts never grants a host action.

## Output and streaming

Capture stdout and stderr from process start. Do not assume a host adapter receives live incremental output merely because the agent prints incrementally. Codex `--json` provides JSONL events, but durable capture and UI streaming remain separate concerns.

Treat transcripts as potentially sensitive project artifacts. Never include auth files, environment dumps, private keys, or copied token values in them.
