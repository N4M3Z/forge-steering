//! Audit log parsing for safety-net blocked commands.
//!
//! `parse_entries` / `format_blocked_commands` are pure; `recent_blocked_commands`
//! performs I/O (reads `~/.cc-safety-net/logs/`).

use serde::Deserialize;
use std::collections::HashMap;
use std::fmt::Write;

#[derive(Deserialize)]
pub struct AuditEntry {
    pub command: String,
    pub reason: String,
}

/// Parse JSONL content into audit entries. Skips malformed lines.
pub fn parse_entries(content: &str) -> Vec<AuditEntry> {
    content
        .lines()
        .filter(|line| !line.trim().is_empty())
        .filter_map(|line| serde_json::from_str(line).ok())
        .collect()
}

/// Deduplicate entries by command, format as a blocked-commands section.
///
/// Groups identical commands, shows count if > 1, truncates to `max_items`.
/// Returns `None` if no entries.
pub fn format_blocked_commands(entries: &[AuditEntry], max_items: usize) -> Option<String> {
    if entries.is_empty() {
        return None;
    }

    let mut groups: Vec<(&str, &str, usize)> = Vec::new();
    let mut counts: HashMap<&str, usize> = HashMap::new();

    for entry in entries {
        let count = counts.entry(&entry.command).or_insert(0);
        if *count == 0 {
            groups.push((&entry.command, &entry.reason, 0));
        }
        *count += 1;
    }

    for group in &mut groups {
        group.2 = counts[group.0];
    }

    groups.sort_by(|a, b| b.2.cmp(&a.2));

    let mut out = String::new();
    let _ = writeln!(
        out,
        "\u{1f6e1}\u{fe0f} Blocked Commands (last 24h) \u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
    );

    for (command, reason, count) in groups.iter().take(max_items) {
        let count_str = if *count > 1 {
            format!(" (\u{00d7}{count})")
        } else {
            String::new()
        };
        let _ = writeln!(out, "\u{2022} {command}{count_str} \u{2014} {reason}");
    }

    let remaining = groups.len().saturating_sub(max_items);
    if remaining > 0 {
        let _ = writeln!(out, "  \u{2026} and {remaining} more");
    }

    let _ = writeln!(
        out,
        "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
    );

    Some(out)
}

/// Read safety-net audit logs from the last 24h and format blocked commands.
pub fn recent_blocked_commands(max_items: usize) -> Option<String> {
    let home = std::env::var("HOME").ok()?;
    let log_dir = std::path::Path::new(&home).join(".cc-safety-net/logs");
    if !log_dir.is_dir() {
        return None;
    }

    let cutoff = std::time::SystemTime::now() - std::time::Duration::from_secs(24 * 3600);
    let mut all_content = String::new();

    let dir_entries = std::fs::read_dir(&log_dir).ok()?;
    for entry in dir_entries.flatten() {
        let path = entry.path();
        if path.extension().is_none_or(|e| e != "jsonl") {
            continue;
        }
        let Some(modified) = std::fs::metadata(&path)
            .ok()
            .and_then(|m| m.modified().ok())
        else {
            continue;
        };
        if modified > cutoff {
            if let Ok(content) = std::fs::read_to_string(&path) {
                all_content.push_str(&content);
                if !content.ends_with('\n') {
                    all_content.push('\n');
                }
            }
        }
    }

    let entries = parse_entries(&all_content);
    format_blocked_commands(&entries, max_items)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_entries_valid_jsonl() {
        let content = r#"{"ts":"2025-02-16T14:23:45.123Z","command":"git reset --hard","segment":"git reset --hard","reason":"destroys uncommitted changes","cwd":"/tmp"}
{"ts":"2025-02-16T14:24:00.000Z","command":"rm -rf ~/Documents","segment":"rm -rf ~/Documents","reason":"outside cwd","cwd":"/tmp"}"#;

        let entries = parse_entries(content);
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].command, "git reset --hard");
        assert_eq!(entries[0].reason, "destroys uncommitted changes");
        assert_eq!(entries[1].command, "rm -rf ~/Documents");
    }

    #[test]
    fn parse_entries_skips_malformed() {
        let content = "not json\n{\"command\":\"git reset --hard\",\"reason\":\"bad\"}\n{broken";
        let entries = parse_entries(content);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].command, "git reset --hard");
    }

    #[test]
    fn parse_entries_empty_input() {
        assert!(parse_entries("").is_empty());
        assert!(parse_entries("  \n  \n").is_empty());
    }

    #[test]
    fn format_empty_returns_none() {
        assert!(format_blocked_commands(&[], 5).is_none());
    }

    #[test]
    fn format_single_entry() {
        let entries = vec![AuditEntry {
            command: "git reset --hard".to_string(),
            reason: "destroys uncommitted changes".to_string(),
        }];
        let output = format_blocked_commands(&entries, 5).unwrap();
        assert!(output.contains("git reset --hard"));
        assert!(output.contains("destroys uncommitted changes"));
        assert!(!output.contains("\u{00d7}"));
    }

    #[test]
    fn format_deduplicates_with_count() {
        let entries = vec![
            AuditEntry {
                command: "git reset --hard".to_string(),
                reason: "destroys uncommitted changes".to_string(),
            },
            AuditEntry {
                command: "git reset --hard".to_string(),
                reason: "destroys uncommitted changes".to_string(),
            },
            AuditEntry {
                command: "rm -rf ~/".to_string(),
                reason: "home directory".to_string(),
            },
        ];
        let output = format_blocked_commands(&entries, 5).unwrap();
        assert!(output.contains("\u{00d7}2"));
        assert!(output.contains("git reset --hard"));
        assert!(output.contains("rm -rf ~/"));
    }

    #[test]
    fn format_respects_max_items() {
        let entries: Vec<AuditEntry> = (0..10)
            .map(|i| AuditEntry {
                command: format!("cmd-{i}"),
                reason: format!("reason-{i}"),
            })
            .collect();
        let output = format_blocked_commands(&entries, 3).unwrap();
        assert!(output.contains("and 7 more"));
    }

    #[test]
    fn format_sorts_by_frequency() {
        let entries = vec![
            AuditEntry {
                command: "rare-cmd".to_string(),
                reason: "rare".to_string(),
            },
            AuditEntry {
                command: "common-cmd".to_string(),
                reason: "common".to_string(),
            },
            AuditEntry {
                command: "common-cmd".to_string(),
                reason: "common".to_string(),
            },
            AuditEntry {
                command: "common-cmd".to_string(),
                reason: "common".to_string(),
            },
        ];
        let output = format_blocked_commands(&entries, 5).unwrap();
        let common_pos = output.find("common-cmd").unwrap();
        let rare_pos = output.find("rare-cmd").unwrap();
        assert!(common_pos < rare_pos, "most frequent should appear first");
    }
}
