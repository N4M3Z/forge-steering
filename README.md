# forge-steering

Behavioral steering rules for AI sessions. Loads SYSTEM defaults and user-configured vault rules at SessionStart.

## Installation

```bash
claude plugin install forge-steering
```

Or clone into your `Plugins/` directory.

Optionally install `forge-obsidian` to automatically strip Obsidian YAML frontmatter from vault files.

## How It Works

1. **SYSTEM defaults** in `SYSTEM/` load every session (pre-stripped, no frontmatter)
2. **Vault directories** configured in `config.yaml` layer on top
3. Later content has higher LLM weight (natural override)

Out of the box, forge-steering provides:
- **APPROACH.md** — simplicity first, scope discipline, opponent review
- **ANTI-PATTERNS.md** — common mistakes to avoid
- **CONVENTIONS.md** — memory and logging conventions

## Configuration

Edit `config.yaml` to point at your vault steering directories:

```yaml
steering_dirs:
  - "Vaults/Personal/Orchestration/Steering"
```

Multiple directories and vaults are supported:

```yaml
steering_dirs:
  - "Vaults/Personal/Orchestration/Steering/System"
  - "Vaults/Personal/Orchestration/Steering/User"
  - "Vaults/Work/Steering"
```

With no `steering_dirs` configured, only SYSTEM defaults load — useful for quick setup.

## Customization

Add `.md` files to your configured steering directory. If `forge-obsidian` is installed, frontmatter is stripped automatically. If not, files load as-is (extra YAML tokens, still functional).
