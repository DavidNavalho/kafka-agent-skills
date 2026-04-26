# kafka-local-lab sbx Evaluation Plan

Purpose: forward-test `kafka-local-lab` in a clean sandbox so the skill succeeds because its files are sufficient, not because this conversation contains the design context.

## Phase 1: Prepare the sandbox

- [ ] Create a clean host workspace at `/tmp/agent-skills-eval`.
- [ ] Create an `sbx` Codex sandbox named `agent-skills-eval`.
- [ ] Mount `/tmp/agent-skills-eval` as the writable workspace.
- [ ] Mount this repository read-only for skill installation inside the sandbox.
- [ ] Confirm the sandbox can run Docker and Docker Compose.
- [ ] Confirm the sandbox can run Codex.
- [ ] Complete Codex or Claude login inside the sandbox if required.

Auth state is environment-specific. Check it inside the sandbox with `codex login status` or the corresponding runner command before starting a model matrix.

Sandbox creation command used:

```bash
sbx create \
  --name agent-skills-eval \
  --memory 8g \
  --cpus 4 \
  codex \
  /tmp/agent-skills-eval \
  <repo>:ro
```

Then verify:

```bash
sbx exec agent-skills-eval -- sh -lc \
  'test -f <repo>/skills/kafka-local-lab/SKILL.md && docker compose version'
```

## Phase 2: Install and discover the skill

- [x] Copy or symlink the skill into the sandbox Codex skills directory.
- [x] Start a fresh Codex session in the sandbox.
- [x] Use a natural user prompt, not leaked design context.
- [x] Confirm the skill triggers from metadata alone.

## Phase 3: Happy-path evaluation

Prompt:

```text
Use kafka-local-lab to create a quick local Kafka lab in /tmp/kafka-lab-test. Use the defaults.
```

Success criteria:

- [x] The agent avoids unnecessary questions.
- [x] The agent uses `scripts/create-lab.sh`.
- [x] The agent checks Docker availability and required ports.
- [x] The agent starts Docker Compose.
- [x] The agent runs `scripts/smoke-test.sh`.
- [x] The smoke test passes.
- [x] The final response includes host bootstrap, Docker-network bootstrap, stop command, and cleanup command.

Run 1 result: pass. See `evaluation-results.md`.

## Phase 4: Optional component evaluation

- [x] Confluent Kafka-only lab.
- [x] Confluent Kafka with Schema Registry.
- [x] Confluent Kafka with Kafka Connect.
- [x] Confluent Kafka with AKHQ UI.
- [x] Full Confluent Kafka lab with Schema Registry, Kafka Connect, and AKHQ UI.

Each option must pass direct runtime validation and at least one focused harness run.

## Phase 5: Negative-path evaluation

Later prompts:

- Required host port is already occupied.
- User asks which bootstrap address to use from a host app versus a container app.
- Docker `exec` is not available even though Docker inspection works.
- User asks for unsupported security modes such as SASL, TLS, or ACLs.

## Phase 6: Model comparison

Run the same prompts in separate clean workspaces for each model. Do not run in parallel unless the compose ports are made configurable.

Use the Codex matrix harness from the repository root:

```bash
evaluation/kafka-local-lab/run-model-matrix.sh \
  --runner codex \
  --scenarios "default full" \
  --models "gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex-spark gpt-5.2" \
  --efforts "low medium high xhigh"
```

The harness:

- refreshes the installed skill inside the `sbx` sandbox before the run;
- installs only runtime skill files into the runner-specific skill directory: Codex uses `.codex/skills`, Claude uses `.claude/skills`;
- runs one scenario/model/reasoning cell at a time because the labs use fixed host ports;
- captures `prompt.txt`, `final.md`, `trace.log`, raw stdout/stderr logs, generated artifacts, `summary.tsv`, and `summary.md`;
- captures generated `.env` and `docker-compose.yml` for option-specific scoring;
- supports first-class scenarios: `default`, `confluent`, `schema-registry`, `connect`, `akhq`, and `full`;
- gates each built-in scenario against exact expected generated config plus matching smoke-test output;
- records `cost_usd` when the runner exposes stable cost data;
- cleans each generated lab with `docker compose down -v` unless `--keep-labs` is set.

Default model set:

- `gpt-5.5`
- `gpt-5.4`
- `gpt-5.4-mini`
- `gpt-5.3-codex-spark`
- `gpt-5.2`

`gpt-5.3-codex-spark` is included as the lowest/faster Codex-specific candidate confirmed available in the sandbox. `gpt-5.2` is included to compare against an older general model.

Claude comparison uses the same harness with Claude-only defaults:

```bash
evaluation/kafka-local-lab/run-model-matrix.sh --runner claude
```

Claude defaults:

- Models: `haiku sonnet`
- Efforts: `low medium`
- Permission mode: `bypassPermissions`, because the evaluation runs inside an isolated `sbx` sandbox and must be non-interactive.

The default prompt can be overridden with `PROMPT_TEXT`. Use `{{TARGET_DIR}}` where the harness should insert the generated lab directory:

```bash
PROMPT_TEXT='Use kafka-local-lab to create a default lab in {{TARGET_DIR}} and report the connection details.' \
  evaluation/kafka-local-lab/run-model-matrix.sh \
  --scenarios custom \
  --models "gpt-5.4-mini" \
  --efforts "low"
```

Prefer built-in scenarios for regular regression runs. Use `PROMPT_TEXT` with `--scenarios custom` only for one-off natural-language probes, because custom scoring can only infer explicit requested options from the prompt text.
