#!/usr/bin/env bash
# Inject vault steering content and user overrides into skill context.
# Called from SKILL.md via DCI (!`command`).
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

# Emit configured vault steering (directories or individual files)
for path in "${DIRS[@]}"; do
  if [[ "$path" == /* ]]; then
    abs_path="$path"
  else
    abs_path="$PROJECT_ROOT/$path"
  fi

  if [ -f "$abs_path" ]; then
    # Individual file
    strip_front "$abs_path"
    printf '\n'
  elif [ -d "$abs_path" ]; then
    # Directory — flat *.md files
    for f in "$abs_path"/*.md; do
      [ -f "$f" ] || continue
      strip_front "$f"
      printf '\n'
    done
    # Directory — nested SkillName/SKILL.md (Claude Code layout)
    for f in "$abs_path"/*/SKILL.md; do
      [ -f "$f" ] || continue
      strip_front "$f"
      printf '\n'
    done
  fi
done

# User overrides
USER_MD="$MODULE_ROOT/skills/BehavioralSteering/User.md"
if [ -f "$USER_MD" ]; then cat "$USER_MD"; fi
