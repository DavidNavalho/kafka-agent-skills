# run-agents-in-sbx Evaluation Results

## Fresh-context low-effort release matrix

Date: 2026-07-20

The release matrix ran three fresh sessions per model at explicitly low reasoning effort. All nine runner invocations succeeded, retained an unchanged guest auth cache, produced valid handoffs, passed the final semantic scorer, and removed their exact owned sandbox.

| Model | Effort | Final semantic result | Runner/auth/cleanup |
| --- | --- | --- | --- |
| `gpt-5.6-sol` | low | 3/3 passed | 3/3 passed |
| `gpt-5.5` | low | 3/3 passed | 3/3 passed |
| `gpt-5.3-codex-spark` | low | 3/3 passed | 3/3 passed |

Environment and candidate:

- `sbx v0.35.0` (`01e01520456e4126a9653471e7072e4d9b280321`)
- host `codex-cli 0.144.5`
- guest `codex-cli 0.145.0-alpha.13`, installed before auth copy
- generated trusted git repositories only
- file-backed ChatGPT subscription auth copied only to `/home/agent/.codex/auth.json`
- one serial cell at a time with a finite 86,400-second lock-wait bound
- frozen raw candidate-bundle SHA-256 `681104473767b2d6338f2a4c9c8bd31e14723465a30aede473324b3c49883f03`

The raw run summary was 8/9 because the third Spark plan omitted `codex-logout` from a redundant `forbiddenActions` summary array. Its typed recovery object independently set `codexLogout` to `false`, selected stop-and-preserve/manual reconciliation, and explicitly said not to log out automatically. The host-only scorer was corrected to keep the typed safety checks strict without requiring every decision to be repeated in the summary array. No agent-facing skill, runner, request, schema, or model output changed; rescoring the frozen nine-output corpus with the committed scorer produced 9/9. The raw failure is retained rather than rewritten.

Every final score scanned 55 generated workspace/artifact files against the copied credential material and found no match. Actual lock waits ranged from 0 to 5,318 seconds while other legitimate local runs used the same auth lineage. The harness waited or stopped according to ownership evidence and never bypassed another owner's lock. This demonstrates bounded serialization under observed contention, not FIFO fairness.

See the [redacted per-cell baseline](baselines/fresh-context-low-effort-20260720.md) for the exact command, results, evaluator calibration, findings, and limits. Raw prompts, model output, and runner artifacts remain local under the ignored `evaluation-runs/` directory because they can contain account or workspace metadata.

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
- bounded waiting behind a live owner and exact-owner lock release;
- preservation of ambiguous stale lock metadata;
- successful lifecycle and credential-copy command shape;
- exact guest auth destination and rejection of shared writable workspaces;
- guest Codex installation before auth copy;
- guest auth refresh requiring preserved-sandbox recovery;
- changed-auth recovery that forbids automatic logout or host-auth overwrite;
- agent timeout requiring preserved-sandbox recovery;
- missing handoff remaining incomplete despite agent exit zero;
- cleanup verification; and
- live-boundary and fresh-context scorer behavior without real credentials;
- immutable/read-only candidate snapshotting; and
- a complete credential-free mocked fresh-context matrix.

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

The fresh-context evidence is also intentionally bounded: it samples three named models on one date, only at low effort, and has no no-skill ablation. It supports consistency across those nine cells, not the claim that every current or future model will behave identically. The observed permissive network policy also does not prove egress restriction.
