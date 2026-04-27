# kafka-local-lab Evaluation Results

These are historical validation notes from the initial workshop extraction. The run commands have been updated to the publishable repository layout, but generated `evaluation-runs/` artifacts are intentionally not committed.

## Run 1: Happy Path, gpt-5.5, sbx

Date: 2026-04-26

Sandbox: `kafka-local-lab-eval`

Prompt:

```text
Use kafka-local-lab to create a quick local Kafka lab in /tmp/kafka-lab-test.nNO0S5. Use the defaults.
```

Result: pass.

Observed behavior:

- The skill triggered and loaded `SKILL.md`.
- The agent did not ask unnecessary questions.
- The agent checked Docker resources and host ports.
- The agent used `scripts/create-lab.sh` to create the target lab directory.
- The agent started Docker Compose.
- The agent ran `scripts/smoke-test.sh`.
- The smoke test passed:
  - Kafka became ready.
  - Topic `lab-smoke-test` was created.
  - One message was produced.
  - The same message was consumed back.
- The final response included:
  - Lab directory.
  - Host bootstrap address.
  - Docker-network bootstrap addresses.
  - Smoke-test status.
  - Stop and cleanup commands.

Created files inside the sandbox:

```text
/tmp/kafka-lab-test.nNO0S5/docker-compose.yml
/tmp/kafka-lab-test.nNO0S5/scripts/smoke-test.sh
```

Smoke-test output excerpt:

```text
Kafka smoke test passed
Bootstrap servers: kafka-1:19092,kafka-2:19092,kafka-3:19092
Topic: lab-smoke-test
```

Notes:

- The agent first attempted a port check with `ss`, which was not installed in the sandbox. It noticed the issue and reran with a fallback.
- This suggests the skill should eventually include a deterministic preflight script instead of asking each model to invent port checks.
- The agent read full script contents before running them. This is acceptable for now but may be wasteful; a stronger `SKILL.md` could tell agents to run bundled scripts directly unless debugging.
- The generated lab worked during the Codex run. Subsequent external `sbx exec` calls restarted the sandbox Docker daemon and showed the containers exited with code 255. This appears to be an `sbx` execution-environment behavior, not a skill failure.
- The lab was cleaned up with `docker compose down -v`.

Potential improvements before model-matrix testing:

- Done: added `scripts/preflight.sh` to check Docker, Docker Compose, Docker exec, resources, and required ports consistently.
- Done: updated `SKILL.md` to prefer running bundled scripts directly rather than reading full script bodies first.
- Consider adding configurable host ports before running parallel model tests.

## Run 2: Happy Path After Preflight, gpt-5.5, sbx

Date: 2026-04-26

Sandbox: `kafka-local-lab-eval`

Prompt:

```text
Use kafka-local-lab to create a quick local Kafka lab in /tmp/kafka-lab-test-preflight.rv6V34. Use the defaults.
```

Result: pass.

Observed behavior:

- The skill triggered and loaded `SKILL.md`.
- The agent did not ask unnecessary questions.
- The agent used `scripts/create-lab.sh`.
- The generated lab included:
  - `docker-compose.yml`
  - `scripts/preflight.sh`
  - `scripts/smoke-test.sh`
- The agent ran `./scripts/preflight.sh` before startup.
- The agent started Docker Compose.
- The agent ran `./scripts/preflight.sh --check-exec` after startup.
- The agent ran `./scripts/smoke-test.sh`.
- The smoke test passed.
- The final response included:
  - Lab directory.
  - Host bootstrap address.
  - Docker-network bootstrap addresses.
  - Smoke-test status.
  - Stop and cleanup commands.

Smoke-test output excerpt:

```text
Kafka smoke test passed
Bootstrap servers: kafka-1:19092,kafka-2:19092,kafka-3:19092
Topic: lab-smoke-test
```

Notes:

- The agent no longer invented its own port-check logic.
- The agent did not read full script bodies before normal use.
- The lab was cleaned up with `docker compose down -v`.

## Run 3: Matrix Harness Smoke, gpt-5.4-mini low, sbx

Date: 2026-04-26

Sandbox: `kafka-local-lab-eval`

Command:

```bash
MODELS="gpt-5.4-mini" EFFORTS="low" \
  evaluation/kafka-local-lab/run-model-matrix.sh
```

Result: pass.

Summary file:

```text
evaluation/kafka-local-lab/evaluation-runs/20260426-195906/summary.md
```

Observed behavior:

- The harness refreshed the skill inside the sandbox before running Codex.
- The installed skill copy excluded evaluation files and prior run logs.
- The model used `scripts/create-lab.sh`.
- The model ran `./scripts/preflight.sh`, `docker compose up -d`, `./scripts/preflight.sh --check-exec`, and `./scripts/smoke-test.sh`.
- The smoke test passed.
- The final response included host bootstrap, Docker-network bootstrap, smoke status, stop command, and cleanup command.
- The model did not read full script bodies during normal use.

Scored result:

```text
model          effort  result  seconds  tokens  create  preflight  smoke-script  smoke-passed  read-script-body
gpt-5.4-mini  low     pass    40       8456    yes     yes        yes           yes           no
```

Notes:

- `codex exec` writes the rich event trace to stderr and the final response to stdout. The harness now combines both into `trace.log` before scoring.
- The first harness attempt was a false negative because it assumed the host evaluation directory was mounted at `/home/agent/workspace`. The harness now writes prompts and reads final artifacts through `sbx exec`, so it does not depend on host-path visibility.
- `sbx` can leave Compose containers in an exited state when the Docker daemon restarts between exec calls. The harness cleanup now falls back to removing containers by the Compose `working_dir` label and normalized Compose project name after `docker compose down -v`.

## Model Availability Check

Date: 2026-04-26

Sandbox: `kafka-local-lab-eval`

Confirmed with minimal `codex exec` prompts:

- `gpt-5.2`: available.
- `gpt-5.3-codex-spark`: available.

The default matrix now includes:

```text
gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex-spark gpt-5.2
```

`gpt-5.3-codex-spark` is the lowest/faster Codex-specific candidate tested so far.

## Run 4: Full Model Matrix, sbx

Date: 2026-04-26

Sandbox: `kafka-local-lab-eval`

Command:

```bash
evaluation/kafka-local-lab/run-model-matrix.sh \
  --models "gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex-spark gpt-5.2" \
  --efforts "low medium high xhigh"
```

Result: 20/20 pass.

Summary file:

```text
evaluation/kafka-local-lab/evaluation-runs/20260426-203352/summary.md
```

All runs:

- exited with code `0`;
- used `scripts/create-lab.sh`;
- used `scripts/preflight.sh`;
- used `scripts/smoke-test.sh`;
- passed the Kafka smoke test;
- did not read full script bodies during normal use;
- included host bootstrap, Docker-network bootstrap, and cleanup commands in the final response.

Average by model:

```text
model                 avg_seconds  avg_tokens
gpt-5.3-codex-spark   33.25        8134.50
gpt-5.4-mini          45.75        11546.75
gpt-5.5               51.75        21647.75
gpt-5.4               61.75        13552.00
gpt-5.2               70.75        6983.50
```

Average by reasoning effort:

```text
effort   avg_seconds  avg_tokens
low      46.80        13528.60
medium   53.40        12828.00
high     51.60        12045.60
xhigh    58.80        11089.40
```

Fastest individual runs:

```text
gpt-5.3-codex-spark  low     31s  10608 tokens
gpt-5.3-codex-spark  medium  34s  7672 tokens
gpt-5.3-codex-spark  high    34s  7201 tokens
gpt-5.3-codex-spark  xhigh   34s  7057 tokens
```

Lowest-token individual runs:

```text
gpt-5.2               low     65s  5698 tokens
gpt-5.3-codex-spark   xhigh   34s  7057 tokens
gpt-5.3-codex-spark   high    34s  7201 tokens
gpt-5.2               high    61s  7205 tokens
```

Interpretation:

- For this happy-path skill flow, `gpt-5.3-codex-spark` is the best candidate so far: fastest average runtime, all passes, and no skill-contract misses.
- `gpt-5.2` used the fewest tokens, but it was the slowest model on average.
- Higher reasoning did not improve pass rate because the task is already script-driven and tightly specified.
- Do not overinterpret token ordering across reasoning levels; the measured tokens include the CLI trace and model behavior variance, not only useful reasoning.
- Post-run check showed no full-matrix containers left running. An older pre-harness test container set named `kafka-lab-testnno0s5-*` still reappears in `sbx` after Docker daemon restarts, which appears to be sandbox state behavior rather than a matrix-run leak.

## Run 5: Claude Code Matrix, sbx

Date: 2026-04-26

Sandbox: `kafka-local-lab-eval`

Command:

```bash
evaluation/kafka-local-lab/run-model-matrix.sh --runner claude
```

Result: 4/4 pass.

Summary file:

```text
evaluation/kafka-local-lab/evaluation-runs/20260426-214521/summary.md
```

All runs:

- used the same `kafka-local-lab` skill source, installed into `/home/agent/.claude/skills/kafka-local-lab`;
- used Claude Code slash-skill invocation;
- used `create-lab.sh`, `preflight.sh`, and `smoke-test.sh`;
- passed the Kafka smoke test;
- did not read full script bodies during normal use;
- included host bootstrap, Docker-network bootstrap, and cleanup commands in the final response.

Results:

```text
model   effort  result  seconds  tokens   cost_usd
haiku   low     pass    38       232088   0.043611
haiku   medium  pass    36       230667   0.041111
sonnet  low     pass    55       153761   0.097028
sonnet  medium  pass    47       154233   0.097486
```

Average by model:

```text
model   avg_seconds  avg_tokens  avg_cost_usd
haiku   37.00        231377.50   0.042361
sonnet  51.00        153997.00   0.097257
```

Notes:

- Claude text output hides tool calls, so the harness now uses `--output-format stream-json --verbose` for Claude runs and extracts final text from the `result` event.
- Claude runs use `CLAUDE_PERMISSION_MODE=bypassPermissions` by default because `dontAsk` stops to request Bash permission.
- Haiku is the better Claude default for this happy path so far: all passes, lower average runtime, and less than half the average cost of Sonnet.
- `sbx` still shows some exited/dead Compose containers after Docker daemon restarts, including Claude matrix containers. This appears to be the same sandbox state issue observed in earlier runs, not an active lab leak.

## Run 6: Optional Component Expansion, sbx

Date: 2026-04-26

Sandbox: `kafka-local-lab-eval`

Scope:

- Added Confluent Kafka KRaft Compose support.
- Added optional Confluent Schema Registry.
- Added optional Kafka Connect with the bundled FileStream source connector.
- Added optional AKHQ UI.
- Updated `preflight.sh` to check extra host ports from generated `.env`.
- Updated `smoke-test.sh` to verify option-specific behavior:
  - Schema Registry registers an Avro schema and reads it back.
  - Kafka Connect creates a FileStream source connector, appends a line, and consumes it from Kafka.
  - AKHQ responds over HTTP.
- Updated the matrix harness to capture generated `.env`/Compose files and score requested options.

Direct runtime checks:

```text
confluent-only                              pass
confluent + schema-registry                 pass
confluent + kafka-connect                   pass
confluent + akhq                            pass
confluent + schema-registry + connect + akhq pass
```

Focused Codex harness checks:

```text
run set          prompt option       model           effort  result  seconds  option proof
20260426-222851  confluent           gpt-5.4-mini    low     pass    48       STACK=confluent
20260426-223332  schema-registry     gpt-5.4-mini    low     pass    45       schema smoke passed
20260426-223558  kafka-connect       gpt-5.4-mini    low     pass    78       FileStream smoke passed
20260426-223851  akhq                gpt-5.4-mini    low     pass    45       AKHQ smoke passed
```

Full-stack cross-runner checks:

```text
runner  run set          model           effort  result  seconds  tokens   cost_usd
codex   20260426-224121  gpt-5.4-mini    low     pass    80       24995    unknown
claude  20260426-224509  haiku           low     pass    72       238903   0.046426
```

Both full-stack runs generated:

```text
STACK=confluent
WITH_SCHEMA_REGISTRY=1
WITH_CONNECT=1
UI=akhq
REQUIRED_HOST_PORTS="29092 39092 49092 8081 8083 8080"
```

Notes:

- A first Claude full-stack run was a false negative in the harness because the final cleanup command used `docker compose -f <file> down -v`; the scorer only recognized literal `docker compose down`. The harness now accepts both forms.
- A direct Schema Registry rerun briefly hit an `sbx` Docker storage issue (`RWLayer ... unexpectedly nil`) when reusing an old Compose project name. Using unique target directories avoided the stale-project artifact, which matches how the harness already operates.
- No Spark model was used for these iteration checks.

## Run 7: Scenario-Aware Harness Update, sbx

Date: 2026-04-26

Sandbox: `kafka-local-lab-eval`

Scope:

- Replaced prompt-grep scoring as the primary path with explicit harness scenarios.
- Added `--scenarios` and `SCENARIOS`.
- Built-in scenarios:
  - `default`: Apache Kafka, no extras.
  - `confluent`: Confluent Kafka, no extras.
  - `schema-registry`: Confluent Kafka plus Schema Registry.
  - `connect`: Confluent Kafka plus Kafka Connect.
  - `akhq`: Confluent Kafka plus AKHQ.
  - `full`: Confluent Kafka plus Schema Registry, Kafka Connect, and AKHQ.
- Kept `PROMPT_TEXT` as a `custom` scenario path for ad hoc natural-language probes.
- Added expected-vs-generated columns to `summary.tsv` and `summary.md`.

Validation:

```text
run set          scenario  model           effort  result  expected                         generated
20260426-230341  full      gpt-5.4-mini    low     pass    confluent + schema/connect/akhq  confluent + schema/connect/akhq
20260426-230526  default   gpt-5.4-mini    low     pass    apache + no extras              apache + no extras
```

Example commands:

```bash
evaluation/kafka-local-lab/run-model-matrix.sh \
  --runner codex \
  --scenarios "default full" \
  --models "gpt-5.4-mini" \
  --efforts "low"
```

```bash
evaluation/kafka-local-lab/run-model-matrix.sh \
  --runner claude \
  --scenarios "default full" \
  --models "haiku" \
  --efforts "low"
```

Notes:

- This makes the harness safer for regressions: a model can no longer pass a Schema Registry scenario by only creating a base Kafka lab whose generic smoke test succeeds.
- No Spark model was used for this harness review.

## Run 8: Cross-Runner Scenario Sweep, sbx

Date: 2026-04-26

Sandbox: `kafka-local-lab-eval`

Commands:

```bash
evaluation/kafka-local-lab/run-model-matrix.sh \
  --runner codex \
  --scenarios "default confluent schema-registry connect akhq full" \
  --models "gpt-5.4-mini" \
  --efforts "low"
```

```bash
evaluation/kafka-local-lab/run-model-matrix.sh \
  --runner claude \
  --scenarios "default confluent schema-registry connect akhq full" \
  --models "haiku" \
  --efforts "low"
```

Result: 12/12 pass.

Summary files:

```text
evaluation/kafka-local-lab/evaluation-runs/20260426-230907/summary.md
evaluation/kafka-local-lab/evaluation-runs/20260426-231701/summary.md
```

Codex results:

```text
scenario         model           effort  result  seconds
default          gpt-5.4-mini    low     pass    41
confluent        gpt-5.4-mini    low     pass    44
schema-registry  gpt-5.4-mini    low     pass    44
connect          gpt-5.4-mini    low     pass    77
akhq             gpt-5.4-mini    low     pass    58
full             gpt-5.4-mini    low     pass    99
```

Claude results:

```text
scenario         model   effort  result  seconds  cost_usd
default          haiku   low     pass    56       0.042759
confluent        haiku   low     pass    46       0.042079
schema-registry  haiku   low     pass    62       0.044797
connect          haiku   low     pass    73       0.036232
akhq             haiku   low     pass    47       0.043187
full             haiku   low     pass    77       0.044769
```

Totals:

```text
runner  cells  total_seconds  total_cost_usd
codex   6      363            unknown
claude  6      361            0.253823
```

All cells matched expected generated config exactly and passed the required smoke checks. No Spark model was used.

## Run 9: Repo-Local Packaging Harness Check, sbx

Date: 2026-04-27

Sandbox: `agent-skills-eval`

Scope:

- Created a fresh `agent-skills-eval` sandbox with the publishable `agent-skills` repo mounted read-only.
- Verified `skills/kafka-local-lab/SKILL.md` is visible inside the sandbox.
- Fixed sandbox Codex auth by removing the stale API-key login and completing `codex login --device-auth`.
- Verified `codex login status` reports ChatGPT authentication.
- Ran the repo-local harness against the default scenario.

Command:

```bash
evaluation/kafka-local-lab/run-model-matrix.sh \
  --runner codex \
  --scenarios "default" \
  --models "gpt-5.4-mini" \
  --efforts "low"
```

Result:

```text
run set          scenario  model           effort  result  seconds
20260427-000033  default   gpt-5.4-mini    low     pass    69
```

Notes:

- This confirms the extracted repo layout and repo-local `SKILL_SOURCE` work.
- Generated `evaluation-runs/` artifacts remain ignored and were not added to the publishable file set.

## Run 10: Manual UI Feedback Fixes

Date: 2026-04-27

Scope:

- Updated `SKILL.md` so normal interactive use asks for confirmation before creating or starting a lab, while automated harness prompts explicitly opt into non-interactive execution.
- Fixed `preflight.sh --check-exec` so post-start validation does not re-check host ports that the running Kafka containers have already bound.

Validation:

```bash
bash -n skills/kafka-local-lab/scripts/create-lab.sh
bash -n skills/kafka-local-lab/scripts/preflight.sh
bash -n skills/kafka-local-lab/scripts/smoke-test.sh
bash -n evaluation/kafka-local-lab/run-model-matrix.sh
```

Post-start preflight was also validated against the running manual UI-test lab:

```bash
./skills/kafka-local-lab/scripts/preflight.sh \
  --check-exec \
  --project-dir /Users/jinx/gits/jinx/tests-and-stuff/kafka-local-lab \
  --compose-file /Users/jinx/gits/jinx/tests-and-stuff/kafka-local-lab/docker-compose.yml
```

Result:

```text
[preflight] Checking docker compose exec against kafka-1
[preflight] Preflight checks passed
```

Full fresh-lab validation was not rerun in this pass because the manual UI-test lab was still occupying the default host ports.

## Run 11: Public Release Baseline

Date: 2026-04-27

Sandbox: `agent-skills-eval`

Scope:

- Added runner preflight checks to fail fast when Codex or Claude is missing or unauthenticated inside the sandbox.
- Ran the full built-in scenario set for Codex and Claude without using Spark.
- Added the MIT license before making the repository public.

Commands:

```bash
evaluation/kafka-local-lab/run-model-matrix.sh \
  --runner codex \
  --scenarios "default confluent schema-registry connect akhq full" \
  --models "gpt-5.4-mini" \
  --efforts "low"
```

```bash
evaluation/kafka-local-lab/run-model-matrix.sh \
  --runner claude \
  --scenarios "default confluent schema-registry connect akhq full" \
  --models "haiku" \
  --efforts "low"
```

Codex results:

```text
run set          scenario         model           effort  result  seconds
20260427-003000  default          gpt-5.4-mini    low     pass    36
20260427-003000  confluent        gpt-5.4-mini    low     pass    41
20260427-003000  schema-registry  gpt-5.4-mini    low     pass    62
20260427-003000  connect          gpt-5.4-mini    low     pass    86
20260427-003000  akhq             gpt-5.4-mini    low     pass    53
20260427-003000  full             gpt-5.4-mini    low     pass    96
```

Claude results:

```text
run set          scenario         model  effort  result  seconds  cost_usd
20260427-011514  default          haiku  low     pass    40       0.043192
20260427-011514  confluent        haiku  low     pass    49       0.050588
20260427-011514  schema-registry  haiku  low     pass    41       0.044060
20260427-011514  connect          haiku  low     pass    69       0.046140
20260427-011514  akhq             haiku  low     pass    42       0.045129
20260427-011514  full             haiku  low     pass    74       0.055304
```

Totals:

```text
runner  cells  total_seconds  total_tokens  total_cost_usd
codex   6      374            100981        unknown
claude  6      315            1515809       0.284413
```

All release baseline cells matched expected generated config and passed the required smoke checks.
