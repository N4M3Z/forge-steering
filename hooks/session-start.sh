#!/usr/bin/env bash
# SessionStart: emit behavioral steering rules.
# Loads SYSTEM/ defaults, then any configured steering directories.
set -euo pipefail

MODULE_ROOT="$(builtin cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="${FORGE_ROOT:-$(builtin cd "$MODULE_ROOT/../.." && pwd)}"

# Source strip_front: forge-core shared lib > inline fallback
if [ -n "${FORGE_LIB:-}" ] && [ -f "$FORGE_LIB/strip-front.sh" ]; then
  source "$FORGE_LIB/strip-front.sh"
elif ! type strip_front &>/dev/null; then
  strip_front() {
    awk '
      /^---$/ && !started { started=1; skip=1; next }
      /^---$/ && skip     { skip=0; next }
      skip                { next }
      !body && /^# /      { body=1; next }
      { body=1; print }
    ' "$1"
  }
fi

# Parse steering paths from config.yaml (user overrides) or module.yaml (defaults)
CONFIG="$MODULE_ROOT/config.yaml"
[ -f "$CONFIG" ] || CONFIG="$MODULE_ROOT/module.yaml"
DIRS=()
if [ -f "$CONFIG" ]; then
  while IFS= read -r line; do
    dir=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/^["'"'"']//;s/["'"'"']$//')
    [ -n "$dir" ] && DIRS+=("$dir")
  done < <(awk '/^steering:/{f=1;next} f && /^[[:space:]]*-/{print} f && /^[^ ]/{exit}' "$CONFIG")
fi

# Collect output
output=""

# Emit SYSTEM defaults (pre-stripped, no frontmatter needed)
for f in "$MODULE_ROOT"/SYSTEM/*.md; do
  [ -f "$f" ] || continue
  output+="$(cat "$f")"$'\n\n'
done

# Emit configured steering directories
for dir in "${DIRS[@]}"; do
  # Resolve absolute or relative-to-project paths
  if [[ "$dir" == /* ]]; then
    abs_dir="$dir"
  else
    abs_dir="$PROJECT_ROOT/$dir"
  fi
  [ -d "$abs_dir" ] || continue
  for f in "$abs_dir"/*.md; do
    [ -f "$f" ] || continue
    output+="$(strip_front "$f")"$'\n\n'
  done
done

[ -n "$output" ] && printf '## Steering\n\n%s' "$output"
exit 0
