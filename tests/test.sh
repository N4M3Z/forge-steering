#!/usr/bin/env bash
# forge-steering module tests.
# Run: bash tests/test.sh
set -uo pipefail

MODULE_ROOT="$(builtin cd "$(dirname "$0")/.." && pwd)"
PASS=0 FAIL=0

# --- Helpers ---

_tmpdirs=()
setup() {
  _tmpdir=$(mktemp -d)
  _tmpdirs+=("$_tmpdir")
}
cleanup_all() {
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

# module.yaml has required fields
if [ -f "$MODULE_ROOT/module.yaml" ]; then
  printf '  PASS  module.yaml exists\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  module.yaml missing\n'; FAIL=$((FAIL + 1))
fi

mod_yaml=$(cat "$MODULE_ROOT/module.yaml")
assert_contains "module.yaml has name" "name:" "$mod_yaml"
assert_contains "module.yaml has version" "version:" "$mod_yaml"
assert_contains "module.yaml has events" "events:" "$mod_yaml"
assert_contains "module.yaml has metadata" "metadata:" "$mod_yaml"

# hooks.json is valid JSON
if [ -f "$MODULE_ROOT/hooks/hooks.json" ] && python3 -c "import json; json.load(open('$MODULE_ROOT/hooks/hooks.json'))" 2>/dev/null; then
  printf '  PASS  hooks.json is valid JSON\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  hooks.json invalid or missing\n'; FAIL=$((FAIL + 1))
fi

# plugin.json is valid JSON
if [ -f "$MODULE_ROOT/.claude-plugin/plugin.json" ] && python3 -c "import json; json.load(open('$MODULE_ROOT/.claude-plugin/plugin.json'))" 2>/dev/null; then
  printf '  PASS  plugin.json is valid JSON\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  plugin.json invalid or missing\n'; FAIL=$((FAIL + 1))
fi

# session-start.sh exists
if [ -f "$MODULE_ROOT/hooks/session-start.sh" ]; then
  printf '  PASS  session-start.sh exists\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  session-start.sh missing\n'; FAIL=$((FAIL + 1))
fi

# bin/steer exists and is executable
if [ -x "$MODULE_ROOT/bin/steer" ]; then
  printf '  PASS  bin/steer exists and is executable\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  bin/steer missing or not executable\n'; FAIL=$((FAIL + 1))
fi

# SYSTEM/ directory with default content
if [ -d "$MODULE_ROOT/SYSTEM" ]; then
  printf '  PASS  SYSTEM/ directory exists\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  SYSTEM/ directory missing\n'; FAIL=$((FAIL + 1))
fi

for f in APPROACH.md ANTI-PATTERNS.md CONVENTIONS.md; do
  if [ -f "$MODULE_ROOT/SYSTEM/$f" ]; then
    printf '  PASS  SYSTEM/%s exists\n' "$f"; PASS=$((PASS + 1))
  else
    printf '  FAIL  SYSTEM/%s missing\n' "$f"; FAIL=$((FAIL + 1))
  fi
done

# ============================================================
# session-start.sh tests
# ============================================================
printf '\n--- session-start.sh ---\n'

# Emits SYSTEM defaults (no config.yaml needed)
setup
result=$(FORGE_ROOT="$_tmpdir" bash "$MODULE_ROOT/hooks/session-start.sh" 2>/dev/null) || true
assert_contains "session-start: emits Steering header" "## Steering" "$result"
assert_contains "session-start: emits Approach content" "Simplicity first" "$result"
assert_contains "session-start: emits Anti-patterns content" "Anti-patterns" "$result"
assert_contains "session-start: emits Conventions content" "Conventions" "$result"

# Exits 0
exit_code=0
FORGE_ROOT=/tmp bash "$MODULE_ROOT/hooks/session-start.sh" >/dev/null 2>&1 || exit_code=$?
assert_eq "session-start.sh exits 0" "0" "$exit_code"

# With configured steering directory
setup
mkdir -p "$_tmpdir/steering"
printf '## Custom Rule\n\nAlways test first.\n' > "$_tmpdir/steering/custom.md"
mkdir -p "$_tmpdir/module"
command cp -R "$MODULE_ROOT/SYSTEM" "$_tmpdir/module/SYSTEM"
command cp "$MODULE_ROOT/hooks/session-start.sh" "$_tmpdir/module/"
mkdir -p "$_tmpdir/module/hooks"
command cp "$MODULE_ROOT/hooks/session-start.sh" "$_tmpdir/module/hooks/"
printf 'steering:\n  - "%s"\n' "$_tmpdir/steering" > "$_tmpdir/module/config.yaml"
result=$(FORGE_ROOT="$_tmpdir" bash "$_tmpdir/module/hooks/session-start.sh" 2>/dev/null) || true
assert_contains "session-start: loads configured dir" "Always test first" "$result"

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

# steer exits 0 in all cases
exit_code=0
"$MODULE_ROOT/bin/steer" "$_tmpdir/mod" >/dev/null 2>&1 || exit_code=$?
assert_eq "steer exits 0" "0" "$exit_code"

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
