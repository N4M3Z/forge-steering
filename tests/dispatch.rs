//! Integration tests for `dispatch skill-load` subcommand.

use assert_cmd::Command;
use predicates::prelude::*;
use std::fs;
use tempfile::tempdir;

fn dispatch() -> Command {
    Command::new(env!("CARGO_BIN_EXE_dispatch"))
}

/// Helper: create a minimal forge layout with a module that has a skill-load.sh hook.
fn setup_module(dir: &std::path::Path, module: &str, script: &str) {
    let hooks_dir = dir.join("Modules").join(module).join("hooks");
    fs::create_dir_all(&hooks_dir).unwrap();
    fs::write(hooks_dir.join("skill-load.sh"), script).unwrap();
    // Minimal defaults.yaml (modules list not required for skill-load)
    if !dir.join("defaults.yaml").exists() {
        fs::write(dir.join("defaults.yaml"), "modules: []\n").unwrap();
    }
}

#[test]
fn skill_load_no_module_arg() {
    dispatch()
        .args(["skill-load"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Usage"));
}

#[test]
fn skill_load_missing_module() {
    let dir = tempdir().unwrap();
    fs::create_dir_all(dir.path().join("Modules")).unwrap();
    fs::write(dir.path().join("defaults.yaml"), "modules: []\n").unwrap();

    dispatch()
        .args(["skill-load", "nonexistent"])
        .env("FORGE_ROOT", dir.path())
        .env_remove("CLAUDE_PLUGIN_ROOT")
        .assert()
        .success()
        .stdout(predicate::str::is_empty());
}

#[test]
fn skill_load_runs_hook() {
    let dir = tempdir().unwrap();
    setup_module(
        dir.path(),
        "test-mod",
        "#!/bin/bash\necho 'INJECTED CONTEXT'\n",
    );

    dispatch()
        .args(["skill-load", "test-mod"])
        .env("FORGE_ROOT", dir.path())
        .env_remove("CLAUDE_PLUGIN_ROOT")
        .assert()
        .success()
        .stdout(predicate::str::contains("INJECTED CONTEXT"));
}

#[test]
fn skill_load_passes_env_vars() {
    let dir = tempdir().unwrap();
    setup_module(
        dir.path(),
        "env-test",
        "#!/bin/bash\necho \"ROOT=$FORGE_ROOT\"\necho \"MOD=$FORGE_MODULE_ROOT\"\necho \"LIB=$FORGE_LIB\"\necho \"USER=$FORGE_USER_ROOT\"\n",
    );

    let output = dispatch()
        .args(["skill-load", "env-test"])
        .env("FORGE_ROOT", dir.path())
        .env_remove("CLAUDE_PLUGIN_ROOT")
        .output()
        .unwrap();

    let stdout = String::from_utf8_lossy(&output.stdout);
    let root = dir.path().display().to_string();
    assert!(
        stdout.contains(&format!("ROOT={root}")),
        "FORGE_ROOT not set: {stdout}"
    );
    assert!(
        stdout.contains(&format!("MOD={root}/Modules/env-test")),
        "FORGE_MODULE_ROOT not set: {stdout}"
    );
    assert!(
        stdout.contains(&format!("LIB={root}/Modules/forge-lib")),
        "FORGE_LIB not set: {stdout}"
    );
}

#[test]
fn skill_load_missing_hook_file() {
    let dir = tempdir().unwrap();
    // Module dir exists but no hooks/skill-load.sh
    fs::create_dir_all(dir.path().join("Modules/no-hook")).unwrap();
    fs::write(dir.path().join("defaults.yaml"), "modules: []\n").unwrap();

    dispatch()
        .args(["skill-load", "no-hook"])
        .env("FORGE_ROOT", dir.path())
        .env_remove("CLAUDE_PLUGIN_ROOT")
        .assert()
        .success()
        .stdout(predicate::str::is_empty());
}

#[test]
fn skill_load_hook_failure_propagates() {
    let dir = tempdir().unwrap();
    setup_module(
        dir.path(),
        "fail-mod",
        "#!/bin/bash\necho 'partial output'\nexit 1\n",
    );

    dispatch()
        .args(["skill-load", "fail-mod"])
        .env("FORGE_ROOT", dir.path())
        .env_remove("CLAUDE_PLUGIN_ROOT")
        .assert()
        .failure()
        .stdout(predicate::str::contains("partial output"));
}

#[test]
fn resolve_forge_root_prefers_forge_root_env() {
    let dir = tempdir().unwrap();
    fs::write(dir.path().join("defaults.yaml"), "modules: []\n").unwrap();

    // FORGE_ROOT takes priority over CLAUDE_PLUGIN_ROOT
    dispatch()
        .args(["SessionStart"])
        .env("FORGE_ROOT", dir.path())
        .env("CLAUDE_PLUGIN_ROOT", "/nonexistent")
        .assert()
        .success();
}

#[test]
fn resolve_forge_root_uses_project_root_with_defaults() {
    let dir = tempdir().unwrap();
    fs::write(dir.path().join("defaults.yaml"), "modules: []\n").unwrap();

    // CLAUDE_PROJECT_ROOT with defaults.yaml takes priority over CLAUDE_PLUGIN_ROOT
    dispatch()
        .args(["SessionStart"])
        .env_remove("FORGE_ROOT")
        .env("CLAUDE_PROJECT_ROOT", dir.path())
        .env("CLAUDE_PLUGIN_ROOT", "/nonexistent")
        .assert()
        .success();
}
