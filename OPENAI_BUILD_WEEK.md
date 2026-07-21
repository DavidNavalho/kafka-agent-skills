# OpenAI Build Week — agent setup and evaluation

This is the single agent-facing entry point for installing and testing the
[`run-agents-in-sbx`](skills/run-agents-in-sbx/SKILL.md) skill. A judge can point a
local coding agent at this file and ask it to follow the instructions.

## Judge instruction

Give your agent this request:

> Follow `OPENAI_BUILD_WEEK.md` from the repository root. Ask me which evaluation
> route I authorize before installing anything or using authentication.

The authenticated route is the primary test: it runs real Codex sessions inside
Docker `sbx` against generated, trusted fixtures. The alternative is a
credential-free mock regression that tests the lifecycle without a real sandbox,
model call, or credential.

## Agent instruction

Your goal is to install the repository skill and run exactly one judge-approved
evaluation route. Stay in the repository root, do not commit or push, and do not
inspect ignored raw evaluation runs, private prompts, transcripts, or credential
contents.

### 1. Explain the check, then ask for authorization

Before running commands, tell the judge briefly:

> I’ll check the host platform and whether Git, Bash, Python 3, Homebrew, Docker
> `sbx`, Codex CLI, and the skill are available. If you choose the authenticated
> route and a required tool is missing, I’ll show you the official installation
> command and, only with your approval, run it. I will not inspect or print any
> credential contents.

Then ask this question and wait for the answer:

> Which route do you authorize?
>
> 1. **Authenticated live evaluation:** install missing prerequisites if separately
>    approved, then allow the skill to use my file-backed ChatGPT/Codex subscription
>    login only with generated trusted fixtures.
> 2. **Credential-free mock:** install the skill and run the deterministic mock
>    lifecycle suite without using my subscription, a real Codex call, or a real
>    `sbx` sandbox.

Pointing at this file is not consent to use a subscription. Do not infer the
answer, inspect authentication status, install host software, or set
`ALLOW_REAL_CODEX_AUTH=1` until the judge chooses. If the judge chooses the live
route, explain that it consumes their Codex subscription usage.

### 2. Locate the repository and perform read-only checks

If this file is already in a local checkout, use its Git top level. Otherwise ask
where to create the checkout, then run:

```bash
git clone https://github.com/DavidNavalho/jinx-agent-skills.git
cd jinx-agent-skills
```

Record the current branch, commit, and worktree status without modifying them:

```bash
git status --short --branch
git rev-parse HEAD
```

Preserve all existing changes. Check availability before installing anything:

```bash
uname -s
uname -m
sw_vers -productVersion 2>/dev/null || true
command -v git || true
command -v bash || true
command -v python3 || true
command -v brew || true
command -v sbx || true
command -v codex || true
```

Git, Bash, and Python 3 are required for both routes. The authenticated macOS
route additionally requires Homebrew, Docker `sbx`, Codex CLI, a Docker login,
and a file-backed ChatGPT login. Docker's documented macOS requirements are
macOS Sonoma 14 or newer on Apple silicon. If the host does not meet them, do not
improvise a different live setup; offer the credential-free mock route.

### 3. Install the skill without overwriting an existing copy

The source is `skills/run-agents-in-sbx`. The normal destination is
`${CODEX_HOME:-$HOME/.codex}/skills/run-agents-in-sbx`.

If the destination does not exist, install it with:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
cp -R skills/run-agents-in-sbx "${CODEX_HOME:-$HOME/.codex}/skills/"
```

If it already exists, compare it with `diff -qr`. Leave an identical copy alone.
If it differs, report that fact and ask before replacing or moving it; never
silently overwrite or delete an existing skill.

## Route 1 — authenticated live evaluation

Use this route only after the judge explicitly chooses it. The harness creates
generated private fixtures and invokes the committed runner, which owns the
sandbox lifecycle, copies only the file-backed authentication cache, validates
the handoff and evidence, and removes the exact owned sandbox when safe.

### Install missing host prerequisites

Show the judge every missing prerequisite and the exact command before running
it. A previous approval to use subscription authentication is not approval to
install host software.

If Homebrew is missing, ask before running the current command from
[brew.sh](https://brew.sh/):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the installer's PATH instructions. Install only the prerequisites that
the availability check found missing:

| Missing command | Homebrew command |
| --- | --- |
| `git` | `brew install git` |
| `bash` | `brew install bash` |
| `python3` | `brew install python` |

If `sbx` is missing, tell the judge that you are about to install Docker `sbx`,
ask for approval, then use Docker's documented macOS commands:

```bash
brew trust docker/tap
brew install docker/tap/sbx
```

Sign in to Docker interactively and let the judge select the network policy:

```bash
sbx login
```

If Codex CLI is missing, ask before running the current standalone installer from
the [official Codex CLI guide](https://learn.chatgpt.com/docs/codex/cli):

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

Re-run the availability and version checks after installation:

```bash
git --version
bash --version
python3 --version
brew --version
sbx version
codex --version
```

### Establish the supported ChatGPT login

Ask the judge to complete the browser flow rather than handling their account:

```bash
codex login
codex login status
```

The status must say that Codex is logged in using ChatGPT. This skill does not
implement OpenAI API-key authentication.

The runner requires a regular, non-symlink, file-backed cache at the generic
location `${CODEX_HOME:-$HOME/.codex}/auth.json`. Never open, print, parse, paste,
or mount that file or its parent directory. If ChatGPT status succeeds but the
file is unavailable, explain that the supported setup requires this Codex setting:

```toml
cli_auth_credentials_store = "file"
```

Ask before adding that single setting to
`${CODEX_HOME:-$HOME/.codex}/config.toml`; preserve all existing configuration,
then ask the judge to run `codex login` again. Do not use `codex logout`. If a
file-backed login still cannot be established, stop and offer the mock route.

### Preflight and preview

Run the credential-safe preflight. It may inspect file type and permissions but
must not read token values:

```bash
skills/run-agents-in-sbx/scripts/preflight.sh \
  --workspace "$(git rev-parse --show-toplevel)"
```

Then preview the exact evaluation. Plan mode creates no file or sandbox and
copies no credential:

```bash
evaluation/run-agents-in-sbx/run-live-boundary-eval.sh \
  --repetitions 1 \
  --plan
```

Summarize the plan: generated trusted fixtures, the generic credential source
and guest destination, both `outer` and `workspace-write` postures, effective
network-policy recording, serialized authentication, timeouts, evidence path,
and exact cleanup or recovery behavior. Ask the judge once more whether to
proceed with the credential crossing and two live cases.

### Run the live smoke evaluation

Only after that confirmation, run one repetition for each posture:

```bash
ALLOW_REAL_CODEX_AUTH=1 \
evaluation/run-agents-in-sbx/run-live-boundary-eval.sh \
  --repetitions 1
```

Do not mount host `CODEX_HOME`, pass credentials in a prompt, run live cases in
parallel, or run this against unknown or public code. The runner must copy only
`auth.json` to `/home/agent/.codex/auth.json` and serialize that authentication
lineage.

On ordinary completion, verify that the harness reports both postures passed and
that each exact owned sandbox was removed. If authentication changed, ownership
is ambiguous, or cleanup failed, stop and preserve the named sandbox and
workspace; report the typed recovery outcome and do not retry, log out, overwrite
host authentication, or delete unrelated sandboxes. Never use `sbx rm --all`.

The smoke command runs two live cases. Only if the judge asks to reproduce the
committed 6/6 boundary matrix, repeat the reviewed plan and live commands with
`--repetitions 3`.

## Route 2 — credential-free mock

Use this route when the judge has no compatible ChatGPT/Codex subscription login,
does not want to use it, or cannot run Docker `sbx`. Do not install `sbx` or Codex
solely for this route, inspect authentication, or set `ALLOW_REAL_CODEX_AUTH`.

After confirming Git, Bash, and Python 3, run:

```bash
evaluation/run-agents-in-sbx/run-static-tests.sh
```

Expected final line:

```text
run-agents-in-sbx static tests passed
```

This suite uses committed mock `sbx` and Codex fixtures to test preflight,
ownership, timeouts, handoffs, typed outcomes, authentication-change recovery,
semantic scoring, credential-leak detection, and exact cleanup logic. It creates
temporary data under the host temporary directory and removes it through an exit
trap. It does not prove the real Docker boundary or make a model call.

## Report to the judge

Finish with a compact report containing:

- the route the judge authorized;
- branch, commit, platform, and tool versions;
- any host software or skill installation performed;
- preflight, plan, and evaluation exit codes that apply;
- passed cases and sandbox cleanup or preserved-recovery state; and
- the non-sensitive evidence or summary path.

Do not include credential values, account metadata, raw prompts, raw transcripts,
or ignored run contents. Public methodology and committed results are in
[`TESTING.md`](TESTING.md), the
[`evaluation plan`](evaluation/run-agents-in-sbx/evaluation-plan.md), and the
[`evaluation results`](evaluation/run-agents-in-sbx/evaluation-results.md).
