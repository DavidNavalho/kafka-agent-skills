# kafka-architecture-investigation Evaluation Plan

Purpose: forward-test `kafka-architecture-investigation` in `sbx` so the skill succeeds because its files are sufficient, context-efficient, and safe to run in an isolated environment.

This skill should not be evaluated first with a full Kafka proof. Its cheapest and most important failure modes are workflow discipline, context management, intake quality, ADR gating, and autonomous execution behavior.

Active run status is tracked in `evaluation/kafka-architecture-investigation/evaluation-tracker.md`. Start there when resuming evaluation work; use this plan for phase details and scoring expectations.

## Watch Surfaces

- `evaluation-tracker.md` is the live cursor: active phase, next action, run log, and short follow-ups only.
- `evaluation-plan.md` is the stable plan: phase intent, gates, prompts, scoring signals, and lessons learned.
- `evaluation-runs/<run-id>/summary.md` is the evidence surface for each model run.
- `evaluation-runs/<run-id>/<case>/` contains raw outputs, prompts, copied docs, and traces for review.

Keep the tracker concise. If a finding needs more than one or two lines, put it in the relevant run summary or this plan and link it from the tracker.

## Cost Strategy

- Run one scenario/model/effort at a time.
- Start with low-cost models: `gpt-5.4-mini` low by default; try `gpt-5.3-codex-spark` low only when it is available and not capacity-limited.
- Use document-only scenarios first. Do not build Kafka, clone Kafka, or run Docker until the cheap workflow checks pass.
- Record seconds, approximate tokens, exit status, and whether the agent respected tracker `Read Now`.
- Escalate to higher reasoning or real Kafka harnesses only when a low-cost model fails for a reason that may be model capacity rather than skill design.

## Robustness Ladder

The evaluation ladder deliberately starts with the cheapest behavior checks and only moves toward real Kafka implementation after the skill proves it can preserve context, resume correctly, and expand work through the intended gates.

| Phase | Scope | Why It Exists | Move On When |
| --- | --- | --- | --- |
| A-repeat-cheap-smokes | Repeat the initial tracker-first intake smoke. | Finds trigger, bootstrap, tracker, and premature-work failures cheaply. | Several clean runs pass with known facts captured and no research/build. |
| B-prompt-variants | Run different Kafka architecture prompts at S01. | Checks the skill is architecture-investigation shaped, not overfit to snapshot restore. | Cluster Linking, transactions, backup-tool, and vague prompts all stay in intake and ask focused questions. |
| C-resume-intake-loop | Resume from partial S01 workspaces. | Tests the high-risk "read tracker first, continue from cursor" behavior. | Existing facts are preserved, missing questions are asked, and S01 is not advanced early. |
| D-adr-scenario-spec-no-kafka | Use fake/simple research fixtures to force S02-S04 without Kafka cost. | Validates the source-research -> ADR -> scenario -> implementation-spec gate. | ADR precedes scenarios, scenarios map to objectives/ADR claims, and specs are small and executable. |
| E-toy-autonomous-loop | Run a shell-testable toy implementation spec. | Checks the self-driven implementation loop without Kafka/Docker cost. | Agent executes, validates, records evidence, updates tracker, and continues until done or blocked. |
| F-small-kafka-golden-path | Run one minimal real Kafka/KRaft path. | Verifies the lab/harness contract against real broker behavior. | Evidence follows `reset -> seed -> capture -> mutate -> start -> assert -> report`. |
| G-historical-complex-benchmark | Re-run one historical complex pattern. | Gives confidence that the skill handles the original class of work. | Output is decision-grade and clearly separates proven, falsified, untested, and uncertain claims. |

## Setup: Static Validation In sbx

Create or reuse a sandbox:

```bash
mkdir -p /tmp/agent-skills-eval
sbx create --name agent-skills-eval --memory 8g --cpus 4 codex /tmp/agent-skills-eval "$(pwd):ro"
```

Validate the skill without model tokens:

- `SKILL.md` frontmatter is valid.
- `agents/openai.yaml` default prompt mentions `$kafka-architecture-investigation`.
- All tracker `Read Now` references resolve to a reference file or template.
- `SCENARIO_MATRIX.tsv` rows have consistent column counts.
- No stale previous skill-name references remain.
- No generated template markers remain.

`quick_validate.py` note: the system `skill-creator` validator depends on `PyYAML`. Do not install it on the host. In sbx, either create a temporary venv and install `pyyaml`, or use a dependency-free local validation script for the subset of checks this repo needs.

Initial sbx observation:

- `agent-skills-eval` was created with `/tmp/agent-skills-eval` writable and this repo mounted read-only.
- Dependency-free static validation passed inside sbx.
- `/Users/jinx/.codex/skills/.system/skill-creator/scripts/quick_validate.py` was not visible inside sbx by default.
- `PyYAML` was not installed inside the sbx Python environment by default.
- Practical next step: add a repo-local static validator or run the official validator from a mounted/copied path inside a temporary sbx venv.
- `codex login status` can return success even when a subsequent `codex exec` fails with API 401. Treat the first model call as an auth validation unless a cheap explicit API probe is added.

Codex auth gate:

- For this evaluation, use ChatGPT-managed Codex auth inside sbx, not API-key auth.
- If `codex login status` reports API-key login, use the auth-sync helper or delete the sandbox auth cache file locally before re-authenticating. Do not run `codex logout` in a sandbox that may contain copied host ChatGPT credentials.
- Preferred human-driven sandbox setup is `codex login --device-auth` from inside the sbx shell.
- Do not set `OPENAI_API_KEY`, `CODEX_API_KEY`, or use `codex login --with-api-key` for subscription-based evals.
- Keep auth state under the sandbox user's `CODEX_HOME`/`~/.codex`.
- `codex login status` must not report API-key login before running this eval.
- The runner can copy host ChatGPT auth into sbx when explicitly requested with `--sync-host-codex-auth`.
- Run a cheap `codex exec --ephemeral` smoke call before expensive scenarios, closing stdin explicitly and satisfying Codex's git-repo guard: `sbx exec agent-skills-eval -- sh -lc 'codex exec --ephemeral --skip-git-repo-check "Reply with: auth ok" < /dev/null'`. `codex login status` is useful but insufficient because it can pass with stale or unusable credentials.
- See `evaluation/sbx-sandbox-pattern/sbx-skill-notes.md` for the future generic sbx skill pattern and official Codex doc links.

First smoke runner attempt:

- Command: `evaluation/kafka-architecture-investigation/run-sbx-smoke.sh`
- Model/effort: `gpt-5.3-codex-spark` / `low`
- Result: blocked before skill execution by sbx Codex auth.
- Evidence: `evaluation/kafka-architecture-investigation/evaluation-runs/20260615-144704/summary.md`
- Error: API 401 with the sandbox-provided `proxy-ma*aged` key, despite `codex login status` passing.
- Harness finding: runner now installs only the skill under test inside sbx and records an explicit `auth_failed` score column.

First auth-sync smoke attempt:

- Command: `evaluation/kafka-architecture-investigation/run-sbx-smoke.sh --sync-host-codex-auth --model gpt-5.3-codex-spark --effort low`
- Result: blocked before skill execution by ChatGPT OAuth token revocation.
- Evidence: `evaluation/kafka-architecture-investigation/evaluation-runs/20260616-110824/summary.md`
- Error: `refresh_token_invalidated` / `token_revoked` after the helper ran `codex logout` inside sbx before copying host auth.
- Harness finding: never run `codex logout` in sbx after host auth has been copied there; delete the sandbox auth cache file locally instead.

First passing tracker smoke:

- Command: `evaluation/kafka-architecture-investigation/run-sbx-smoke.sh --sync-host-codex-auth --model gpt-5.4-mini --effort low`
- Result: passed Phase 1 tracker-first smoke.
- Evidence: `evaluation/kafka-architecture-investigation/evaluation-runs/20260616-115218/summary.md`
- Model/effort: `gpt-5.4-mini` / `low`
- Tokens: `14532`
- Behavior: created tracker, investigation brief, and reference architecture only; captured known KRaft and reduced-broker facts; asked four focused intake questions; did not research docs/source or build scenarios/harnesses.
- Harness finding: the summary TSV writer needed one extra field after adding `known_facts_captured`; fixed after this run.

## Phase A: Repeat Cheap Smokes

Runner:

```bash
evaluation/kafka-architecture-investigation/run-sbx-smoke.sh \
  --sync-host-codex-auth \
  --model gpt-5.4-mini \
  --effort low
```

The runner installs only `kafka-architecture-investigation` inside sbx before running Codex.

Prompt:

```text
Use $kafka-architecture-investigation to start investigating this Kafka architecture question in {{TARGET_DIR}}: can we restore a Kafka snapshot into a smaller local recovery cluster? I only know that the source was KRaft and the target has fewer brokers. Do not research yet; start the investigation properly.
```

Expected:

- Skill triggers.
- Creates `docs/kafka-architecture-investigation/TRACKER.md`.
- Reads/uses the tracker before other project investigation files.
- Creates only S01-needed docs: `INVESTIGATION_BRIEF.md` and `REFERENCE_ARCHITECTURE.md`.
- Asks at least one and no more than five focused questions.
- Does not clone Kafka, browse docs, create Compose files, or write scenarios.

Repeat the smoke until there is enough confidence that failures are not one-off model variance. A useful target is three clean passes after the latest skill/harness change, not counting runs that exposed a bug subsequently fixed.

## Phase B: Prompt Variants

Runner:

```bash
evaluation/kafka-architecture-investigation/run-phase-b-variant.sh cluster-linking --sync-host-codex-auth
evaluation/kafka-architecture-investigation/run-phase-b-variant.sh transactions --sync-host-codex-auth
evaluation/kafka-architecture-investigation/run-phase-b-variant.sh backup-tool --sync-host-codex-auth
evaluation/kafka-architecture-investigation/run-phase-b-variant.sh vague --sync-host-codex-auth
```

Expected:

- Skill triggers for different Kafka architecture investigation shapes.
- Captures the facts already present in the prompt.
- Keeps unknowns explicit instead of inventing source estate or target state.
- Asks 1-5 focused intake questions.
- Does not research docs/source, write ADRs/scenarios/specs, or create harness files.

## Phase C: Resume Intake Loop

Runner:

```bash
evaluation/kafka-architecture-investigation/run-phase-c-resume.sh \
  --sync-host-codex-auth \
  --model gpt-5.4-mini \
  --effort low
```

Cases:

- `partial-s01`: existing source/target facts are preserved, S01 stays `in_progress`, and the agent asks 1-5 missing intake questions.
- `ready-s01`: complete S01 facts are already present, so the agent marks S01 `done`, moves the cursor to S02, and stops before source research.

Prompt starts from a workspace with S01 incomplete and partial user answers.

Expected:

- Updates brief and architecture.
- Records unknowns as assumptions only when safe.
- Continues asking 1-5 focused questions if the research-ready gate is still blocked.
- Marks S01 done only when source estate, target state, acceptability boundaries, constraints, evidence needs, and tracks are present or explicitly assumed.
- For step transitions, uses the deterministic tracker updater so Current Cursor keeps the full destination `Read Now` list.

## Phase D: ADR And Scenario/Spec Without Kafka

This phase should be split into cheap document-only cases before any Kafka/Docker work:

1. `S02-source-research`: prompt starts from S01 done and S02 pending.
2. `S03-adr-gate`: prompt starts from S02 done and S03 pending.
3. `S04-scenario-spec`: prompt starts from S03 done and S04 pending.

Prompt starts from a workspace with S01 done and S02 pending.

Expected:

- Reads only tracker S02 `Read Now` files.
- Produces `SOURCE_RESEARCH.md`.
- Uses docs/source research language.
- Does not expand scenarios or build harness.
- If a missing policy fact appears, returns to user synchronization instead of guessing.

Prompt starts from S02 done and S03 pending.

Expected:

- Writes `ADR.md`.
- Combines user context, source claims, options, decision, consequences, and light scenario coverage.
- Does not write detailed scenario specs until the ADR completion gate is satisfied.

Prompt starts from S03 done and S04 pending.

Expected:

- Writes `SCENARIO_MATRIX.tsv` with objective and ADR claim mappings.
- Writes `IMPLEMENTATION_SPEC.md` with small ordered steps and validation gates.
- Every implemented scenario has deterministic construction or is explicitly `nondeterministic`.

## Phase E: Toy Autonomous Loop

Prompt starts from S04 done with a toy implementation spec that can be completed without Kafka.

Expected:

- Starts from the first non-`done` implementation step.
- Executes one step, validates it, updates evidence/status, and continues.
- Stops only when all steps are done or a real stop condition is recorded.
- Updates `TRACKER.md` after each loop pass.

## Phase F: Small Kafka Golden Path

Only after phases A-E pass, run a small Kafka-like or real Kafka task:

- A tiny local KRaft lab.
- One baseline scenario.
- One deterministic mutation scenario that does not require real production-sized snapshot data.

Expected:

- Fixed doc/script/artifact paths.
- `reset -> seed -> capture -> mutate -> start -> assert -> report` shape.
- Evidence recorded under `artifacts/kafka-architecture-investigation/`.

## Phase G: Historical Complex Benchmark

Use one of the historical patterns as an expensive benchmark only after cheap tests pass:

- reduced-broker snapshot recovery
- cluster-linking cutover
- transactional migration behavior
- backup-tooling comparison

This run is expected to be long and token-heavy. It is for confidence, not quick regression.

## Scoring Signals

Record per run:

- trigger: pass/fail
- tracker-first: pass/fail
- `Read Now` respected: pass/fail/unclear
- question count: number
- premature research/build: yes/no
- ADR before scenarios: yes/no
- objective-to-scenario mapping: pass/fail
- autonomous loop behavior: pass/fail
- fixed paths used: pass/fail
- final answer useful: pass/fail
- seconds
- approximate tokens/cost when available
