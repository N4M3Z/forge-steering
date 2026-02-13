#!/usr/bin/env bash
# forge-steering module tests.
# Run: bash Modules/forge-steering/tests/test.sh
set -uo pipefail

MODULE_ROOT="$(builtin cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(builtin cd "$MODULE_ROOT/../.." && pwd)"
PASS=0 FAIL=0

# --- Helpers ---

_tmpdirs=()
setup() {
  _tmpdir=$(mktemp -d)
  _tmpdirs+=("$_tmpdir")
}
cleanup_all() {
  # Restore config.yaml if moved aside during tests
  [ -f "$MODULE_ROOT/config.yaml.bak" ] && command mv "$MODULE_ROOT/config.yaml.bak" "$MODULE_ROOT/config.yaml"
  command rm -f "$MODULE_ROOT/config.yaml.test"
  for d in "${_tmpdirs[@]}"; do
    [ -d "$d" ] && command rm -rf "$d"
  done
}
trap cleanup_all EXIT

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  PASS  %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n' "$label"
    printf '    expected: %s\n' "$(echo "$expected" | head -5)"
    printf '    actual:   %s\n' "$(echo "$actual" | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    printf '  PASS  %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n' "$label"
    printf '    expected to contain: %s\n' "$needle"
    printf '    actual: %s\n' "$(echo "$haystack" | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    printf '  FAIL  %s\n' "$label"
    printf '    should not contain: %s\n' "$needle"
    FAIL=$((FAIL + 1))
  else
    printf '  PASS  %s\n' "$label"
    PASS=$((PASS + 1))
  fi
}

assert_empty() {
  local label="$1" actual="$2"
  if [ -z "$actual" ]; then
    printf '  PASS  %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n' "$label"
    printf '    expected empty, got: %s\n' "$(echo "$actual" | head -3)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== forge-steering tests ==="

# ============================================================
# Structure tests
# ============================================================
printf '\n--- Structure ---\n'

# SKILL.md exists
[ -f "$MODULE_ROOT/skills/BehavioralSteering/SKILL.md" ] \
  && { printf '  PASS  SKILL.md exists\n'; PASS=$((PASS + 1)); } \
  || { printf '  FAIL  SKILL.md missing\n'; FAIL=$((FAIL + 1)); }

# SKILL.md has name: in frontmatter
result=$(awk '/^---$/{if(n++)exit;next} n && /^name:/{print; exit}' "$MODULE_ROOT/skills/BehavioralSteering/SKILL.md")
[ -n "$result" ] \
  && { printf '  PASS  SKILL.md has name: frontmatter\n'; PASS=$((PASS + 1)); } \
  || { printf '  FAIL  SKILL.md missing name: frontmatter\n'; FAIL=$((FAIL + 1)); }

# SKILL.md has two !` lines (DCI blocks)
bang_count=$(grep -c '^!\`' "$MODULE_ROOT/skills/BehavioralSteering/SKILL.md" || true)
assert_eq "SKILL.md has two !command blocks" "2" "$bang_count"

# module.yaml has required fields
[ -f "$MODULE_ROOT/module.yaml" ] \
  && { printf '  PASS  module.yaml exists\n'; PASS=$((PASS + 1)); } \
  || { printf '  FAIL  module.yaml missing\n'; FAIL=$((FAIL + 1)); }

mod_yaml=$(cat "$MODULE_ROOT/module.yaml")
assert_contains "module.yaml has name" "name:" "$mod_yaml"
assert_contains "module.yaml has events" "events:" "$mod_yaml"
assert_contains "module.yaml has metadata" "metadata:" "$mod_yaml"

# hooks.json is valid JSON
[ -f "$MODULE_ROOT/hooks/hooks.json" ] && python3 -c "import json; json.load(open('$MODULE_ROOT/hooks/hooks.json'))" 2>/dev/null \
  && { printf '  PASS  hooks.json is valid JSON\n'; PASS=$((PASS + 1)); } \
  || { printf '  FAIL  hooks.json invalid or missing\n'; FAIL=$((FAIL + 1)); }

# plugin.json is valid JSON with skills field
[ -f "$MODULE_ROOT/.claude-plugin/plugin.json" ] && python3 -c "import json; d=json.load(open('$MODULE_ROOT/.claude-plugin/plugin.json')); assert 'skills' in d" 2>/dev/null \
  && { printf '  PASS  plugin.json has skills field\n'; PASS=$((PASS + 1)); } \
  || { printf '  FAIL  plugin.json missing or lacks skills field\n'; FAIL=$((FAIL + 1)); }

# session-start.sh exists
[ -f "$MODULE_ROOT/hooks/session-start.sh" ] \
  && { printf '  PASS  session-start.sh exists\n'; PASS=$((PASS + 1)); } \
  || { printf '  FAIL  session-start.sh missing\n'; FAIL=$((FAIL + 1)); }

# skill-load.sh exists and is executable
[ -x "$MODULE_ROOT/hooks/skill-load.sh" ] \
  && { printf '  PASS  skill-load.sh exists and is executable\n'; PASS=$((PASS + 1)); } \
  || { printf '  FAIL  skill-load.sh missing or not executable\n'; FAIL=$((FAIL + 1)); }

# bin/steer exists and is executable (cross-module tool)
[ -x "$MODULE_ROOT/bin/steer" ] \
  && { printf '  PASS  bin/steer exists and is executable\n'; PASS=$((PASS + 1)); } \
  || { printf '  FAIL  bin/steer missing or not executable\n'; FAIL=$((FAIL + 1)); }

# No SYSTEM/ directory (content merged into SKILL.md)
[ ! -d "$MODULE_ROOT/SYSTEM" ] \
  && { printf '  PASS  SYSTEM/ directory removed\n'; PASS=$((PASS + 1)); } \
  || { printf '  FAIL  SYSTEM/ directory still exists\n'; FAIL=$((FAIL + 1)); }

# ============================================================
# session-start.sh tests
# ============================================================
printf '\n--- session-start.sh ---\n'

# With forge-load available (convention mode)
# Temporarily move config.yaml aside — its steering: key puts forge-load into
# config mode, which expects system:/user: keys. Convention mode auto-discovers
# skills/*/SKILL.md.
FORGE_LOAD="$PROJECT_ROOT/Modules/forge-load/src"
if [ -f "$FORGE_LOAD/load.sh" ]; then
  [ -f "$MODULE_ROOT/config.yaml" ] && command mv "$MODULE_ROOT/config.yaml" "$MODULE_ROOT/config.yaml.bak"
  result=$(FORGE_ROOT="$PROJECT_ROOT" bash "$MODULE_ROOT/hooks/session-start.sh" 2>/dev/null) || true
  [ -f "$MODULE_ROOT/config.yaml.bak" ] && command mv "$MODULE_ROOT/config.yaml.bak" "$MODULE_ROOT/config.yaml"
  assert_contains "session-start (forge-load): emits name" "name: BehavioralSteering" "$result"
  assert_contains "session-start (forge-load): emits description" "description:" "$result"
  # --index-only should NOT emit body
  assert_not_contains "session-start (forge-load): no body" "## Approach" "$result"

  # Test awk fallback: hide forge-load temporarily
  setup
  result=$(FORGE_ROOT="$_tmpdir" bash "$MODULE_ROOT/hooks/session-start.sh" 2>/dev/null) || true
  assert_contains "session-start (awk fallback): has name:" "name:" "$result"
else
  printf '  SKIP  forge-load not available\n'
fi

# Both paths exit 0
exit_code=0
bash "$MODULE_ROOT/hooks/session-start.sh" >/dev/null 2>&1 || exit_code=$?
assert_eq "session-start.sh exits 0" "0" "$exit_code"

# ============================================================
# DCI expansion tests
# ============================================================
printf '\n--- DCI expansion ---\n'

# DCI line 1: standalone path (module root = plugin root)
exit_code=0
"$MODULE_ROOT/hooks/skill-load.sh" >/dev/null 2>&1 || exit_code=$?
assert_eq "DCI standalone: skill-load.sh exits 0" "0" "$exit_code"

# DCI line 2: forge-core path (project root + Modules/...)
exit_code=0
"$PROJECT_ROOT/Modules/forge-steering/hooks/skill-load.sh" >/dev/null 2>&1 || exit_code=$?
assert_eq "DCI forge-core: skill-load.sh exits 0" "0" "$exit_code"

# skill-load.sh with configured vault directory
setup
mkdir -p "$_tmpdir/steering"
cat > "$_tmpdir/steering/custom.md" <<'FIXTURE'
---
title: Custom
---

## Custom Rule

Always test first.
FIXTURE
[ -f "$MODULE_ROOT/config.yaml" ] && command cp "$MODULE_ROOT/config.yaml" "$MODULE_ROOT/config.yaml.bak"
printf 'steering:\n  - "%s"\n' "$_tmpdir/steering" > "$MODULE_ROOT/config.yaml"
result=$("$MODULE_ROOT/hooks/skill-load.sh" 2>/dev/null) || true
if [ -f "$MODULE_ROOT/config.yaml.bak" ]; then
  command mv "$MODULE_ROOT/config.yaml.bak" "$MODULE_ROOT/config.yaml"
else
  command rm -f "$MODULE_ROOT/config.yaml"
fi
assert_contains "skill-load.sh: loads vault steering" "Always test first" "$result"
assert_not_contains "skill-load.sh: strips frontmatter" "title: Custom" "$result"

# skill-load.sh with no User.md produces no user content
result=$("$MODULE_ROOT/hooks/skill-load.sh" 2>/dev/null) || true
assert_not_contains "skill-load.sh: no User.md → no user content" "My Overrides" "$result"

# skill-load.sh with nested SkillName/SKILL.md directories
setup
mkdir -p "$_tmpdir/steering/TestSkill"
cat > "$_tmpdir/steering/TestSkill/SKILL.md" <<'FIXTURE'
---
name: TestSkill
description: A test skill
---

## Test Nested Rule

Nested SKILL.md works.
FIXTURE
[ -f "$MODULE_ROOT/config.yaml" ] && command cp "$MODULE_ROOT/config.yaml" "$MODULE_ROOT/config.yaml.bak"
printf 'steering:\n  - "%s"\n' "$_tmpdir/steering" > "$MODULE_ROOT/config.yaml"
result=$("$MODULE_ROOT/hooks/skill-load.sh" 2>/dev/null) || true
if [ -f "$MODULE_ROOT/config.yaml.bak" ]; then
  command mv "$MODULE_ROOT/config.yaml.bak" "$MODULE_ROOT/config.yaml"
else
  command rm -f "$MODULE_ROOT/config.yaml"
fi
assert_contains "skill-load.sh: loads nested SKILL.md" "Nested SKILL.md works" "$result"
assert_not_contains "skill-load.sh: strips nested frontmatter" "name: TestSkill" "$result"

# skill-load.sh with individual file path
setup
mkdir -p "$_tmpdir"
cat > "$_tmpdir/single-rule.md" <<'FIXTURE'
---
title: Single
---

## Single Rule

File path works.
FIXTURE
[ -f "$MODULE_ROOT/config.yaml" ] && command cp "$MODULE_ROOT/config.yaml" "$MODULE_ROOT/config.yaml.bak"
printf 'steering:\n  - "%s"\n' "$_tmpdir/single-rule.md" > "$MODULE_ROOT/config.yaml"
result=$("$MODULE_ROOT/hooks/skill-load.sh" 2>/dev/null) || true
if [ -f "$MODULE_ROOT/config.yaml.bak" ]; then
  command mv "$MODULE_ROOT/config.yaml.bak" "$MODULE_ROOT/config.yaml"
else
  command rm -f "$MODULE_ROOT/config.yaml"
fi
assert_contains "skill-load.sh: loads individual file" "File path works" "$result"
assert_not_contains "skill-load.sh: strips file frontmatter" "title: Single" "$result"

# ============================================================
# User.md tests
# ============================================================
printf '\n--- User.md ---\n'

# No User.md by default
SKILL_DIR="$MODULE_ROOT/skills/BehavioralSteering"
[ ! -f "$SKILL_DIR/User.md" ] \
  && { printf '  PASS  User.md does not exist by default\n'; PASS=$((PASS + 1)); } \
  || { printf '  FAIL  User.md should not exist by default\n'; FAIL=$((FAIL + 1)); }

# Create temp User.md and verify it loads
setup
USER_MD="$_tmpdir/User.md"
printf '## My Overrides\n\n- Custom rule\n' > "$USER_MD"
result=$(F="$USER_MD"; [ -f "$F" ] && cat "$F")
assert_contains "User.md cat: content emitted" "Custom rule" "$result"

# ============================================================
# bin/steer tests
# ============================================================
printf '\n--- bin/steer ---\n'

# No config.yaml → no output
setup
mkdir -p "$_tmpdir/mod"
result=$("$MODULE_ROOT/bin/steer" "$_tmpdir/mod" 2>/dev/null)
assert_empty "steer: no config → no output" "$result"

# With existing steering directory
setup
mkdir -p "$_tmpdir/mod" "$_tmpdir/steering"
printf 'test-file\n' > "$_tmpdir/steering/conventions.md"
printf 'steering:\n  - %s\n' "$_tmpdir/steering" > "$_tmpdir/mod/config.yaml"
result=$("$MODULE_ROOT/bin/steer" "$_tmpdir/mod" 2>/dev/null)
assert_contains "steer: existing dir → tree output" "conventions.md" "$result"

# With non-existent directory
setup
mkdir -p "$_tmpdir/mod"
printf 'steering:\n  - /nonexistent/path/1234\n' > "$_tmpdir/mod/config.yaml"
result=$("$MODULE_ROOT/bin/steer" "$_tmpdir/mod" 2>/dev/null)
assert_empty "steer: non-existent dir → no output" "$result"

# With individual file path
setup
mkdir -p "$_tmpdir/mod"
printf 'single rule content\n' > "$_tmpdir/single.md"
printf 'steering:\n  - %s\n' "$_tmpdir/single.md" > "$_tmpdir/mod/config.yaml"
result=$("$MODULE_ROOT/bin/steer" "$_tmpdir/mod" 2>/dev/null)
assert_contains "steer: file path → prints path" "$_tmpdir/single.md" "$result"

# steer exits 0 in all cases
exit_code=0
"$MODULE_ROOT/bin/steer" "$_tmpdir/mod" >/dev/null 2>&1 || exit_code=$?
assert_eq "steer exits 0" "0" "$exit_code"

# ============================================================
# Vault steering structure
# ============================================================
printf '\n--- Vault steering structure ---\n'

VAULT_STEERING="${FORGE_USER_ROOT:-$PROJECT_ROOT/Vaults/Personal}/Orchestration/Steering"
if [ -d "$VAULT_STEERING" ]; then
  for skill in VaultOperations MemoryInsights BacklogJournals; do
    [ -f "$VAULT_STEERING/$skill/SKILL.md" ] \
      && { printf '  PASS  %s/SKILL.md exists\n' "$skill"; PASS=$((PASS + 1)); } \
      || { printf '  FAIL  %s/SKILL.md missing\n' "$skill"; FAIL=$((FAIL + 1)); }
  done
  # No flat .md files remaining
  flat_count=$(find "$VAULT_STEERING" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "No flat .md files in Steering/" "0" "$flat_count"
else
  printf '  SKIP  Vault steering directory not found\n'
fi

# ============================================================
# Config override
# ============================================================
printf '\n--- Config override ---\n'

if [ -x "$PROJECT_ROOT/Core/bin/dispatch" ]; then
  # events: [] disables module
  [ -f "$MODULE_ROOT/config.yaml" ] && command cp "$MODULE_ROOT/config.yaml" "$MODULE_ROOT/config.yaml.bak"
  printf 'events: []\n' > "$MODULE_ROOT/config.yaml"
  result=$(CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$PROJECT_ROOT/Core/bin/dispatch" SessionStart < /dev/null 2>/dev/null) || true
  assert_not_contains "config events: [] disables module" "BehavioralSteering" "$result"
  if [ -f "$MODULE_ROOT/config.yaml.bak" ]; then
    command mv "$MODULE_ROOT/config.yaml.bak" "$MODULE_ROOT/config.yaml"
  else
    command rm -f "$MODULE_ROOT/config.yaml"
  fi
else
  printf '  SKIP  dispatch binary not available\n'
fi

# ============================================================
# Naming consistency
# ============================================================
printf '\n--- Naming consistency ---\n'

mod_name=$(awk '/^name:/{print $2; exit}' "$MODULE_ROOT/module.yaml")
plugin_name=$(python3 -c "import json; print(json.load(open('$MODULE_ROOT/.claude-plugin/plugin.json'))['name'])" 2>/dev/null)
assert_eq "module.yaml name matches plugin.json name" "$mod_name" "$plugin_name"

mod_version=$(awk '/^version:/{print $2; exit}' "$MODULE_ROOT/module.yaml")
plugin_version=$(python3 -c "import json; print(json.load(open('$MODULE_ROOT/.claude-plugin/plugin.json'))['version'])" 2>/dev/null)
assert_eq "module.yaml version matches plugin.json version" "$mod_version" "$plugin_version"

# ============================================================
# Summary
# ============================================================
printf '\n=== Results ===\n'
printf '  %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
