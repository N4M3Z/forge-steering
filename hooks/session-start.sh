#!/usr/bin/env bash
# SessionStart hook: emit behavioral steering rules.
# Loads SYSTEM/ defaults, then any configured steering_dirs.
#
# Dual-mode: works standalone (CLAUDE_PLUGIN_ROOT) or as forge-core module (FORGE_MODULE_ROOT).
set -euo pipefail

MODULE_ROOT="${FORGE_MODULE_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(builtin cd "$(dirname "$0")/.." && pwd)}}"
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$(builtin cd "$MODULE_ROOT/../.." && pwd)}"

# Source strip-front: forge-core shared lib > local lib > inline fallback
HAS_STRIP=false
if [ -n "${FORGE_LIB:-}" ] && [ -f "$FORGE_LIB/strip-front.sh" ]; then
  source "$FORGE_LIB/strip-front.sh"
  HAS_STRIP=true
elif [ -f "$MODULE_ROOT/lib/strip-front.sh" ]; then
  source "$MODULE_ROOT/lib/strip-front.sh"
  HAS_STRIP=true
fi

# Parse steering_dirs from config.yaml (no yq dependency)
CONFIG="$MODULE_ROOT/config.yaml"
DIRS=()
if [ -f "$CONFIG" ]; then
  while IFS= read -r line; do
    dir=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/^["'"'"']//;s/["'"'"']$//')
    [ -n "$dir" ] && DIRS+=("$dir")
  done < <(grep -A 100 '^steering_dirs:' "$CONFIG" | tail -n +2 | grep '^[[:space:]]*-' || true)
fi

# Collect output
output=""

# Emit SYSTEM defaults (pre-stripped, just cat)
for f in "$MODULE_ROOT"/SYSTEM/*.md; do
  [ -f "$f" ] || continue
  output+="$(cat "$f")"$'\n\n'
done

# Emit configured steering dirs
for dir in "${DIRS[@]}"; do
  abs_dir="$PROJECT_ROOT/$dir"
  [ -d "$abs_dir" ] || continue
  for f in "$abs_dir"/*.md; do
    [ -f "$f" ] || continue
    if [ "$HAS_STRIP" = true ]; then
      output+="$(strip_front "$f")"$'\n\n'
    else
      output+="$(cat "$f")"$'\n\n'
    fi
  done
done

[ -n "$output" ] && printf '## Steering\n\n%s' "$output"
exit 0
