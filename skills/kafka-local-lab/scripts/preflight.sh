#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: preflight.sh [options]

Check local prerequisites for kafka-local-lab.

Options:
  --check-exec          Also verify docker compose exec works against kafka-1.
  --compose-file FILE   Compose file to use for exec checks. Defaults to docker-compose.yml.
  --project-dir DIR     Compose project directory. Defaults to current directory.
  --ports "LIST"        Space-separated host ports to check. Defaults to "29092 39092 49092".
  -h, --help            Show this help.

Environment overrides:
  COMPOSE_FILE          Compose file to use.
  PROJECT_DIR           Compose project directory.
  PORTS                 Space-separated host ports to check.
  MIN_CPUS              Warn if Docker has fewer CPUs. Defaults to 4.
  MIN_MEMORY_BYTES      Warn if Docker has less memory. Defaults to 6442450944.
USAGE
}

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
PROJECT_DIR="${PROJECT_DIR:-.}"
PORTS="${PORTS:-29092 39092 49092}"
MIN_CPUS="${MIN_CPUS:-4}"
MIN_MEMORY_BYTES="${MIN_MEMORY_BYTES:-6442450944}"
CHECK_EXEC=0
PORTS_EXPLICIT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-exec)
      CHECK_EXEC=1
      shift
      ;;
    --compose-file)
      COMPOSE_FILE="${2:?Missing value for --compose-file}"
      shift 2
      ;;
    --project-dir)
      PROJECT_DIR="${2:?Missing value for --project-dir}"
      shift 2
      ;;
    --ports)
      PORTS="${2:?Missing value for --ports}"
      PORTS_EXPLICIT=1
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$PROJECT_DIR/.env"
  set +a
fi

if [ "$PORTS_EXPLICIT" -eq 0 ] && [ -n "${REQUIRED_HOST_PORTS:-}" ]; then
  PORTS="$REQUIRED_HOST_PORTS"
fi

log() {
  printf '[preflight] %s\n' "$*"
}

warn() {
  printf '[preflight] warning: %s\n' "$*" >&2
}

fail() {
  printf '[preflight] error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

compose() {
  docker compose -f "$COMPOSE_FILE" --project-directory "$PROJECT_DIR" "$@"
}

port_in_use() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk -v p=":$port" '$4 ~ p "$" {found=1} END {exit !found}'
    return $?
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -an 2>/dev/null | awk -v p=".$port" '$0 ~ p && $0 ~ /LISTEN/ {found=1} END {exit !found}'
    return $?
  fi

  (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1
}

check_docker() {
  log "Checking Docker CLI"
  require_command docker

  log "Checking Docker daemon"
  docker version >/dev/null || fail "Docker is installed but the daemon is not reachable"

  log "Checking Docker Compose"
  docker compose version >/dev/null || fail "Docker Compose is not available through 'docker compose'"
}

check_resources() {
  local cpus memory_bytes memory_gib

  cpus="$(docker info --format '{{.NCPU}}' 2>/dev/null || true)"
  memory_bytes="$(docker info --format '{{.MemTotal}}' 2>/dev/null || true)"

  if [ -n "$cpus" ] && [ "$cpus" -lt "$MIN_CPUS" ]; then
    warn "Docker reports $cpus CPU(s); the default 3-broker lab is smoother with $MIN_CPUS or more"
  elif [ -n "$cpus" ]; then
    log "Docker CPU allocation: $cpus"
  fi

  if [ -n "$memory_bytes" ]; then
    memory_gib="$((memory_bytes / 1073741824))"
    if [ "$memory_bytes" -lt "$MIN_MEMORY_BYTES" ]; then
      warn "Docker reports about ${memory_gib}GiB memory; the default 3-broker lab is smoother with 6GiB or more"
    else
      log "Docker memory allocation: about ${memory_gib}GiB"
    fi
  fi
}

check_ports() {
  local port found_conflict
  found_conflict=0

  log "Checking host ports: $PORTS"
  for port in $PORTS; do
    if port_in_use "$port"; then
      echo "[preflight] port $port: in use" >&2
      found_conflict=1
    else
      log "port $port: available"
    fi
  done

  if [ "$found_conflict" -ne 0 ]; then
    fail "One or more required host ports are already in use"
  fi
}

check_compose_exec() {
  log "Checking docker compose exec against kafka-1"
  compose exec -T kafka-1 true >/dev/null || fail "docker compose exec failed for service kafka-1"
}

main() {
  check_docker
  check_resources
  check_ports

  if [ "$CHECK_EXEC" -eq 1 ]; then
    check_compose_exec
  fi

  log "Preflight checks passed"
}

main "$@"
