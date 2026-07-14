# Agent Skills

This repository contains reusable agent skills.

## Layout

```text
skills/
  run-agents-in-sbx/
    SKILL.md
    agents/
    assets/
    references/
    scripts/
  kafka-local-lab/
    SKILL.md
    assets/
    references/
    scripts/
  kafka-architecture-investigation/
    SKILL.md
    agents/
    assets/
    references/
evaluation/
  kafka-local-lab/
    run-model-matrix.sh
    evaluation-plan.md
    evaluation-results.md
```

Runtime skill folders stay self-contained under `skills/<skill-name>`. Evaluation tooling and generated results live outside the skill so published skills do not carry test harness noise.

## Current Skills

- `run-agents-in-sbx`: run host-controlled Codex implementation lanes inside Docker `sbx` with isolated ChatGPT-subscription auth, one-writer workspaces, bounded noninteractive execution, durable handoffs, evidence capture, and recovery-aware cleanup.
- `kafka-local-lab`: create and smoke-test local Docker-based Kafka labs, including Apache Kafka, Confluent Kafka, Schema Registry, Kafka Connect, and AKHQ.
- `kafka-architecture-investigation`: guide source-backed Kafka architecture investigations, ADRs, deterministic scenario design, harness evidence, runbooks, and reports.

## Install Locally

For Codex:

```bash
mkdir -p "$HOME/.codex/skills"
cp -R skills/run-agents-in-sbx "$HOME/.codex/skills/"
cp -R skills/kafka-local-lab "$HOME/.codex/skills/"
cp -R skills/kafka-architecture-investigation "$HOME/.codex/skills/"
```

For Claude Code:

```bash
mkdir -p "$HOME/.claude/skills"
cp -R skills/run-agents-in-sbx "$HOME/.claude/skills/"
cp -R skills/kafka-local-lab "$HOME/.claude/skills/"
cp -R skills/kafka-architecture-investigation "$HOME/.claude/skills/"
```

## Evaluate

From the repository root:

```bash
mkdir -p /tmp/agent-skills-eval
sbx create \
  --name agent-skills-eval \
  --memory 8g \
  --cpus 4 \
  codex \
  /tmp/agent-skills-eval \
  "$(pwd):ro"
```

```bash
evaluation/kafka-local-lab/run-model-matrix.sh \
  --runner codex \
  --scenarios "default full" \
  --models "gpt-5.4-mini" \
  --efforts "low"
```

The generated `evaluation-runs/` directories are intentionally ignored.

## License

MIT. See [LICENSE](LICENSE).

## Publishing Checklist

- Decide whether to publish evaluation summaries only, or also selected redacted transcripts.
- Run `evaluation/kafka-local-lab/run-model-matrix.sh` for the release baseline.
