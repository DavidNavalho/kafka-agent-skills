#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
PROJECT_DIR="${PROJECT_DIR:-.}"
BOOTSTRAP_SERVERS="${BOOTSTRAP_SERVERS:-kafka-1:19092,kafka-2:19092,kafka-3:19092}"
TOPIC="${TOPIC:-lab-smoke-test}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-90}"
SCHEMA_REGISTRY_SUBJECT="${SCHEMA_REGISTRY_SUBJECT:-lab-smoke-value}"
CONNECT_TOPIC="${CONNECT_TOPIC:-connect-file-smoke}"
CONNECTOR_NAME="${CONNECTOR_NAME:-local-file-source}"

MESSAGE="kafka-local-lab-smoke-$(date +%s)-$$"
CONNECT_MESSAGE="kafka-local-lab-connect-$(date +%s)-$$"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$PROJECT_DIR/.env"
  set +a
fi

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

compose() {
  docker compose -f "$COMPOSE_FILE" --project-directory "$PROJECT_DIR" "$@"
}

kafka_exec() {
  compose exec -T kafka-1 "$@"
}

service_exists() {
  compose config --services 2>/dev/null | grep -Fxq "$1"
}

kafka_cli() {
  local tool="$1"
  shift

  kafka_exec sh -lc '
    tool="$1"
    shift
    for candidate in \
      "/opt/kafka/bin/${tool}.sh" \
      "/usr/bin/${tool}" \
      "/bin/${tool}" \
      "${tool}.sh" \
      "${tool}"; do
      if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then
        exec "$candidate" "$@"
      fi
    done
    echo "Kafka CLI tool not found: $tool" >&2
    exit 127
  ' sh "$tool" "$@"
}

http_in_service() {
  local service="$1"
  local method="$2"
  local url="$3"
  local data="${4:-}"

  compose exec -T "$service" sh -lc '
    method="$1"
    url="$2"
    data="$3"
    if ! command -v curl >/dev/null 2>&1; then
      echo "curl is required inside service $HOSTNAME for HTTP smoke checks" >&2
      exit 127
    fi
    if [ "$method" = "GET" ]; then
      curl -fsS "$url"
    else
      printf "%s" "$data" | curl -fsS -X "$method" \
        -H "Content-Type: application/vnd.schemaregistry.v1+json" \
        --data @- \
        "$url"
    fi
  ' sh "$method" "$url" "$data"
}

wait_for_kafka() {
  local start now
  start="$(date +%s)"

  log "Waiting for Kafka readiness via kafka-1"
  while true; do
    if kafka_cli kafka-broker-api-versions \
      --bootstrap-server "$BOOTSTRAP_SERVERS" >/dev/null 2>&1; then
      log "Kafka is ready"
      return 0
    fi

    now="$(date +%s)"
    if [ "$((now - start))" -ge "$TIMEOUT_SECONDS" ]; then
      echo "Kafka did not become ready within ${TIMEOUT_SECONDS}s" >&2
      compose ps >&2 || true
      return 1
    fi

    log "Kafka not ready yet; retrying in 3s"
    sleep 3
  done
}

create_topic() {
  log "Creating topic if needed: $TOPIC"
  kafka_cli kafka-topics \
    --bootstrap-server "$BOOTSTRAP_SERVERS" \
    --create \
    --if-not-exists \
    --topic "$TOPIC" \
    --partitions 3 \
    --replication-factor 3 >/dev/null
}

produce_message() {
  log "Producing smoke-test message"
  printf '%s\n' "$MESSAGE" | kafka_cli kafka-console-producer \
    --bootstrap-server "$BOOTSTRAP_SERVERS" \
    --topic "$TOPIC" >/dev/null
  log "Produced message: $MESSAGE"
}

consume_message() {
  local topic="${1:-$TOPIC}"
  local expected="${2:-$MESSAGE}"
  local output

  log "Consuming from $topic to verify expected message"
  output="$(
    kafka_cli kafka-console-consumer \
      --bootstrap-server "$BOOTSTRAP_SERVERS" \
      --topic "$topic" \
      --from-beginning \
      --timeout-ms 10000 2>/dev/null || true
  )"

  if ! printf '%s\n' "$output" | grep -Fqx "$expected"; then
    echo "Smoke test message was not consumed back from Kafka" >&2
    echo "Expected: $expected" >&2
    echo "Consumed output:" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
}

wait_for_http_service() {
  local service="$1"
  local url="$2"
  local start now
  start="$(date +%s)"

  log "Waiting for $service readiness at $url"
  while true; do
    if http_in_service "$service" GET "$url" >/dev/null 2>&1; then
      log "$service is ready"
      return 0
    fi

    now="$(date +%s)"
    if [ "$((now - start))" -ge "$TIMEOUT_SECONDS" ]; then
      echo "$service did not become ready within ${TIMEOUT_SECONDS}s" >&2
      compose ps >&2 || true
      return 1
    fi

    log "$service not ready yet; retrying in 3s"
    sleep 3
  done
}

smoke_schema_registry() {
  local payload latest

  if ! service_exists schema-registry; then
    return 0
  fi

  wait_for_http_service schema-registry http://localhost:8081/subjects

  payload='{"schema":"{\"type\":\"record\",\"name\":\"LabSmoke\",\"fields\":[{\"name\":\"message\",\"type\":\"string\"}]}"}'

  log "Registering schema in Schema Registry subject: $SCHEMA_REGISTRY_SUBJECT"
  http_in_service schema-registry POST "http://localhost:8081/subjects/${SCHEMA_REGISTRY_SUBJECT}/versions" "$payload" >/dev/null

  log "Reading schema back from Schema Registry"
  latest="$(http_in_service schema-registry GET "http://localhost:8081/subjects/${SCHEMA_REGISTRY_SUBJECT}/versions/latest")"
  if ! printf '%s\n' "$latest" | grep -Fq "\"subject\":\"$SCHEMA_REGISTRY_SUBJECT\"" \
    || ! printf '%s\n' "$latest" | grep -Fq '\"name\":\"LabSmoke\"' \
    || ! printf '%s\n' "$latest" | grep -Fq '\"name\":\"message\"' \
    || ! printf '%s\n' "$latest" | grep -Fq '\"type\":\"string\"'; then
    echo "Schema Registry did not return the expected schema" >&2
    echo "$latest" >&2
    return 1
  fi

  echo "Schema Registry smoke test passed"
  echo "Schema Registry URL: http://localhost:8081"
}

smoke_connect() {
  local config status output

  if ! service_exists connect; then
    return 0
  fi

  wait_for_http_service connect http://localhost:8083/connectors

  log "Creating Kafka Connect FileStream source connector: $CONNECTOR_NAME"
  compose exec -T connect sh -lc '
    mkdir -p /tmp/kafka-local-lab-connect
    : > /tmp/kafka-local-lab-connect/source.txt
  '

  config='{"connector.class":"FileStreamSource","tasks.max":"1","file":"/tmp/kafka-local-lab-connect/source.txt","topic":"'"$CONNECT_TOPIC"'"}'
  compose exec -T connect sh -lc '
    connector="$1"
    config="$2"
    printf "%s" "$config" | curl -fsS -X PUT \
      -H "Content-Type: application/json" \
      --data @- \
      "http://localhost:8083/connectors/${connector}/config"
  ' sh "$CONNECTOR_NAME" "$config" >/dev/null

  status="$(compose exec -T connect sh -lc 'curl -fsS "http://localhost:8083/connectors/$1/status"' sh "$CONNECTOR_NAME")"
  if ! printf '%s\n' "$status" | grep -Eq '"state"[[:space:]]*:[[:space:]]*"(RUNNING|STARTING)"'; then
    echo "Kafka Connect connector did not start" >&2
    echo "$status" >&2
    return 1
  fi

  log "Appending line to FileStream source file"
  compose exec -T connect sh -lc 'printf "%s\n" "$1" >> /tmp/kafka-local-lab-connect/source.txt' sh "$CONNECT_MESSAGE"

  output="$(
    kafka_cli kafka-console-consumer \
      --bootstrap-server "$BOOTSTRAP_SERVERS" \
      --topic "$CONNECT_TOPIC" \
      --from-beginning \
      --timeout-ms 20000 2>/dev/null || true
  )"

  if ! printf '%s\n' "$output" | grep -Fqx "$CONNECT_MESSAGE"; then
    echo "Kafka Connect FileStream message was not consumed from Kafka" >&2
    echo "Expected: $CONNECT_MESSAGE" >&2
    echo "Consumed output:" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  echo "Kafka Connect FileStream smoke test passed"
  echo "Kafka Connect URL: http://localhost:8083"
}

smoke_akhq() {
  if ! service_exists akhq; then
    return 0
  fi

  log "Checking AKHQ service"
  if command -v curl >/dev/null 2>&1; then
    local start now
    start="$(date +%s)"
    while true; do
      if curl -fsS http://localhost:8080 >/dev/null 2>&1; then
        echo "AKHQ smoke test passed"
        echo "AKHQ URL: http://localhost:8080"
        return 0
      fi

      now="$(date +%s)"
      if [ "$((now - start))" -ge "$TIMEOUT_SECONDS" ]; then
        echo "AKHQ did not become reachable within ${TIMEOUT_SECONDS}s" >&2
        compose ps >&2 || true
        return 1
      fi

      log "AKHQ not ready yet; retrying in 3s"
      sleep 3
    done
  fi

  echo "Host curl is not available; AKHQ HTTP smoke check skipped" >&2
}

main() {
  log "Kafka local lab smoke test starting"
  log "Compose file: $COMPOSE_FILE"
  log "Project directory: $PROJECT_DIR"
  log "Bootstrap servers: $BOOTSTRAP_SERVERS"
  log "Topic: $TOPIC"

  log "Current Compose service status"
  compose ps

  wait_for_kafka
  create_topic
  produce_message
  consume_message
  smoke_schema_registry
  smoke_connect
  smoke_akhq

  echo "Kafka smoke test passed"
  echo "Bootstrap servers: $BOOTSTRAP_SERVERS"
  echo "Topic: $TOPIC"
}

main "$@"
