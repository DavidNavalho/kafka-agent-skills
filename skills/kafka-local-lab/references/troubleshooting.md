# Troubleshooting

## Docker Is Not Running

Symptoms:
- `Cannot connect to the Docker daemon`
- Docker socket errors
- `docker compose ps` fails

Response:
- Ask the user to start Docker Desktop or Docker Engine.
- Do not attempt to install Docker automatically.
- Do not modify Docker socket permissions.
- After Docker is running, retry `docker version` and `docker compose version`.

## Docker Permission Or Sandbox Denied

Symptoms:
- `permission denied while trying to connect to the Docker daemon socket`
- `operation not permitted`
- `docker ps` works but `docker exec` fails
- `docker compose ps` works but `docker compose exec` fails

Response:
- Explain that the shell/session can inspect Docker but cannot exec into containers.
- Tell the user the smoke test requires `docker compose exec`.
- Ask them to grant Docker access or run the command themselves.
- Do not work around by installing host Kafka clients unless the user asks.

## Host Ports Already In Use

Symptoms:
- `Bind for 0.0.0.0:29092 failed`
- `port is already allocated`
- Compose starts partially, or one broker exits immediately

Response:
- Check what is using `29092`, `39092`, `49092`, and any enabled extra ports.
- Extra service ports are `8081` for Schema Registry, `8083` for Kafka Connect, and `8080` for AKHQ.
- Prefer stopping the conflicting local Kafka lab.
- If changing ports, update Docker `ports`, `KAFKA_LISTENERS`, and `KAFKA_ADVERTISED_LISTENERS`.
- Do not change only the Docker port mapping.

## Advertised Listener Mismatch

Symptoms:
- Client connects initially, then produce/consume/admin calls hang or fail.
- Metadata request works but broker connection fails.
- Errors mention unreachable broker address like `kafka-1:19092` from the host, or `localhost:29092` from inside a container.

Explanation:
- Kafka clients first connect to a bootstrap server.
- Kafka then returns advertised broker addresses.
- Those advertised addresses must be reachable from the client's network location.

Correct addresses:
- Host clients use: `localhost:29092,localhost:39092,localhost:49092`
- Containers on the same Compose network use: `kafka-1:19092,kafka-2:19092,kafka-3:19092`

Rule:
- If changing listener ports, update `KAFKA_LISTENERS`, `KAFKA_ADVERTISED_LISTENERS`, and Docker `ports` together.

## Smoke Test Hangs At Consume

Symptoms:
- Topic is created.
- Produce step logs success.
- Consume step waits until timeout or fails to find the message.

Checks:
- Confirm the smoke test uses internal bootstrap servers because it runs inside `kafka-1`.
- Confirm topic name matches.
- Confirm the message was produced after topic creation.
- Run topic describe from inside `kafka-1`:

```bash
docker compose exec -T kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka-1:19092,kafka-2:19092,kafka-3:19092 \
  --describe \
  --topic lab-smoke-test
```
