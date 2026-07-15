# run-agents-in-sbx Evaluation Results

## Authenticated live boundary evaluation

Date: 2026-07-15

Command:

```bash
evaluation/run-agents-in-sbx/run-live-boundary-eval.sh --plan
ALLOW_REAL_CODEX_AUTH=1 evaluation/run-agents-in-sbx/run-live-boundary-eval.sh \
  --repetitions 3
```

Environment:

- `sbx v0.35.0`
- `codex-cli 0.144.4`
- `gpt-5.4-mini`
- low reasoning effort
- generated trusted git repositories only
- file-backed ChatGPT subscription auth copied into each guest
- effective network policy included `default-allow-all`

Results:

| Posture | Result | Guest auth | Sandbox |
| --- | --- | --- | --- |
| `outer` | 3/3 passed | unchanged in every run | removed and confirmed absent after every run |
| `workspace-write` | 3/3 passed | unchanged in every run | removed and confirmed absent after every run |

Each case proved:

- the owned workspace was writable;
- the additional context mount was readable but not writable;
- a host sibling sentinel that was not mounted remained hidden;
- `OPENAI_API_KEY` and `CODEX_API_KEY` were absent from the task environment;
- the exact sandbox identity, runtime, invocation posture, and effective network policy were recorded;
- Codex produced a valid run-specific handoff citing host-visible boundary evidence;
- the scorer found no copied auth material in 51 generated workspace/artifact files;
- the guest auth cache was unchanged; and
- the uniquely owned sandbox was removed and absent from `sbx ls --json`.

Local raw evidence was retained under the ignored run set `evaluation-runs/live-boundary-20260715T013708Z-18159/`.

The permissive network policy means this run demonstrates filesystem, process-lifecycle, evidence, and cleanup boundaries. It does not demonstrate egress restriction.

## Live serialization check

A subsequent repetition attempt encountered another legitimate runner using the same host auth lineage. The evaluation refused before sandbox creation or credential copying. That observation exposed an overly generic `internal-error` classification; the runner now emits exit `22`, outcome `ownership-busy`, auth state `not-checked`, and sandbox disposition `not-created`. The corrected behavior was then verified against the still-live owner as well as in the mock suite.

## Deterministic and mock evaluation

[`run-static-tests.sh`](run-static-tests.sh) covers:

- syntax and help surfaces;
- refusal to start the live harness without explicit real-auth opt-in;
- insecure auth-cache permissions;
- host process-group timeout behavior;
- valid, malformed, traversal, and missing-evidence handoffs;
- raw malformed-handoff preservation with mode `0600`;
- sandbox agent/workspace identity mismatch;
- live auth-lock contention reported as typed `ownership-busy` without creating a sandbox;
- successful lifecycle and credential-copy command shape;
- guest auth refresh requiring preserved-sandbox recovery;
- agent timeout requiring preserved-sandbox recovery;
- missing handoff remaining incomplete despite agent exit zero;
- cleanup verification; and
- live-boundary scorer behavior without real credentials.

## Fresh-context evaluation

On 2026-07-13, a fresh-context agent used only the skill to plan a sandboxed Node dependency task. It correctly chose an owned worktree, read-only documentation mount, noninteractive posture, narrow ChatGPT-auth copy, serialized execution, strict handoff, and typed recovery. It exposed that malformed handoff bytes were not yet retained for diagnosis; the validator and runner were updated and regression-tested before the authenticated live run.

## Coverage still intentionally deferred

The following branches are deterministic/mock-tested but were not induced with a real subscription credential because they can leave a refreshed or ambiguous auth cache requiring manual reconciliation:

- real token refresh;
- host cancellation during a model request;
- outer host-deadline failure;
- real `sbx` cleanup failure; and
- attempts to bypass serialization with another copy of the same auth lineage.

The live harness supports `--repetitions` for future drift and race checks. Rerun both postures after material `sbx` or Codex CLI changes.
