#!/usr/bin/env python3
"""Validate the run-agents-in-sbx handoff contract without dependencies."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "1.0"
STATUSES = {"succeeded", "partial", "blocked", "failed"}
FIELDS = {
    "schemaVersion",
    "status",
    "summary",
    "changedFiles",
    "validationEvidence",
    "unresolvedRisks",
    "recommendedNextAction",
}
CREDENTIAL_PARTS = {
    ".codex",
    ".ssh",
    "auth.json",
    "credentials",
    "credential",
    "secrets",
    "secret",
    "private-key",
}
DEFAULT_MAX_HANDOFF_BYTES = 1_048_576
DEFAULT_MAX_EVIDENCE_BYTES = 10_485_760


class ValidationError(Exception):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", required=True, help="Absolute or relative workspace root")
    parser.add_argument("--handoff", required=True, help="Workspace-relative handoff JSON path")
    parser.add_argument("--json", action="store_true", help="Print a JSON result")
    parser.add_argument(
        "--preserve-raw-to",
        help="After safe bounded path checks, copy raw handoff bytes to a new file",
    )
    parser.add_argument(
        "--max-handoff-bytes", type=int, default=DEFAULT_MAX_HANDOFF_BYTES
    )
    parser.add_argument(
        "--max-evidence-bytes", type=int, default=DEFAULT_MAX_EVIDENCE_BYTES
    )
    return parser.parse_args()


def require_nonempty_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(f"{field} must be a nonempty string")
    return value.strip()


def relative_parts(value: Any, field: str) -> tuple[str, ...]:
    text = require_nonempty_string(value, field)
    if "\\" in text:
        raise ValidationError(f"{field} must use forward-slash workspace-relative paths")
    if text.startswith("/"):
        raise ValidationError(f"{field} must be workspace-relative")
    parts = tuple(text.split("/"))
    if any(part in {"", ".", ".."} for part in parts):
        raise ValidationError(f"{field} contains a forbidden path component")
    if any(part.lower() in CREDENTIAL_PARTS for part in parts):
        raise ValidationError(f"{field} points at a credential-oriented path")
    return parts


def safe_existing_file(
    workspace: Path, parts: tuple[str, ...], field: str, max_bytes: int
) -> Path:
    current = workspace
    for part in parts:
        current = current / part
        try:
            info = current.lstat()
        except FileNotFoundError as error:
            raise ValidationError(f"{field} is missing: {'/'.join(parts)}") from error
        if stat.S_ISLNK(info.st_mode):
            raise ValidationError(f"{field} traverses or targets a symlink")

    info = current.stat()
    if not stat.S_ISREG(info.st_mode):
        raise ValidationError(f"{field} must target a regular file")
    if info.st_size == 0:
        raise ValidationError(f"{field} must not be empty")
    if info.st_size > max_bytes:
        raise ValidationError(
            f"{field} exceeds the {max_bytes}-byte safety limit"
        )
    try:
        current.resolve(strict=True).relative_to(workspace)
    except ValueError as error:
        raise ValidationError(f"{field} resolves outside the workspace") from error
    return current


def string_list(value: Any, field: str) -> list[str]:
    if not isinstance(value, list):
        raise ValidationError(f"{field} must be an array")
    result: list[str] = []
    for index, item in enumerate(value):
        result.append(require_nonempty_string(item, f"{field}[{index}]"))
    return result


def validate(args: argparse.Namespace) -> dict[str, Any]:
    workspace = Path(args.workspace).expanduser().resolve(strict=True)
    if not workspace.is_dir():
        raise ValidationError("workspace must be a directory")

    handoff_parts = relative_parts(args.handoff, "handoff")
    handoff_path = safe_existing_file(
        workspace, handoff_parts, "handoff", args.max_handoff_bytes
    )
    raw_handoff = handoff_path.read_bytes()
    if args.preserve_raw_to:
        destination = Path(args.preserve_raw_to).expanduser()
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            descriptor = os.open(
                destination,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o600,
            )
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(raw_handoff)
        except FileExistsError as error:
            raise ValidationError(
                f"raw handoff destination already exists: {destination}"
            ) from error
    try:
        document = json.loads(raw_handoff.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValidationError(f"handoff is not valid UTF-8 JSON: {error}") from error

    if not isinstance(document, dict):
        raise ValidationError("handoff root must be an object")
    keys = set(document)
    if keys != FIELDS:
        missing = sorted(FIELDS - keys)
        unknown = sorted(keys - FIELDS)
        details = []
        if missing:
            details.append(f"missing={','.join(missing)}")
        if unknown:
            details.append(f"unknown={','.join(unknown)}")
        raise ValidationError("handoff fields are not exact: " + " ".join(details))

    if document["schemaVersion"] != SCHEMA_VERSION:
        raise ValidationError(
            f"schemaVersion must be {SCHEMA_VERSION!r}, got {document['schemaVersion']!r}"
        )
    status_value = require_nonempty_string(document["status"], "status")
    if status_value not in STATUSES:
        raise ValidationError("status must be succeeded, partial, blocked, or failed")
    summary = require_nonempty_string(document["summary"], "summary")
    if summary.lower() in {"todo", "tbd", "placeholder"}:
        raise ValidationError("summary must not be a placeholder")

    changed_files = string_list(document["changedFiles"], "changedFiles")
    for index, path in enumerate(changed_files):
        relative_parts(path, f"changedFiles[{index}]")

    evidence = string_list(document["validationEvidence"], "validationEvidence")
    if status_value == "succeeded" and not evidence:
        raise ValidationError("succeeded handoff requires validationEvidence")
    for index, path in enumerate(evidence):
        parts = relative_parts(path, f"validationEvidence[{index}]")
        safe_existing_file(
            workspace, parts, f"validationEvidence[{index}]", args.max_evidence_bytes
        )

    string_list(document["unresolvedRisks"], "unresolvedRisks")
    next_action = document["recommendedNextAction"]
    if next_action is not None:
        require_nonempty_string(next_action, "recommendedNextAction")

    return {
        "valid": True,
        "schemaVersion": SCHEMA_VERSION,
        "status": status_value,
        "handoff": "/".join(handoff_parts),
        "changedFileCount": len(changed_files),
        "validationEvidenceCount": len(evidence),
    }


def main() -> int:
    args = parse_args()
    try:
        result = validate(args)
    except (ValidationError, FileNotFoundError, NotADirectoryError, OSError) as error:
        if args.json:
            print(json.dumps({"valid": False, "error": str(error)}, sort_keys=True))
        else:
            print(f"handoff invalid: {error}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        print(
            "handoff valid: "
            f"status={result['status']} evidence={result['validationEvidenceCount']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
