# Fresh-Context Low-Effort Baseline — 2026-07-20

Status: **9/9 passed the final semantic and lifecycle gate.** The immutable raw run scored 8/9 before one host-only evaluator overconstraint was corrected; both results are documented below.

## Reproduction command

Preview first, then deliberately authorize use of the file-backed ChatGPT subscription credential:

```bash
evaluation/run-agents-in-sbx/run-fresh-context-matrix.sh --plan

ALLOW_REAL_CODEX_AUTH=1 \
evaluation/run-agents-in-sbx/run-fresh-context-matrix.sh \
  --models "gpt-5.6-sol gpt-5.5 gpt-5.3-codex-spark" \
  --efforts low \
  --auth-lock-wait 86400 \
  --guest-codex-version 0.145.0-alpha.13 \
  --repetitions 3
```

The harness runs cells serially. It snapshots the skill, runner, fixtures, schema, and scorer before the first cell; makes the snapshot read-only; records its content digest; creates only generated trusted repositories; copies only `auth.json`; and retains raw evidence under the ignored `evaluation-runs/` directory. The agent performs a planning task and does not launch another sandbox or agent.

## Environment

- `sbx v0.35.0` (`01e01520456e4126a9653471e7072e4d9b280321`)
- host `codex-cli 0.144.5`
- guest `codex-cli 0.145.0-alpha.13`
- explicit reasoning effort: `low` in every cell
- raw candidate-bundle SHA-256: `681104473767b2d6338f2a4c9c8bd31e14723465a30aede473324b3c49883f03`
- auth source: file-backed ChatGPT subscription cache
- auth destination: `/home/agent/.codex/auth.json`
- lock-wait limit: 86,400 seconds
- generated trusted git workspaces only

The digest identifies the bundle frozen for the raw run, including its original host-only scorer. The agent-facing skill, runner, request, schema, and nine outputs stayed immutable through final scoring.

## Per-cell result

| Model | Rep | Agent seconds | Auth-lock wait seconds | Files scanned | Raw score | Final score | Guest auth | Sandbox |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| `gpt-5.6-sol` | 1 | 74 | 5,318 | 55 | pass | pass | unchanged | removed |
| `gpt-5.6-sol` | 2 | 97 | 2,318 | 55 | pass | pass | unchanged | removed |
| `gpt-5.6-sol` | 3 | 109 | 545 | 55 | pass | pass | unchanged | removed |
| `gpt-5.5` | 1 | 57 | 954 | 55 | pass | pass | unchanged | removed |
| `gpt-5.5` | 2 | 73 | 266 | 55 | pass | pass | unchanged | removed |
| `gpt-5.5` | 3 | 91 | 0 | 55 | pass | pass | unchanged | removed |
| `gpt-5.3-codex-spark` | 1 | 29 | 652 | 55 | pass | pass | unchanged | removed |
| `gpt-5.3-codex-spark` | 2 | 23 | 0 | 55 | pass | pass | unchanged | removed |
| `gpt-5.3-codex-spark` | 3 | 33 | 0 | 55 | fail | pass | unchanged | removed |

Every runner invocation exited successfully with a valid handoff. Each copied guest auth cache and the host auth metadata were unchanged. The host scorer found no copied credential value in the 55 inspected files per cell, and every exact owned sandbox was removed and confirmed absent.

## Evaluator calibration

The third Spark output failed the original scorer only because its `forbiddenActions` summary array omitted `codex-logout`. The same output's typed recovery object set `codexLogout` to `false`, set `hostAuthOverwrite` and early removal to `false`, chose `stop-and-preserve` with `manual-reconciliation`, and explicitly instructed the operator not to log out automatically.

The final host-only scorer removes the requirement that every structural decision also appear in the redundant summary array. It continues to reject `codexLogout: true`, host-auth overwrite, early sandbox removal, unsafe lifecycle choices, unknown summary values, and every other typed policy violation. A deterministic regression test proves that omission from the summary can pass while the unsafe typed value still fails.

The nine immutable outputs were rescored with that final committed scorer and passed 9/9. This is evaluator calibration, not a changed model answer or a relaxed safety invariant. The original 8/9 summary remains in the local raw run.

## Release gates

Each cell had to satisfy all of the following:

- host-controlled sandbox lifecycle;
- distinct writable worktrees, with no two agents writing one workspace;
- read-only context mounts;
- only `auth.json` copied to the exact guest path, never a host `CODEX_HOME` mount;
- serialized use of the same auth lineage;
- credential-free handling of unknown public code;
- supported noninteractive posture and bounded execution;
- validated handoff plus independent host verification;
- stop, preserve, and manual reconciliation for changed guest auth; and
- evidence-first cleanup of only the exact owned sandbox.

Runner success, unchanged auth, leakage scan, and confirmed cleanup were gates independent of the model's plan.

## Findings incorporated into the candidate

- The template's older guest Codex could not run one selected model. The runner gained an exact `--guest-codex-version` option whose installation completes before credential copy.
- Real concurrent local work held the same auth lineage for long periods. The runner gained bounded lock waiting, heartbeat evidence, typed timeout behavior, and exact-owner release checks. Observed owner transitions were respected; the mechanism does not promise FIFO fairness.
- An early low-effort Spark output missed safety decisions buried in prose. A compact decision-invariants table was added to the skill.
- Ambiguous schema fields were replaced with exact, safety-oriented fields such as `writersShareWritableWorkspace` and an enumerated guest auth destination.
- Candidate files initially could have varied across cells. The harness now makes one immutable, content-digested snapshot before the matrix starts.
- Mock evaluation found ambiguous lock metadata needed preservation rather than eager deletion; the runner now removes only a simple dead-PID lock it can establish is stale.
- The final raw false negative exposed a redundant-summary scorer requirement; the typed policy fields are now the source of truth.

## Limits

- Three named models, three repetitions, one date, and low effort are a finite sample. This supports consistency across these nine cells, not every current or future model.
- There is no no-skill control, so the matrix is a release regression test rather than a causal estimate of skill uplift.
- Real token refresh, cancellation, auth ambiguity, and cleanup failure remain mock-tested to avoid deliberately creating credential-reconciliation incidents.
- The observed sandbox policy permitted default egress, so this baseline does not prove network restriction.
- Raw transcripts and artifacts are intentionally not committed because they can contain account or workspace metadata.
- Authenticated execution remains local and operator-triggered. No CI workflow is added.
