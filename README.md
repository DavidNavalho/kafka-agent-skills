# Agent Skills

Reusable skills for Codex and other agents that support the `SKILL.md` format.

## Skills

| Skill | Use it for |
| --- | --- |
| [`run-agents-in-sbx`](skills/run-agents-in-sbx/SKILL.md) | Run Codex implementation tasks inside Docker `sbx` with one-writer workspaces, copied ChatGPT-subscription auth, hard timeouts, validated handoffs, and explicit recovery. Use the authenticated mode only with trusted private code. |
| [`kafka-local-lab`](skills/kafka-local-lab/SKILL.md) | Create and smoke-test disposable Docker Compose Kafka labs, from a minimal Apache Kafka setup to Confluent services, Schema Registry, Kafka Connect, and AKHQ. |
| [`kafka-architecture-investigation`](skills/kafka-architecture-investigation/SKILL.md) | Turn Kafka architecture questions into source-backed ADRs, deterministic scenarios, local proof harnesses, evidence, reports, and runbooks. |

## Install

Choose a skill and copy its complete directory into your agent's skill directory:

```bash
skill=run-agents-in-sbx

mkdir -p "$HOME/.codex/skills"
cp -R "skills/$skill" "$HOME/.codex/skills/"
```

For Claude Code, use `$HOME/.claude/skills/` instead. Install only the skills you want available to the agent.

## Testing

See [TESTING.md](TESTING.md) for each skill's evaluation method, latest recorded result, known coverage gaps, and links to the detailed harnesses and evidence.

Runtime skill files live under `skills/`. Evaluation harnesses and test records live under `evaluation/`; generated transcripts and run artifacts are ignored.

## License

MIT. See [LICENSE](LICENSE).
