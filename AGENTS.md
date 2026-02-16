# forge-steering

Behavioral steering rules — guardrails derived from real AI coding failures. Content module (markdown rules + shell loader, no Rust).

## Testing

```bash
bash tests/test.sh
```

## Structure

- `hooks/session-start.sh` — loads steering rules at session start
- `bin/steer` — rule management utility
- `skills/BehavioralSteering/` — access steering rules on demand

## Rule Format

Statement/Bad/Correct triplets. Each rule describes: a behavioral statement, what going wrong looks like, and what correct behavior looks like.

## Code Style

- Shell: `set -euo pipefail`, `shellcheck` clean
- Markdown: Obsidian-compatible, wikilinks for cross-references
