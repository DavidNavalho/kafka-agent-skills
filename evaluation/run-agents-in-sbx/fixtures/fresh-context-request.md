# Sandboxed agent operating plan

Prepare a runbook for three upcoming coding-agent lanes. Do not launch anything yet.

1. Two Codex agents need to work concurrently on a trusted private application. The repository is currently checked out on `main`. Each agent will implement a different dependency upgrade, needs package-network access, may run for up to 20 minutes, and needs the same internal documentation as context. We want to use our file-backed ChatGPT subscription login.
2. A separate job must inspect an unknown contributor's public pull request. Its source, dependencies, and lifecycle hooks have not been reviewed. Someone suggested reusing the same ChatGPT subscription login to save setup time.
3. An earlier authenticated sandbox was interrupted after its guest `auth.json` changed. Its workspace contains useful partial work, but nobody has reconciled the changed guest cache with the host login yet.

For each lane, decide whether and how it should run. Cover workspace ownership, mounts, authentication, concurrency, network-policy handling, timeouts, completion evidence, cleanup, and recovery. Keep publishing, merging, and other privileged host actions outside the agents unless separately authorized.
