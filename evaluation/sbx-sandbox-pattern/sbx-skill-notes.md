# sbx Sandbox Skill Notes

These notes capture patterns for a future generic `sbx` skill. The goal is to isolate code compilation, dependency installation, and agent-driven evaluation from the host machine to reduce supply-chain exposure and keep local developer environments clean.

## Why Use sbx

- Install third-party dependencies inside a disposable sandbox instead of the host.
- Compile untrusted or unfamiliar code away from the main machine.
- Run model/agent evaluations with bounded writable state.
- Mount source repositories read-only when the agent only needs to inspect or install from them.
- Reuse a named sandbox when setup is expensive, but reset or recreate it when trust boundaries change.

## Basic Pattern

Create a writable scratch workspace and mount the repo read-only:

```bash
mkdir -p /tmp/agent-skills-eval
sbx create --name agent-skills-eval --memory 8g --cpus 4 codex /tmp/agent-skills-eval /path/to/repo:ro
```

Run commands inside the sandbox:

```bash
sbx exec agent-skills-eval -- sh -lc 'pwd && ls'
```

Run an agent inside the sandbox:

```bash
sbx run agent-skills-eval
```

## Dependency Safety Pattern

- Prefer installing packages inside the sandbox.
- Prefer temporary venvs inside the sandbox for Python tooling such as `PyYAML`.
- Do not install evaluation-only dependencies on the host unless the user explicitly chooses that.
- Keep downloaded dependencies, build caches, and generated artifacts inside the sandbox workspace.
- Copy only intentional outputs back to the host.

## Skill Evaluation Pattern

- Mount the skill repo read-only.
- Clear the sandbox user skill directory before each run, then copy only the skill or skills under test into the sandbox agent skill directory.
- Run one model/scenario at a time unless ports and resource names are isolated.
- Capture prompts, final responses, traces, generated files, and summaries under an ignored `evaluation-runs/` directory.
- Clean up generated containers and files after each run unless preserving evidence.

## Common Failure Modes

- Agent cannot see the repo path because the host path was not mounted into sbx.
- System-local agent files such as `~/.codex/skills/.system/...` are not visible unless explicitly mounted.
- Agent is not authenticated inside the sandbox.
- Agent auth status may be stale: `codex login status` can pass while the first `codex exec` call fails with API 401.
- Python packages available on the host, such as `PyYAML`, may be missing inside the sandbox.
- Docker or Docker Compose behavior differs across `sbx exec` calls.
- Model runs leave containers or generated files behind.
- Scripts assume host paths that do not exist inside the sandbox.
- Agents install dependencies on the host because the prompt does not explicitly say to use sbx.

## Future Skill Shape

Potential skill name: `sbx-isolated-build`.

Scope:

- Set up or reuse named sbx sandboxes.
- Mount repos read-only or writable depending on task.
- Run dependency installation, compilation, tests, and agent evaluations inside sbx.
- Use temporary in-sandbox venvs for validation tools and throw them away after use.
- Preserve or export selected artifacts.
- Record sandbox setup decisions and cleanup commands.

Out of scope:

- Claiming sbx is a perfect security boundary.
- Running production secrets or sensitive data in sandbox by default.
- Hiding network access or dependency download behavior from the user.
