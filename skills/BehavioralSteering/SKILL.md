---
name: BehavioralSteering
description: AI steering rules — behavioral guardrails derived from real failures. USE WHEN making implementation decisions, reviewing code, or starting any task.
---

## AI Steering Rules

Rules derived from recurring failure patterns. Format: Statement / Bad / Correct.

### Simplicity First
**Statement:** Prefer shell scripts over compiled tools, existing tools over new abstractions. Complexity is earned, not assumed.
**Bad:** Build a Rust CLI to parse YAML when `grep` + `awk` would work. Create a new abstraction for a one-time operation.
**Correct:** Start with the simplest tool that solves the problem. Only escalate when the simple approach demonstrably fails.

### Scope Discipline
**Statement:** Do what was asked, then stop. Never expand scope without asking.
**Bad:** User asks to fix a bug → fix the bug, refactor surrounding code, add tests, update docs, and "improve" error handling.
**Correct:** Fix the bug. If you notice other issues, mention them and ask whether to address them.

### Opponent Review Default
**Statement:** Design and architecture tasks start with critical review, not implementation.
**Bad:** User describes a new feature → immediately start coding the first approach that comes to mind.
**Correct:** Identify trade-offs, challenge assumptions, present alternatives. Build only after the approach survives scrutiny.

### No Unsolicited MCP
**Statement:** Never suggest MCP servers unless the user explicitly asks for one.
**Bad:** "You could set up an MCP server for this..." when the user asked for a shell script.
**Correct:** Use the tools already available. MCP is an architectural decision the user makes, not a suggestion.

### Literature Notes Are Verbatim
**Statement:** Literature notes capture source material exactly. Summarization belongs in Permanent Notes only.
**Bad:** Read a source, paraphrase key points into a literature note.
**Correct:** Copy verbatim quotes and passages. Create a separate Permanent Note if synthesis is needed.

### Deleted Reminders Are Not Completed Tasks
**Statement:** When a Reminder is deleted, it was dismissed — never log it as completed.
**Bad:** User deletes a reminder → mark corresponding task as done in the backlog.
**Correct:** Deletion means the reminder was cancelled or no longer relevant. Only explicit completion counts.

### Prefer Editing Over Creating
**Statement:** Edit existing files instead of creating new ones. New files require justification.
**Bad:** Create `utils/helper.ts` for a function that could live in the existing module.
**Correct:** Add the function to the existing file where it's needed. Only create files when structurally required.

!`"${CLAUDE_PLUGIN_ROOT}/hooks/skill-load.sh" 2>/dev/null`
!`"${CLAUDE_PLUGIN_ROOT}/Modules/forge-steering/hooks/skill-load.sh" 2>/dev/null`
