---
name: run-agents-in-sbx
description: Run coding agents inside Docker's sbx with explicit workspace ownership, bounded execution, narrowly copied credentials, durable evidence, handoff validation, and safe cleanup or recovery. Use for sandboxed implementation lanes in trusted private workspaces, agent evaluations, CI-like noninteractive runs, dependency-heavy host isolation, or troubleshooting sbx mounts, network policy, Codex authentication, timeouts, handoffs, and leftover sandboxes. The implemented provider path is Codex CLI authenticated with a copied ChatGPT-subscription auth cache; Claude subscription, Claude API, and OpenAI API adapters are intentionally not implemented yet.
---

# Run Agents in sbx

Run an agent as a host-controlled lifecycle, not as an ad hoc command. Keep the outer `sbx` boundary, workspace ownership, agent permission posture, credentials, network policy, host capabilities, completion contract, and cleanup as separate explicit decisions.

## Current support

- Support `sbx` plus Codex CLI using ChatGPT-subscription authentication copied from a file-backed host `auth.json`.
- Support one writable workspace, optional additional read-only mounts, hard timeouts, JSONL event capture, a run-specific handoff, and explicit cleanup.
- Support two Codex postures: `outer` for a fully externally sandboxed run and `workspace-write` for defense in depth.
- Do not claim support for Claude subscription, Claude API, OpenAI API-key auth, Codex access tokens, or native `sbx secret set -g openai --oauth`. Treat them as future provider strategies.

## Non-negotiable boundaries

1. Drive `sbx` from a host controller. If `sbx create` fails with authentication error `-50` from inside another Codex/Seatbelt sandbox, stop and move the lifecycle to an unsandboxed host process.
2. Give one agent one owned writable workspace. For code changes, prefer a dedicated git worktree and never allow two writers to share it.
3. Mount only the owned workspace writable. Add context repositories or documents as read-only mounts.
4. Never mount host `CODEX_HOME`, `~/.codex`, API keys, GitHub credentials, SSH keys, or other host secret directories into the sandbox.
5. Copy only file-backed ChatGPT `auth.json` into the guest-private Codex home. Never run `codex logout` in a sandbox containing a copied session. Remember that guest processes can potentially reach the copied file: use this strategy only for trusted private workspaces and prompts.
6. Record the effective network policy. Visibility is mandatory; a visible permissive policy is not a restrictive policy.
7. Put every agent invocation behind a hard timeout and close stdin. Treat exit codes and terminal text as diagnostics, not completion.
8. Require a valid run-specific handoff whose evidence paths exist. Independently inspect the workspace and rerun important validation on the host afterward.
9. Collect evidence before cleanup. Remove only the uniquely named sandbox owned by this run; never use `sbx rm --all`.
10. Preserve the workspace on every failure. Preserve the sandbox too when authentication refresh or an ambiguous interruption requires recovery.

Read [references/sandbox-boundaries.md](references/sandbox-boundaries.md) before changing mounts, Codex posture, network handling, or host-capability access. Read [references/codex-chatgpt-auth.md](references/codex-chatgpt-auth.md) before provisioning, diagnosing, or recovering authentication. Read [references/operations-and-recovery.md](references/operations-and-recovery.md) for artifact, handoff, timeout, cancellation, and cleanup semantics.

## Workflow

### 1. Establish authority and ownership

- Identify the task, writable workspace, allowed read-only mounts, network need, timeout, and whether any host-side action is separately authorized.
- Classify workspace and dependency trust. For adversarial code, public pull requests from unknown authors, or intentionally malicious-package analysis, use a separate credential-free sandbox; do not place a reusable ChatGPT auth cache beside that code.
- For implementation, create or select a dedicated worktree before launching the agent. Record its branch and baseline commit.
- Refuse a write run on `main` or `master` unless the user explicitly authorizes that target. Refuse an unknown, shared, symlink-ambiguous, or already-active workspace.
- Keep commits, pushes, merges, publishing, host application use, and privileged integrations outside the sandbox unless the user explicitly assigns them and a host broker owns them.

### 2. Preflight without touching credentials

Run:

```bash
<skill-dir>/scripts/preflight.sh \
  --workspace /absolute/path/to/worktree
```

The preflight checks the installed `sbx` and Codex surfaces, host ChatGPT login mode, file-backed credential availability and permissions, `sbx` daemon reachability, and workspace identity. It reads no token values and creates no sandbox.

Use `sbx version`, not `sbx --version`. Record `codex --version`, `codex exec --help`, and `sbx version` for every run. Re-run the boundary matrix in [references/sandbox-boundaries.md](references/sandbox-boundaries.md) after material tool-version drift; do not silently pin an older tool to avoid revalidation.

### 3. Preview the run

Use the runner's plan mode when the target, posture, mounts, or credential crossing deserves review:

```bash
<skill-dir>/scripts/run-codex-in-sbx.sh \
  --workspace /absolute/path/to/worktree \
  --prompt-file ./task.md \
  --plan
```

Before the first real credential copy, state the host credential reference, guest-private destination, workspace trust assumption, effective egress policy, serialization rule, sandbox lifetime, artifact location, and cleanup behavior. An explicit request to run a ChatGPT-subscription Codex agent in `sbx` authorizes the narrow copy; otherwise request approval before proceeding.

### 4. Execute through the bundled runner

Prefer the one-shot runner instead of reconstructing the lifecycle in shell:

```bash
<skill-dir>/scripts/run-codex-in-sbx.sh \
  --workspace /absolute/path/to/worktree \
  --prompt-file ./task.md \
  --timeout 1800 \
  --memory 8g \
  --cpus 4
```

Or send the task on stdin:

```bash
<skill-dir>/scripts/run-codex-in-sbx.sh \
  --workspace /absolute/path/to/worktree \
  --prompt-file - <<'PROMPT'
Implement the approved task, run the relevant tests, and leave reviewable evidence.
PROMPT
```

Useful options:

- `--read-only-mount PATH` for extra context without another writable surface.
- `--artifacts PATH` for durable logs outside the default temporary root.
- `--model MODEL` and `--reasoning-effort EFFORT` when the task fixes them.
- `--posture outer` only because this runner creates and verifies the outer sandbox; use `workspace-write` when retaining Codex's inner sandbox is preferable.
- `--keep-sandbox` only for deliberate diagnosis. The workspace is preserved regardless.
- `--allow-protected-branch` or `--allow-non-git` only after confirming that the exception matches the task.

The runner serializes use of a given auth cache and writable workspace. Do not bypass its locks to gain parallelism. Give parallel agents distinct worktrees and, until refreshed-copy reconciliation is implemented, distinct or strictly serialized ChatGPT auth streams.

If the runner reports `ownership-busy`, another live process owns the auth cache or workspace. Wait for that exact owner to finish; do not remove its lock, copy the same auth lineage to evade serialization, or start a competing writer.

### 5. Validate completion

Require all of these before calling the task complete:

- Codex exited successfully rather than timing out or being cancelled.
- The run-specific handoff passed `scripts/validate-handoff.py`.
- Every cited validation artifact exists inside the workspace and is a bounded regular file.
- The workspace contains the intended changes and no unexplained changes.
- Important tests or checks pass when independently rerun outside the agent transcript.
- Network policy, versions, exact invocation posture, and cleanup outcome are present in the run artifacts.

Terminal output, a final Codex message, exit code zero, or a plausible diff alone is insufficient.

### 6. Recover or clean up

- On ordinary success or task failure, collect artifacts and remove the owned sandbox with `sbx rm --force <name>`; this flag is required for noninteractive cleanup.
- On timeout, cancellation, missing/invalid handoff, or validation failure, preserve the workspace and report a typed outcome plus recovery commands.
- If the guest auth cache changed, preserve and stop the sandbox. Do not discard or automatically overwrite the host cache; follow the reconciliation procedure in [references/codex-chatgpt-auth.md](references/codex-chatgpt-auth.md).
- Remove a git worktree only after it is clean, fully integrated or intentionally abandoned, no longer owned by a run, and eligible under the project's cleanup policy. Never use forced git worktree or branch deletion as recovery.

## Existing sandboxes

Use `scripts/provision-codex-auth.sh` directly only when the user deliberately wants to reuse a known, owned sandbox:

```bash
<skill-dir>/scripts/provision-codex-auth.sh --sbx <owned-name>
```

First verify the sandbox's recorded workspace, agent type, owner, network policy, and absence of another active writer. Do not adopt or delete an unfamiliar sandbox merely because its name looks related.

## Provider extension seam

Keep future providers behind the same conceptual operations:

1. probe runtime and version;
2. provision an isolated credential strategy;
3. build a bounded noninteractive invocation;
4. classify timeout, cancellation, auth, and task failures;
5. collect transcript, final output, artifacts, and handoff;
6. reconcile refreshed credentials when applicable;
7. clean up or preserve for recovery.

Add one strategy at a time and prove it against the same boundary matrix. Do not weaken the current Codex/ChatGPT path to make an unproved provider appear generic.
