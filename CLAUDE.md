@AGENTS.md

# Claude Code notes

`AGENTS.md` above is the source of truth. These notes only map it onto Claude Code.

- Read `PROJECT-CONTEXT.md` at the start of every session, as `AGENTS.md` section 1 requires. If it
  does not exist, say so and ask before working.
- Read the matching file in `rules/` before the work it covers (`AGENTS.md` section 14). Do not
  `@`-import those files here: imports load at launch and would bring back the context cost they
  were moved out to avoid.
- For a non-trivial task, use plan mode for steps 1-3 of `AGENTS.md` section 3.2 and leave it only
  after the plan is approved.
- Do not store project knowledge in Claude Code memory files. Durable knowledge goes into
  `knowledge/` (`AGENTS.md` section 12); a personal, git-ignored memory file is for machine-local
  state only.
- The role files in `agents/` can be used as Claude Code subagents: copy one into `.claude/agents/`
  and add frontmatter with `name`, `description` and, if needed, a restricted `tools` list. Keep the
  body unchanged so all tools share one definition.
- The templates in `prompts/` can be copied into `.claude/commands/` to become slash commands.
- `claude-settings.example.json` holds `permissions.ask` rules for the actions in section 11. They
  match command text, so they are a safety net, not a security boundary.
- Permission prompts are not a substitute for `AGENTS.md` section 11: an action on that list is
  asked about in the conversation even when the tool would allow it without a prompt.
