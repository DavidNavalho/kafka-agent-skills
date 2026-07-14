# Codex ChatGPT-Subscription Authentication

Use this reference before provisioning or diagnosing Codex authentication, after a 401, and whenever a run reports that the guest auth cache changed.

## Supported strategy

This skill implements one strategy: copy a file-backed host ChatGPT auth cache into `/home/agent/.codex` inside one owned sandbox.

OpenAI distinguishes ChatGPT sign-in for subscription/workspace access from API-key sign-in for usage-based Platform access. `codex login status` must report ChatGPT for this strategy. Do not set `OPENAI_API_KEY` or `CODEX_API_KEY` for the sandboxed invocation.

Official references:

- [Authentication](https://learn.chatgpt.com/docs/auth)
- [Non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)
- [Maintain Codex account auth in CI/CD](https://learn.chatgpt.com/docs/auth/ci-cd-auth)
- [Codex CLI commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli)

## Host prerequisites

1. Configure file-backed credential storage when the host uses a keyring:

   ```toml
   cli_auth_credentials_store = "file"
   ```

2. Sign in on the trusted host with `codex login`.
3. Verify `codex login status` reports ChatGPT.
4. Locate `${CODEX_HOME:-$HOME/.codex}/auth.json` and require it to be a regular, non-symlink file with no group or other permission bits.
5. Treat the file as a password. Never print it, parse token values into logs, commit it, paste it into chat, or expose its directory as a mount.

This is host isolation, not secret isolation from guest code. The copied cache must be readable and writable by the guest Codex user, so a command or dependency lifecycle hook running as that user may be able to read it. Use the copy strategy only for trusted private workspaces and trusted prompts. Do not use it for adversarial repositories, unknown public pull requests, malicious-package analysis, or arbitrary untrusted build hooks, especially under permissive egress. Run those probes in a separate credential-free sandbox or adopt a separately validated credential proxy that does not expose reusable token material to the guest.

For a headless sandbox, `codex login --device-auth` is a manual fallback. It creates guest-local credentials through the official device-code flow, but is interactive and therefore not the default one-shot strategy.

## Copy sequence

Use `scripts/provision-codex-auth.sh`; its sequence is intentionally narrow:

1. create guest-private `/home/agent/.codex` with mode 700;
2. `sbx cp` the host file to a staged guest filename;
3. in the guest, run `sudo -n chown agent:agent STAGED`;
4. atomically move the staged file to `auth.json`;
5. set mode 600;
6. unset API-key environment variables and verify `codex login status` reports ChatGPT.

`sbx cp` preserves the host file's uid and mode. A host-owned mode-600 file is unreadable to guest user `agent` until ownership is repaired. Codex must be able to rewrite its guest copy when refreshing tokens, so read-only placement is insufficient.

The host path is passed only as an argument to `sbx cp`; the helper never pipes or prints credential contents. Copying the entire host `CODEX_HOME`, its config, or its skills is outside this strategy.

## Existing template auth

A new `codex` sandbox may already contain API-key or proxy-provisioned auth. Never assume a clean guest. The staged ChatGPT copy must replace the guest file, the runtime must unset `OPENAI_API_KEY` and `CODEX_API_KEY`, and the post-copy status must explicitly name ChatGPT.

Do not call `codex logout` to clear an unwanted guest session. Logout may affect a shared refresh-token lineage. Replace or remove only the disposable guest cache file, or delete the owned sandbox.

## Refresh and serialization

Codex refreshes ChatGPT-managed auth during normal use and rewrites `auth.json`. OpenAI's automation guidance requires one machine or one serialized job stream per auth-cache copy and persistence of the refreshed file for later runs.

For this skill's first version:

- serialize all runs using the same host auth file;
- use short-lived sandbox copies;
- have the runner hash the guest cache before and after, compare those hashes only
  in transient host-controller memory, and persist neither hash;
- if the guest copy changed, stop and preserve the sandbox;
- do not discard the changed copy and do not automatically overwrite the host cache.

When refresh is detected, treat the run as `auth-refresh-recovery-required` even if the task succeeded. Before another run uses the same session lineage:

1. stop new launches;
2. verify the preserved sandbox name and guest auth path from the run result;
3. choose a secure reconciliation design appropriate to the project, such as copying the refreshed file to a new host mode-600 path through `sbx cp` and atomically promoting it after explicit review;
4. verify host `codex login status` and a tiny real `codex exec --ephemeral` call;
5. remove the preserved sandbox only after the usable refreshed cache is safely persisted or the host has been re-seeded with `codex login`.

Automatic refreshed-copy promotion is deliberately future work because an incorrect race can invalidate the host session. Never run parallel sandboxes from one mutable `auth.json` lineage merely because the initial copies are separate files.

## Failure classification

| Observation | Classification | Response |
| --- | --- | --- |
| Host status says API key | Wrong auth mode | Stop; sign in with ChatGPT on the host. |
| Host status says ChatGPT but file is absent | Keyring-backed or wrong `CODEX_HOME` | Switch to file storage or supply the correct file reference. |
| Guest status says API key after copy | Ambient/template auth won | Stop; check API-key env and do not run the task. |
| Guest status succeeds but first model call returns 401 | Stale or revoked cache | Preserve evidence; reseed or reconcile; status alone is insufficient. |
| No-auth run hangs on stdin | Auth missing shape | Hard timeout; classify exit 124 as auth/setup failure when no progress occurred. |
| No-auth run fails quickly | Alternate auth missing shape | Classify from status, exit, latency, and stderr; do not assume one fixed shape. |
| Invalid token fails quickly | Auth invalid | Do not retry as a task failure. |
| Guest cache changes | Refresh occurred or cache was rewritten | Preserve sandbox and reconcile before cleanup. |
| Host cache changes during locked run | External host activity | Record the fact and verify host session before proceeding. |

`codex login status` proves that a cache is recognized, not that the next model request will succeed. Use a tiny bounded real call before an expensive batch when the credential is old, newly copied, or recently recovered.

## Deferred strategies

- `sbx secret set -g openai --oauth` is a current native surface, but it is interactive and changes persistent host `sbx` configuration. Evaluate it separately before adopting it.
- Codex access tokens can support trusted enterprise automation but require a distinct lifecycle and policy.
- API-key auth changes billing, admin controls, storage, and threat model; it is not a drop-in flag for this strategy.
- Claude subscription and Claude API require their own storage, refresh, noninteractive, and revocation probes.
