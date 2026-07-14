#!/usr/bin/env python3
"""Run a command with file-backed stdio and a host-side process-group timeout."""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stdin-file", required=True)
    parser.add_argument("--stdout-file", required=True)
    parser.add_argument("--stderr-file", required=True)
    parser.add_argument("--timeout", required=True, type=int)
    parser.add_argument("--kill-grace", type=int, default=10)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")
    if args.timeout <= 0 or args.kill_grace < 0:
        parser.error("timeouts must be positive and kill grace nonnegative")
    return args


def terminate_group(process: subprocess.Popen[bytes], sig: signal.Signals) -> None:
    if os.name == "posix":
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            pass
    elif sig == signal.SIGTERM:
        process.terminate()
    else:
        process.kill()


def normalized_return_code(return_code: int) -> int:
    if return_code >= 0:
        return min(return_code, 255)
    return min(128 + abs(return_code), 255)


def main() -> int:
    args = parse_args()
    stdin_path = Path(args.stdin_file)
    if not stdin_path.is_file():
        print(f"stdin file is missing: {stdin_path}", file=sys.stderr)
        return 2

    Path(args.stdout_file).parent.mkdir(parents=True, exist_ok=True)
    Path(args.stderr_file).parent.mkdir(parents=True, exist_ok=True)
    with (
        stdin_path.open("rb") as stdin_handle,
        open(args.stdout_file, "wb") as stdout_handle,
        open(args.stderr_file, "wb") as stderr_handle,
    ):
        try:
            process = subprocess.Popen(
                args.command,
                stdin=stdin_handle,
                stdout=stdout_handle,
                stderr=stderr_handle,
                start_new_session=(os.name == "posix"),
            )
        except FileNotFoundError as error:
            stderr_handle.write(f"command not found: {error.filename}\n".encode())
            return 127

        try:
            return normalized_return_code(process.wait(timeout=args.timeout))
        except subprocess.TimeoutExpired:
            stderr_handle.write(
                f"\n[run-bounded-command] host timeout after {args.timeout}s\n".encode()
            )
            stderr_handle.flush()
            terminate_group(process, signal.SIGTERM)
            try:
                process.wait(timeout=args.kill_grace)
            except subprocess.TimeoutExpired:
                terminate_group(process, signal.SIGKILL)
                process.wait()
            return 124


if __name__ == "__main__":
    raise SystemExit(main())
