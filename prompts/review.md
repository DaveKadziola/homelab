# Prompt: review a change

Act as the reviewer role (`agents/reviewer.md`) and follow `AGENTS.md`.

Change: <branch vs base | diff | file list>
Intent: <one sentence, or the issue text>
Focus: <optional: security / scripts idempotency / docs / everything>

Rules:
- Read `PROJECT-CONTEXT.md` for conventions and commands first.
- Every finding needs `file:line` and evidence; label suspicions `Assumption:`.
- Run lint and tests only if allowed: <yes / no>. If not run, say so.
- Do not edit files; propose fixes.

Output: the reviewer output format - summary verdict, numbered findings by severity, checked and
fine, not checked.
