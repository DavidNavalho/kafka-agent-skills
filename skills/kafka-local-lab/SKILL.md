---
name: kafka-local-lab
description: Set up and verify a local Docker-based Apache Kafka or Confluent Platform lab for development, demos, and testing. Use when the user wants a quick local Kafka environment, Docker Compose setup, Schema Registry, Kafka Connect, UI tooling, or smoke-tested Kafka endpoints.
---

# kafka-local-lab

## Purpose

Help users create a local Docker-based Kafka lab quickly, verify that it works, and explain how to connect to it.

## Scope

This skill supports local development and testing environments only.

Initial supported path:
- Apache Kafka
- Confluent Kafka
- KRaft mode
- Three brokers
- Plaintext listeners
- Ephemeral storage
- Docker Compose
- Smoke test with topic create, produce, and consume
- Optional Confluent Schema Registry smoke test with schema write/read through the REST API
- Optional Kafka Connect smoke test with the bundled FileStream source connector
- Optional AKHQ UI

Out of scope for the first version:
- Kubernetes
- Cloud Kafka
- Production hardening
- Advanced failure testing
- Multi-region setups
- Long-running benchmark environments
- Non-Docker host installs

## Workflow

1. Check whether Docker is installed and running. If not, provide instructions to install and start Docker before proceeding.
2. Ask the user only for missing choices needed to proceed.
3. Prefer the default supported setup when the user does not specify details.
4. If the user asks for Confluent Platform components such as Schema Registry or Kafka Connect, prefer `--stack confluent` unless they explicitly ask to keep Apache Kafka brokers.
5. Use `scripts/create-lab.sh` to materialize the lab files into the chosen lab directory. Unless specified, use the current directory as the lab directory.
6. In the lab directory, run `./scripts/preflight.sh` before starting Docker Compose. This checks Docker, Docker Compose, resources, and required host ports.
7. Start the lab with Docker Compose.
8. Run `./scripts/preflight.sh --check-exec` to verify Docker Compose can exec into `kafka-1`.
9. Run `./scripts/smoke-test.sh`. The smoke test must use Docker Compose and Kafka CLI tools inside the Kafka container; do not require host-side Kafka CLI tools, Python packages, or extra local software.
10. Report connection details, created files, and cleanup command.

Use bundled scripts as the primary interface. Do not read full script bodies before normal use. Read script source only if a script fails, needs local modification, or the user asks how it works.

## Defaults

Use these defaults unless the user asks otherwise:

- Stack: Apache Kafka
- Brokers: 3
- Security: plaintext
- Storage: ephemeral
- Extras: none
- Topic for smoke test: `lab-smoke-test`
- Bootstrap servers from host: `localhost:29092,localhost:39092,localhost:49092`
- Bootstrap servers from containers on the same Compose network: `kafka-1:19092,kafka-2:19092,kafka-3:19092`
- Host broker ports: `29092`, `39092`, `49092`
- Schema Registry URL when enabled: `http://localhost:8081`
- Kafka Connect URL when enabled: `http://localhost:8083`
- AKHQ URL when enabled: `http://localhost:8080`

Resource note: the default 3-broker lab is more realistic than a single broker, but uses more local CPU and memory.

## User Questions

Ask at most three short questions before creating the lab.

Ask about:
- Apache Kafka vs Confluent Platform
- Extras such as Schema Registry, Kafka Connect, or AKHQ UI

If the user says "quick", "simple", "default", or gives no preference, use the defaults without asking.

## Validation

After startup, verify:

1. Docker containers are running.
2. Kafka accepts an admin request.
3. A topic can be created.
4. A record can be produced.
5. The record can be consumed back.
6. If Schema Registry is enabled, a schema can be registered and read back.
7. If Kafka Connect is enabled, a FileStream source connector can write one line into Kafka.
8. If AKHQ is enabled, the UI responds over HTTP.

If validation fails, inspect Docker Compose status and logs before suggesting fixes.

If Docker startup, Docker permissions, host port binding, advertised-listener connectivity, or smoke-test validation fails, read `references/troubleshooting.md` before proposing fixes.

Use the bundled create script to create or populate the lab directory:

```bash
./scripts/create-lab.sh ./kafka-local-lab
```

Useful create examples:

```bash
./scripts/create-lab.sh --stack confluent ./kafka-local-lab
./scripts/create-lab.sh --stack confluent --with-schema-registry ./kafka-local-lab
./scripts/create-lab.sh --stack confluent --with-connect ./kafka-local-lab
./scripts/create-lab.sh --stack confluent --with-schema-registry --with-connect --ui akhq ./kafka-local-lab
```

Use the bundled preflight script before startup:

```bash
cd ./kafka-local-lab
./scripts/preflight.sh
```

After startup, verify Docker Compose exec works:

```bash
./scripts/preflight.sh --check-exec
```

Use the bundled smoke test script after startup:

```bash
./scripts/smoke-test.sh
```

The script runs Kafka client commands inside `kafka-1`, so it uses the Docker-network bootstrap servers by default.

## Completion Response

When done, report:

- Lab directory
- Bootstrap server
- Docker-network bootstrap servers, if relevant
- Any extra service URLs
- Smoke test result
- Stop command
- Cleanup command
