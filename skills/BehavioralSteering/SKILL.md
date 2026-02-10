---
name: BehavioralSteering
description: Behavioral steering rules — approach, anti-patterns, and conventions. USE WHEN making implementation decisions, reviewing code, or starting any task.
---

## Approach

- Simplicity first — shell scripts over compiled tools, existing tools over new abstractions
- Scope discipline — do what was asked, then stop. Ask before expanding scope.
- Opponent review is the default first step for design and architecture tasks
- Prefer editing existing files over creating new ones
- Propose the minimal solution first. Complexity is earned, not assumed.

## Anti-patterns

When you encounter these situations, the intuitive response is wrong:

- Literature notes are NEVER summarized — capture verbatim. Summarization belongs in Permanent Notes.
- Deleted Reminders are NOT completed tasks — never conflate deletion with completion.
- Do NOT suggest MCP servers unless the user explicitly asks for one.
- Do NOT over-engineer before simplifying — always propose the simple version first.
- Do NOT add features, refactoring, or "improvements" beyond what was asked.

## Conventions

- Every ★ Insight block you output MUST also be captured as a Memory/Insights/ file. No ephemeral insights.
- Memory files (decisions, insights, ideas) link back to their originating daily note in the body.
- One-liner daily log entries — detail lives in the project work log, not the daily journal.
- One file per decision, insight, or idea — never accumulate lists in a single file.

!`"${CLAUDE_PLUGIN_ROOT}/hooks/skill-load.sh" 2>/dev/null`
!`"${CLAUDE_PLUGIN_ROOT}/Modules/forge-steering/hooks/skill-load.sh" 2>/dev/null`
