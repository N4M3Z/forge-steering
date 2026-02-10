# forge-steering — Installation

> **For AI agents**: This guide covers installation of forge-steering. Follow the steps for your deployment mode.

## As part of forge-core

Add as a submodule:

```bash
git submodule add https://github.com/N4M3Z/forge-steering.git Modules/forge-steering
```

Then add the module to `forge.yaml` under the SessionStart event.

## Standalone (Claude Code plugin)

```bash
claude plugin install forge-steering
```

Or install from a local path during development:

```bash
claude plugin install /path/to/forge-steering
```

## Configuration

Create `config.yaml` (gitignored) with paths to your steering directories:

```yaml
steering:
  - /path/to/your/steering/directory/
```

Paths can be absolute or relative to the project root.

### Disable SessionStart hook

Claude Code loads context natively — the SessionStart hook is for other providers. To disable it:

```yaml
# config.yaml
events: []
```
