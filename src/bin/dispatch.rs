//! Hook dispatcher — routes Claude Code events to forge modules.
//!
//! Behavioral orchestration: reads defaults.yaml for module order,
//! pipes Claude Code's JSON payload to each module's hook scripts.
//!
//! Usage: dispatch <EventName>
//! Stdin:  JSON payload from Claude Code
//! Stdout: Combined module output (context injection)
//! Exit:   0 = allow, 2 = block (gate mode)

use serde::Deserialize;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::{env, fs, io, process};

// -- Config types --

#[derive(Deserialize, Default)]
struct ForgeConfig {
    #[serde(default)]
    user: UserRoot,
    #[serde(default)]
    modules: Vec<String>,
}

#[derive(Deserialize, Default)]
struct UserRoot {
    #[serde(default)]
    root: String,
}

/// Module-level event config.
///
/// `None` = key absent (fall through to next tier).
/// `Some(vec![])` = explicit disable (events: []).
/// `Some(events)` = check membership.
#[derive(Deserialize, Default)]
struct EventConfig {
    events: Option<Vec<String>>,
}

#[derive(Clone, Copy)]
enum OutputMode {
    Concatenate,
    Gate,
    Passive,
}

// -- Event mapping --

fn event_to_hook_file(event: &str) -> Option<&'static str> {
    match event {
        "SessionStart" => Some("SessionStart.sh"),
        "PreToolUse" => Some("PreToolUse.sh"),
        "PostToolUse" => Some("PostToolUse.sh"),
        "UserPromptSubmit" => Some("UserPromptSubmit.sh"),
        "Stop" => Some("Stop.sh"),
        "SubagentStop" => Some("SubagentStop.sh"),
        "PreCompact" => Some("PreCompact.sh"),
        "SessionEnd" => Some("SessionEnd.sh"),
        "Notification" => Some("Notification.sh"),
        _ => None,
    }
}

fn event_to_output_mode(event: &str) -> OutputMode {
    match event {
        "SessionStart" | "PreCompact" | "PostToolUse" => OutputMode::Concatenate,
        "PreToolUse" | "Stop" | "SubagentStop" => OutputMode::Gate,
        _ => OutputMode::Passive,
    }
}

// -- 3-tier event check --

/// Check if a module handles the given event.
///
/// Tier 0: config.yaml / defaults.yaml `events:` field (authoritative if present).
/// Tier 1: module.yaml `events:` field (fallback).
/// Tier 2: hook file existence (last resort).
fn module_handles_event(module_dir: &Path, hook_file: &str, event: &str) -> bool {
    // Tier 0: config override
    if let Some(ec) = load_event_config(module_dir, "config.yaml")
        .or_else(|| load_event_config(module_dir, "defaults.yaml"))
    {
        return match ec.events {
            Some(ref events) => events.iter().any(|e| e == event),
            None => false, // key absent in parsed struct shouldn't happen here
        };
    }

    // Tier 1: module.yaml
    if let Some(ec) = load_event_config(module_dir, "module.yaml") {
        if let Some(ref events) = ec.events {
            return events.iter().any(|e| e == event);
        }
        // events key absent in module.yaml → fall through to Tier 2
    }

    // Tier 2: hook file existence
    module_dir.join("hooks").join(hook_file).exists()
}

/// Load an `EventConfig` from a YAML file in the module directory.
/// Returns `None` if the file doesn't exist.
/// Returns `Some(EventConfig { events: None })` if the file exists but has no `events:` key.
fn load_event_config(dir: &Path, filename: &str) -> Option<EventConfig> {
    let path = dir.join(filename);
    let content = fs::read_to_string(&path).ok()?;
    // No events: key → this file has no opinion on events, fall through.
    // Distinct from "events: []" which explicitly disables all events.
    if !content.lines().any(|l| l.starts_with("events:")) {
        return None;
    }
    serde_yaml::from_str(&content).ok()
}

// -- Dispatch loop --

fn run_hooks(
    handlers: &[&String],
    hook_file: &str,
    output_mode: OutputMode,
    forge_root: &Path,
    module_base: &Path,
    user_root: &str,
    stdin_data: &str,
) {
    let mut combined = String::new();

    for module_name in handlers {
        let module_dir = module_base.join(module_name);
        let hook_script = module_dir.join("hooks").join(hook_file);

        if !hook_script.exists() {
            continue;
        }

        let Ok(mut child) = Command::new("bash")
            .arg(&hook_script)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .env("FORGE_ROOT", forge_root)
            .env("FORGE_MODULE_ROOT", &module_dir)
            .env(
                "FORGE_LIB",
                std::env::var("FORGE_LIB").unwrap_or_else(|_| {
                    forge_root
                        .join("Modules/forge-lib")
                        .to_string_lossy()
                        .into_owned()
                }),
            )
            .env("FORGE_USER_ROOT", user_root)
            .spawn()
        else {
            continue;
        };

        // Write stdin to child, then close the pipe
        if let Some(mut pipe) = child.stdin.take() {
            let _ = pipe.write_all(stdin_data.as_bytes());
        }

        let Ok(output) = child.wait_with_output() else {
            continue;
        };

        let exit_code = output.status.code().unwrap_or(1);
        let stdout = String::from_utf8_lossy(&output.stdout);

        match output_mode {
            OutputMode::Concatenate => {
                if !stdout.is_empty() {
                    combined.push_str(&stdout);
                    if !stdout.ends_with('\n') {
                        combined.push('\n');
                    }
                }
            }
            OutputMode::Gate => {
                if exit_code == 2 {
                    if !stdout.is_empty() {
                        println!("{stdout}");
                    }
                    process::exit(2);
                }
                if !stdout.is_empty() {
                    combined.push_str(&stdout);
                    if !stdout.ends_with('\n') {
                        combined.push('\n');
                    }
                }
            }
            OutputMode::Passive => {}
        }
    }

    if !combined.is_empty() {
        print!("{combined}");
    }
}

// -- Prompt collection --

/// Collect DCI prompt files from handler modules.
/// Each module may have a `hooks/<Event>.md` file with static context to inject.
fn collect_hook_prompts(handlers: &[&String], module_base: &Path, event: &str) -> String {
    let mut combined = String::new();
    let md_file = format!("{event}.md");
    for module_name in handlers {
        let prompt_path = module_base.join(module_name).join("hooks").join(&md_file);
        if let Ok(content) = fs::read_to_string(&prompt_path) {
            if !content.is_empty() {
                combined.push_str(&content);
                if !content.ends_with('\n') {
                    combined.push('\n');
                }
            }
        }
    }
    combined
}

// -- Shared helpers --

/// Resolve the forge root directory from environment, cwd, or exe path.
///
/// Priority: `FORGE_ROOT` (explicit) > `CLAUDE_PROJECT_ROOT` (if it has
/// defaults.yaml, i.e. it's a forge project) > `CLAUDE_PLUGIN_ROOT`
/// (standalone plugin dir) > cwd > exe ancestry.
fn resolve_forge_root() -> PathBuf {
    if let Ok(root) = env::var("FORGE_ROOT") {
        return PathBuf::from(root);
    }
    if let Ok(root) = env::var("CLAUDE_PROJECT_ROOT") {
        let path = PathBuf::from(&root);
        if path.join("defaults.yaml").exists() {
            return path;
        }
    }
    if let Ok(root) = env::var("CLAUDE_PLUGIN_ROOT") {
        return PathBuf::from(root);
    }
    if let Ok(cwd) = env::current_dir() {
        if cwd.join("defaults.yaml").exists() {
            return cwd;
        }
    }
    let exe = env::current_exe().unwrap_or_default();
    PathBuf::from(
        exe.ancestors()
            .nth(4)
            .unwrap_or(Path::new("."))
            .to_string_lossy()
            .into_owned(),
    )
}

/// Load forge config (defaults.yaml + config.yaml overlay).
fn load_forge_config(forge_root: &Path) -> ForgeConfig {
    let defaults_yaml = forge_root.join("defaults.yaml");
    let config_yaml = forge_root.join("config.yaml");
    let mut config: ForgeConfig = if defaults_yaml.exists() {
        let content = fs::read_to_string(&defaults_yaml).unwrap_or_default();
        serde_yaml::from_str(&content).unwrap_or_default()
    } else {
        ForgeConfig::default()
    };
    if config_yaml.exists() {
        if let Ok(content) = fs::read_to_string(&config_yaml) {
            if let Ok(local) = serde_yaml::from_str::<ForgeConfig>(&content) {
                if !local.user.root.is_empty() {
                    config.user.root = local.user.root;
                }
                if !local.modules.is_empty() {
                    config.modules = local.modules;
                }
            }
        }
    }
    config
}

/// Resolve user content root from env var or config.
fn resolve_user_root(forge_root: &Path, config_root: &str) -> String {
    if let Ok(val) = env::var("FORGE_USER_ROOT") {
        if !val.is_empty() {
            return val;
        }
    }
    if !config_root.is_empty() {
        return forge_root.join(config_root).to_string_lossy().into_owned();
    }
    String::new()
}

// -- Subcommand: skill-load --

/// Execute a module's skill-load.sh hook.
///
/// Usage: `dispatch skill-load <module-name>`
///
/// Resolves the module directory, runs `hooks/skill-load.sh` with
/// the standard forge env vars. Exits silently if the hook doesn't exist.
fn skill_load(args: &[String]) {
    let Some(module_name) = args.get(2) else {
        eprintln!("Usage: dispatch skill-load <module-name>");
        process::exit(1);
    };

    let forge_root = resolve_forge_root();
    let module_dir = forge_root.join("Modules").join(module_name);
    let hook_script = module_dir.join("hooks").join("skill-load.sh");

    if !hook_script.exists() {
        process::exit(0);
    }

    let config = load_forge_config(&forge_root);
    let user_root = resolve_user_root(&forge_root, &config.user.root);

    let status = Command::new("bash")
        .arg(&hook_script)
        .env("FORGE_ROOT", &forge_root)
        .env("FORGE_MODULE_ROOT", &module_dir)
        .env(
            "FORGE_LIB",
            std::env::var("FORGE_LIB").unwrap_or_else(|_| {
                forge_root
                    .join("Modules/forge-lib")
                    .to_string_lossy()
                    .into_owned()
            }),
        )
        .env("FORGE_USER_ROOT", &user_root)
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status();

    match status {
        Ok(s) => process::exit(s.code().unwrap_or(1)),
        Err(_) => process::exit(1),
    }
}

// -- Main --

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: dispatch <EventName|skill-load> [args...]");
        process::exit(1);
    }

    // Subcommand: skill-load <module>
    if args[1] == "skill-load" {
        skill_load(&args);
        return;
    }

    let event = &args[1];
    let prompt_mode = args.get(2).is_some_and(|a| a == "--prompt");

    let Some(hook_file) = event_to_hook_file(event) else {
        process::exit(0)
    };

    let forge_root = resolve_forge_root();
    let module_base = forge_root.join("Modules");
    let config = load_forge_config(&forge_root);

    if config.modules.is_empty() {
        process::exit(0);
    }

    // Fast exit: check if any module handles this event
    let handlers: Vec<&String> = config
        .modules
        .iter()
        .filter(|m| module_handles_event(&module_base.join(m), hook_file, event))
        .collect();

    if handlers.is_empty() {
        process::exit(0);
    }

    // --prompt: backward compat no-op (Hook.md now collected in main flow)
    if prompt_mode {
        process::exit(0);
    }

    // Resolve FORGE_USER_ROOT
    let user_root = resolve_user_root(&forge_root, &config.user.root);

    let output_mode = event_to_output_mode(event);

    // Audit: surface blocked commands at session start
    if event == "SessionStart" {
        if let Some(audit_output) = forge_steering::audit::recent_blocked_commands(5) {
            print!("{audit_output}");
        }
    }

    // Read stdin once
    let mut stdin_data = String::new();
    let _ = io::Read::read_to_string(&mut io::stdin(), &mut stdin_data);

    run_hooks(
        &handlers,
        hook_file,
        output_mode,
        &forge_root,
        &module_base,
        &user_root,
        &stdin_data,
    );

    // Collect DCI prompt files from matching modules
    let prompts = collect_hook_prompts(&handlers, &module_base, event);
    if !prompts.is_empty() {
        print!("{prompts}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn event_to_hook_file_known_events() {
        assert_eq!(event_to_hook_file("SessionStart"), Some("SessionStart.sh"));
        assert_eq!(event_to_hook_file("PreToolUse"), Some("PreToolUse.sh"));
        assert_eq!(event_to_hook_file("PostToolUse"), Some("PostToolUse.sh"));
        assert_eq!(
            event_to_hook_file("UserPromptSubmit"),
            Some("UserPromptSubmit.sh")
        );
        assert_eq!(event_to_hook_file("Stop"), Some("Stop.sh"));
        assert_eq!(event_to_hook_file("SubagentStop"), Some("SubagentStop.sh"));
        assert_eq!(event_to_hook_file("PreCompact"), Some("PreCompact.sh"));
        assert_eq!(event_to_hook_file("SessionEnd"), Some("SessionEnd.sh"));
        assert_eq!(event_to_hook_file("Notification"), Some("Notification.sh"));
    }

    #[test]
    fn event_to_hook_file_unknown() {
        assert_eq!(event_to_hook_file("FakeEvent"), None);
    }

    #[test]
    fn output_mode_concatenate() {
        assert!(matches!(
            event_to_output_mode("SessionStart"),
            OutputMode::Concatenate
        ));
        assert!(matches!(
            event_to_output_mode("PreCompact"),
            OutputMode::Concatenate
        ));
    }

    #[test]
    fn output_mode_gate() {
        assert!(matches!(
            event_to_output_mode("PreToolUse"),
            OutputMode::Gate
        ));
        assert!(matches!(event_to_output_mode("Stop"), OutputMode::Gate));
        assert!(matches!(
            event_to_output_mode("SubagentStop"),
            OutputMode::Gate
        ));
    }

    #[test]
    fn output_mode_concatenate_posttooluse() {
        assert!(matches!(
            event_to_output_mode("PostToolUse"),
            OutputMode::Concatenate
        ));
    }

    #[test]
    fn output_mode_passive() {
        assert!(matches!(
            event_to_output_mode("SessionEnd"),
            OutputMode::Passive
        ));
        assert!(matches!(
            event_to_output_mode("Notification"),
            OutputMode::Passive
        ));
    }

    #[test]
    fn module_handles_event_by_file_existence() {
        let dir = tempfile::tempdir().unwrap();
        let hooks_dir = dir.path().join("hooks");
        fs::create_dir_all(&hooks_dir).unwrap();
        fs::write(hooks_dir.join("SessionStart.sh"), "#!/bin/bash\n").unwrap();

        assert!(module_handles_event(
            dir.path(),
            "SessionStart.sh",
            "SessionStart"
        ));
        assert!(!module_handles_event(dir.path(), "Stop.sh", "Stop"));
    }

    #[test]
    fn module_handles_event_config_authoritative() {
        let dir = tempfile::tempdir().unwrap();
        // Hook file exists...
        let hooks_dir = dir.path().join("hooks");
        fs::create_dir_all(&hooks_dir).unwrap();
        fs::write(hooks_dir.join("SessionStart.sh"), "#!/bin/bash\n").unwrap();

        // ...but config.yaml disables all events
        fs::write(dir.path().join("config.yaml"), "events: []\n").unwrap();

        // Config is authoritative — even though hook file exists, events: [] disables
        assert!(!module_handles_event(
            dir.path(),
            "SessionStart.sh",
            "SessionStart"
        ));
    }

    #[test]
    fn module_handles_event_config_selective() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("config.yaml"),
            "events: [SessionStart, Stop]\n",
        )
        .unwrap();

        assert!(module_handles_event(
            dir.path(),
            "SessionStart.sh",
            "SessionStart"
        ));
        assert!(module_handles_event(dir.path(), "Stop.sh", "Stop"));
        assert!(!module_handles_event(
            dir.path(),
            "PreToolUse.sh",
            "PreToolUse"
        ));
    }

    #[test]
    fn module_handles_event_module_yaml_fallback() {
        let dir = tempfile::tempdir().unwrap();
        // No config.yaml, but module.yaml with events
        fs::write(
            dir.path().join("module.yaml"),
            "name: test\nevents:\n  - PreToolUse\n",
        )
        .unwrap();

        assert!(module_handles_event(
            dir.path(),
            "PreToolUse.sh",
            "PreToolUse"
        ));
        assert!(!module_handles_event(
            dir.path(),
            "SessionStart.sh",
            "SessionStart"
        ));
    }

    #[test]
    fn load_event_config_missing_file() {
        let dir = tempfile::tempdir().unwrap();
        assert!(load_event_config(dir.path(), "nonexistent.yaml").is_none());
    }

    #[test]
    fn load_event_config_no_events_key() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("config.yaml"), "name: test\nversion: 1\n").unwrap();
        // File exists but no events: key → None (fall through to next tier)
        assert!(load_event_config(dir.path(), "config.yaml").is_none());
    }

    #[test]
    fn load_event_config_empty_events() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("config.yaml"), "events: []\n").unwrap();
        let ec = load_event_config(dir.path(), "config.yaml").unwrap();
        assert_eq!(ec.events.unwrap().len(), 0);
    }

    #[test]
    fn collect_hook_prompts_reads_event_md() {
        let dir = tempfile::tempdir().unwrap();
        let mod_name = String::from("test-mod");
        let hooks_dir = dir.path().join("test-mod").join("hooks");
        fs::create_dir_all(&hooks_dir).unwrap();
        fs::write(hooks_dir.join("SessionStart.md"), "TLP is active.\n").unwrap();

        let result = collect_hook_prompts(&[&mod_name], dir.path(), "SessionStart");
        assert_eq!(result, "TLP is active.\n");

        // No .md for Stop → empty
        let empty = collect_hook_prompts(&[&mod_name], dir.path(), "Stop");
        assert!(empty.is_empty());
    }
}
