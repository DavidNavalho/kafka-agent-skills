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

## Codex Subscription Auth Pattern

Use ChatGPT-managed Codex authentication inside sbx when the evaluation should consume the user's ChatGPT/Codex subscription or workspace entitlement rather than API usage.

Official Codex docs distinguish these modes:

- ChatGPT sign-in: subscription/workspace access, with ChatGPT workspace permissions and policies.
- API key sign-in: usage-based Platform billing, with API org policies.
- The CLI defaults to ChatGPT sign-in when no valid session exists.
- For headless or remote shells, use device-code login: `codex login --device-auth`.
- For trusted Business/Enterprise automation, Codex access tokens can provide ChatGPT-managed local Codex access without browser login.

Recommended sbx workflow:

1. Keep Codex state inside the sandbox user's `CODEX_HOME`/`~/.codex`; do not mount the host `~/.codex` wholesale into an untrusted sandbox.
2. If `codex login status` says the sandbox is logged in with an API key, run `codex logout` inside sbx first.
3. Open a shell in the sandbox and run `codex login --device-auth`, then complete the browser/device-code flow outside the sandbox.
4. Avoid `codex login --with-api-key`, `OPENAI_API_KEY`, and `CODEX_API_KEY` when the objective is subscription-based auth.
5. If copying host subscription auth into sbx is necessary, treat `auth.json` as a secret, copy only that file, and ensure it is not captured in eval artifacts, logs, commits, or prompts:

   ```bash
   sbx exec agent-skills-eval -- sh -lc 'mkdir -p "$HOME/.codex"; umask 077; cat > "$HOME/.codex/auth.json"' < "$HOME/.codex/auth.json"
   ```

   Prefer this narrow copy over mounting the whole host `~/.codex` directory.
6. For repeatable trusted automation, prefer a Codex access token where the workspace supports it; store it in a secret manager and rotate it.
7. Verify with `codex login status`; it must not report API-key login for subscription-based evals.
8. Run a tiny `codex exec --ephemeral` smoke call before starting expensive evaluations. Close stdin explicitly and satisfy Codex's git-repo guard for prompt-argument smoke calls, for example `sbx exec agent-skills-eval -- sh -lc 'codex exec --ephemeral --skip-git-repo-check "Reply with: auth ok" < /dev/null'`. `login status` only proves credentials are present; stale or wrong credentials can still fail on the first model request.

Useful official references:

- `https://developers.openai.com/codex/auth`
- `https://developers.openai.com/codex/noninteractive`
- `https://developers.openai.com/codex/enterprise/access-tokens`
- `https://developers.openai.com/codex/environment-variables`

## Common Failure Modes

- Agent cannot see the repo path because the host path was not mounted into sbx.
- System-local agent files such as `~/.codex/skills/.system/...` are not visible unless explicitly mounted.
- Agent is not authenticated inside the sandbox.
- Agent is authenticated with an API key inside the sandbox when the eval requires ChatGPT/subscription auth.
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
