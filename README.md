# forge-steering

AI Steering Rules in Statement/Bad/Correct format. Provides behavioural guardrails that tell AI tools how to approach tasks, what mistakes to avoid, and what correct behaviour looks like.

Adopted from [PAI](https://github.com/danielmiessler/Personal_AI_Infrastructure)'s AI Steering Rules pattern.

## Layer

**Behaviour** — part of forge-core's three-layer architecture (Identity / Behaviour / Knowledge). Loaded at session start via `SessionStart` hook.

## How It Works

forge-steering ships a single skill — `BehavioralSteering` — containing rules in Statement/Bad/Correct format:

```markdown
### Simplicity First

**Statement:** Prefer shell scripts over compiled tools, existing tools over new abstractions.

**Bad:** Build a Rust CLI to parse YAML when `grep` + `awk` would work.

**Correct:** Start with the simplest tool that solves the problem. Only escalate
when the simple approach demonstrably fails.
```

Each rule has three parts:
- **Statement** — what should happen
- **Bad** — a concrete example of wrong behaviour
- **Correct** — a concrete example of right behaviour

This gives the AI unambiguous behavioural anchors — not vague principles, but specific patterns to match and avoid.

## Skills

| Skill | Purpose |
|-------|---------|
| `BehavioralSteering` | AI guardrails — simplicity, scope discipline, opponent review, etc. |

## Configuration

**module.yaml** — checked into git:

```yaml
name: forge-steering
version: 0.3.0
description: Behavioral steering rules. USE WHEN making implementation decisions.
events:
  - SessionStart
```

**config.yaml** — gitignored, user creates to point at vault workspace:

```yaml
steering:
  - "Vaults/Personal/Orchestration/Behaviour"
```

When `steering:` paths contain subdirectories with `SKILL.md` files, `forge-update.sh` auto-injects them into `plugin.json` as additional skill sources. This enables the vault Behaviour workspace for drafting and iterating on rules in Obsidian before promoting them to modules.

With no `steering:` paths configured, only the module's built-in `BehavioralSteering` skill loads.

## Vault Behaviour Workspace

Rules can be authored in an Obsidian vault for iterative editing:

1. `/Draft BehavioralSteering` — pulls the skill into `Orchestration/Behaviour/` for editing
2. Edit in Obsidian — the vault version overrides the module version (plugin.json load order)
3. `/Promote BehavioralSteering` — pushes the edited skill back to the module

See `forge-obsidian` for the `/Draft` and `/Promote` skills.

## Dependencies

None. forge-steering is self-contained — it provides a skill file with no hooks, no binaries, and no external dependencies beyond forge-core's skill discovery.
