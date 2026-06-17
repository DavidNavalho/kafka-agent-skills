#!/usr/bin/env python3
"""Update kafka-architecture-investigation tracker statuses and cursor."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys


DOC_DIR = Path("docs/kafka-architecture-investigation")

STEPS = {
    "S00-bootstrap": {
        "read": "`TRACKER.md` only",
        "write": "`TRACKER.md`",
        "next": "Confirm tracker exists and advance to S01.",
        "stop": "tracker bootstrap fails.",
    },
    "S01-user-sync": {
        "read": "`references/intake.md`, `INVESTIGATION_BRIEF.md`, `REFERENCE_ARCHITECTURE.md`",
        "write": "`INVESTIGATION_BRIEF.md`, `REFERENCE_ARCHITECTURE.md`, `TRACKER.md`",
        "next": "Ask the next intake question batch and update the brief.",
        "stop": "the research-ready gate is missing an essential user fact; ask 1-5 focused questions.",
    },
    "S02-source-research": {
        "read": "`references/kafka-internals-checklist.md`, `INVESTIGATION_BRIEF.md`, `REFERENCE_ARCHITECTURE.md`, `SOURCE_RESEARCH.md`",
        "write": "`SOURCE_RESEARCH.md`, `TRACKER.md`",
        "next": "Research docs and source code for the selected Kafka tracks.",
        "stop": "source/version scope needs clarification or a track is blocked by missing facts.",
    },
    "S03-adr": {
        "read": "`references/reporting.md`, `INVESTIGATION_BRIEF.md`, `REFERENCE_ARCHITECTURE.md`, `SOURCE_RESEARCH.md`, `ADR.md`",
        "write": "`ADR.md`, `TRACKER.md`",
        "next": "Build the ADR from user context and source research.",
        "stop": "the ADR decision depends on a missing policy, source claim, or user tradeoff.",
    },
    "S04-scenarios-spec": {
        "read": "`references/scenario-design.md`, `ADR.md`, `SCENARIO_MATRIX.tsv`, `IMPLEMENTATION_SPEC.md`",
        "write": "`SCENARIO_MATRIX.tsv`, `IMPLEMENTATION_SPEC.md`, `TRACKER.md`",
        "next": "Expand ADR claims into deterministic scenarios and small implementation steps.",
        "stop": "a scenario cannot be made deterministic or needs a user-owned policy decision.",
    },
    "S05-harness": {
        "read": "`references/harness-contract.md`, `IMPLEMENTATION_SPEC.md`, `HARNESS_SPEC.md`, `SCENARIO_MATRIX.tsv`",
        "write": "`HARNESS_SPEC.md`, `scripts/kafka-architecture-investigation/`, `TRACKER.md`",
        "next": "Build or extend the local harness and artifact contract.",
        "stop": "harness work needs external approval, credentials, licensing, or unsafe destructive access.",
    },
    "S06-execute": {
        "read": "`IMPLEMENTATION_SPEC.md`, `SCENARIO_MATRIX.tsv`, `HARNESS_SPEC.md`, active run summaries/log excerpts",
        "write": "`SOURCE_RESEARCH.md`, `ADR.md`, `SCENARIO_MATRIX.tsv`, `IMPLEMENTATION_SPEC.md`, `REPORT.md`, `TRACKER.md`",
        "next": "Run the next pending implementation step, validate, update evidence, and continue.",
        "stop": "a scenario contradicts the ADR/source research or an external blocker prevents validation.",
    },
    "S07-report-runbook": {
        "read": "`references/reporting.md`, `REPORT.md`, `RUNBOOK.md`, `ADR.md`, `SCENARIO_MATRIX.tsv`, `IMPLEMENTATION_SPEC.md`",
        "write": "`REPORT.md`, `RUNBOOK.md`, `TRACKER.md`",
        "next": "Produce final decision artifacts.",
        "stop": "reportable evidence is missing for a claim the user needs decided.",
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("project_root")
    parser.add_argument("--step-status", action="append", default=[], metavar="STEP=STATUS")
    parser.add_argument("--cursor", choices=STEPS.keys(), required=True)
    parser.add_argument("--cursor-status", choices=["pending", "in_progress", "done", "blocked"], required=True)
    return parser.parse_args()


def parse_status(value: str) -> tuple[str, str]:
    if "=" not in value:
        raise ValueError(f"--step-status must be STEP=STATUS, got {value!r}")
    step, status = value.split("=", 1)
    if step not in STEPS:
        raise ValueError(f"unknown step {step!r}")
    if status not in {"pending", "in_progress", "done", "blocked"}:
        raise ValueError(f"unknown status {status!r}")
    return step, status


def replace_cursor(text: str, cursor: str, status: str) -> str:
    step = STEPS[cursor]
    start = text.index("## Current Cursor")
    end = text.index("## Workflow Checklist")
    block = f"""## Current Cursor

This section mirrors the earliest non-`done` checklist row. If it conflicts with the checklist, the checklist wins and this section must be corrected.

When changing active steps, copy the destination checklist row's `Read Now` and `Write/Update` cells completely into this cursor. For example, S02's `Read now` includes `SOURCE_RESEARCH.md` even before source research content exists.

- Active step: {cursor}
- Status: {status}
- Read now: {step["read"]}
- Write/update: {step["write"]}
- Next action: {step["next"]}
- Stop/ask user when: {step["stop"]}

"""
    return text[:start] + block + text[end:]


def update_table_statuses(text: str, statuses: dict[str, str]) -> str:
    output = []
    for line in text.splitlines():
        if line.startswith("| S"):
            parts = line.split("|")
            if len(parts) > 3:
                step = parts[1].strip()
                if step in statuses:
                    parts[2] = f" {statuses[step]} "
                    line = "|".join(parts)
        output.append(line)
    return "\n".join(output) + "\n"


def main() -> int:
    args = parse_args()
    statuses = dict(parse_status(item) for item in args.step_status)
    tracker = Path(args.project_root) / DOC_DIR / "TRACKER.md"
    if not tracker.exists():
        print(f"missing tracker: {tracker}", file=sys.stderr)
        return 1

    text = tracker.read_text()
    text = update_table_statuses(text, statuses)
    text = replace_cursor(text, args.cursor, args.cursor_status)
    tracker.write_text(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
