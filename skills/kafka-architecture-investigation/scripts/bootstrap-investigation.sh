#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bootstrap-investigation.sh PROJECT_ROOT [DOC ...]

Create the fixed kafka-architecture-investigation directory layout and copy the
canonical TRACKER.md template if it is missing. Extra DOC arguments copy matching
assets/templates/DOC files into docs/kafka-architecture-investigation/ when
missing.

Example:
  bootstrap-investigation.sh . INVESTIGATION_BRIEF.md REFERENCE_ARCHITECTURE.md
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

project_root="${1:?Missing PROJECT_ROOT}"
shift || true

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"
template_dir="$skill_dir/assets/templates"
doc_dir="$project_root/docs/kafka-architecture-investigation"

mkdir -p \
  "$doc_dir" \
  "$project_root/scripts/kafka-architecture-investigation" \
  "$project_root/artifacts/kafka-architecture-investigation/runs" \
  "$project_root/artifacts/kafka-architecture-investigation/snapshots"

copy_template() {
  local name="$1"
  local src="$template_dir/$name"
  local dest="$doc_dir/$name"

  test -f "$src" || {
    echo "Missing template: $src" >&2
    exit 1
  }

  if [ ! -f "$dest" ]; then
    cp "$src" "$dest"
  fi
}

copy_template TRACKER.md

for doc in "$@"; do
  copy_template "$doc"
done
