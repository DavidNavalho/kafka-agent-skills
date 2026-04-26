#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: create-lab.sh [options] [target-directory]

Create a local Kafka lab directory with:
  docker-compose.yml
  .env
  scripts/preflight.sh
  scripts/smoke-test.sh

Arguments:
  target-directory  Directory to create or populate. Defaults to current directory.

Options:
  --stack NAME              Kafka stack: apache or confluent. Defaults to apache.
  --with-schema-registry    Add Confluent Schema Registry.
  --with-connect            Add Kafka Connect.
  --ui NAME                 Add UI tooling: none or akhq. Defaults to none.
  --force                   Overwrite existing generated files.
  -h, --help                Show this help.
USAGE
}

FORCE=0
TARGET_DIR="."
STACK="apache"
WITH_SCHEMA_REGISTRY=0
WITH_CONNECT=0
UI="none"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --stack)
      STACK="${2:?Missing value for --stack}"
      shift 2
      ;;
    --with-schema-registry)
      WITH_SCHEMA_REGISTRY=1
      shift
      ;;
    --with-connect)
      WITH_CONNECT=1
      shift
      ;;
    --ui)
      UI="${2:?Missing value for --ui}"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

case "$STACK" in
  apache|confluent)
    ;;
  *)
    echo "Unsupported stack: $STACK" >&2
    echo "Supported stacks: apache, confluent" >&2
    exit 2
    ;;
esac

case "$UI" in
  none|akhq)
    ;;
  *)
    echo "Unsupported UI: $UI" >&2
    echo "Supported UIs: none, akhq" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

case "$STACK" in
  apache)
    COMPOSE_SRC="$SKILL_DIR/assets/compose/apache-kafka-kraft-3.yml"
    ;;
  confluent)
    COMPOSE_SRC="$SKILL_DIR/assets/compose/confluent-kafka-kraft-3.yml"
    ;;
esac

SCHEMA_REGISTRY_SRC="$SKILL_DIR/assets/compose/extras/schema-registry.yml"
CONNECT_SRC="$SKILL_DIR/assets/compose/extras/connect.yml"
AKHQ_SRC="$SKILL_DIR/assets/compose/extras/akhq.yml"
PREFLIGHT_SRC="$SKILL_DIR/scripts/preflight.sh"
SMOKE_SRC="$SKILL_DIR/scripts/smoke-test.sh"
REQUIRED_HOST_PORTS="29092 39092 49092"

COMPOSE_DEST="$TARGET_DIR/docker-compose.yml"
ENV_DEST="$TARGET_DIR/.env"
PREFLIGHT_DEST="$TARGET_DIR/scripts/preflight.sh"
SMOKE_DEST="$TARGET_DIR/scripts/smoke-test.sh"

copy_file() {
  local src="$1"
  local dest="$2"

  if [ -e "$dest" ] && [ "$FORCE" -ne 1 ]; then
    echo "Refusing to overwrite existing file: $dest" >&2
    echo "Re-run with --force to overwrite generated lab files." >&2
    exit 1
  fi

  cp "$src" "$dest"
}

append_file() {
  local src="$1"
  local dest="$2"

  printf '\n' >> "$dest"
  cat "$src" >> "$dest"
}

mkdir -p "$TARGET_DIR/scripts"

copy_file "$COMPOSE_SRC" "$COMPOSE_DEST"
if [ "$WITH_SCHEMA_REGISTRY" -eq 1 ]; then
  REQUIRED_HOST_PORTS="$REQUIRED_HOST_PORTS 8081"
  append_file "$SCHEMA_REGISTRY_SRC" "$COMPOSE_DEST"
fi
if [ "$WITH_CONNECT" -eq 1 ]; then
  REQUIRED_HOST_PORTS="$REQUIRED_HOST_PORTS 8083"
  mkdir -p "$TARGET_DIR/connect-data"
  append_file "$CONNECT_SRC" "$COMPOSE_DEST"
fi
if [ "$UI" = "akhq" ]; then
  REQUIRED_HOST_PORTS="$REQUIRED_HOST_PORTS 8080"
  append_file "$AKHQ_SRC" "$COMPOSE_DEST"
fi

copy_file "$PREFLIGHT_SRC" "$PREFLIGHT_DEST"
copy_file "$SMOKE_SRC" "$SMOKE_DEST"
chmod +x "$PREFLIGHT_DEST" "$SMOKE_DEST"

if [ -e "$ENV_DEST" ] && [ "$FORCE" -ne 1 ]; then
  echo "Refusing to overwrite existing file: $ENV_DEST" >&2
  echo "Re-run with --force to overwrite generated lab files." >&2
  exit 1
fi

cat > "$ENV_DEST" <<EOF
STACK=$STACK
WITH_SCHEMA_REGISTRY=$WITH_SCHEMA_REGISTRY
WITH_CONNECT=$WITH_CONNECT
UI=$UI
REQUIRED_HOST_PORTS="$REQUIRED_HOST_PORTS"
HOST_BOOTSTRAP_SERVERS=localhost:29092,localhost:39092,localhost:49092
DOCKER_BOOTSTRAP_SERVERS=kafka-1:19092,kafka-2:19092,kafka-3:19092
SCHEMA_REGISTRY_URL=http://localhost:8081
CONNECT_URL=http://localhost:8083
AKHQ_URL=http://localhost:8080
EOF

cat <<EOF
Kafka local lab files created in: $TARGET_DIR

Configuration:
  Stack: $STACK
  Schema Registry: $WITH_SCHEMA_REGISTRY
  Kafka Connect: $WITH_CONNECT
  UI: $UI

Next commands:
  cd "$TARGET_DIR"
  ./scripts/preflight.sh
  docker compose up -d
  ./scripts/preflight.sh --check-exec
  ./scripts/smoke-test.sh

Stop the lab:
  docker compose down

Stop and remove lab data:
  docker compose down -v
EOF
