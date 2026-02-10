# forge-steering — Verification

> **For AI agents**: Complete this checklist after installation. Every check must pass before declaring the module installed.

## Quick check

```bash
bash tests/test.sh
```

## Manual checks

### SessionStart hook
```bash
bash hooks/session-start.sh
# Should emit SYSTEM defaults (Approach, Anti-patterns, Conventions)
```

### Steer tool
```bash
bin/steer .
# Should list external steering directories (if config.yaml has steering paths)
```

## Expected test results

- Tests covering structure, session-start.sh, steer tool, SYSTEM content
- All tests PASS
