# Copilot instructions

Full rules: `AGENTS.md` at the repository root. Project facts: `PROJECT-CONTEXT.md`. This file is a
short extract; when in doubt, read `AGENTS.md`. Detailed procedures are in `rules/`: read the
matching file before verification or diagnosis, editing or scripts, git work, and the closing
knowledge check.

## Before working

- Read `PROJECT-CONTEXT.md` and the documents in `knowledge/` that cover the request. Assume
  nothing that is not in them or in the repository; ask when a needed fact is missing.
- Check the branch and `git status` of the repository you will touch. Do not switch branches or
  discard local changes to get started. Before implementing, check whether the change already
  exists in another branch or open pull request.
- When there are several similar environments, establish which one the task targets; never reuse
  a value from another.
- Question or small edit: just do it. Non-trivial task: fill the task card (goal, scope, mode, done
  when, permissions - default no, open fields), plan, wait for approval, then implement.

## Anti-hallucination

- Do not guess. Ask, or say "I do not know".
- Mark assumptions as `Assumption:`. Mark knowledge from outside `PROJECT-CONTEXT.md` and the
  repository as general and unverified.
- Do not invent APIs, flags, paths, versions or config keys. Check the code or the tool's
  documentation; otherwise use `<placeholder>` and list it.
- Cite file and line for every claim about the code.
- Run tests or the linter after a change. No "fixed" without the output that shows it. A run
  without evidence is inconclusive, not a pass.
- After a change, reload what reads it (restart the service, re-source the environment) before
  testing; change the source, not the deployed copy.
- Report the diagnosis and the fix separately; an untested fix is unconfirmed.

## Changes

- Smallest change, one intent, no unrequested refactoring or features.
- Preserve encoding and line endings; check `git diff --stat` shows only the intended lines.
  Files that are not UTF-8 are edited by a script that keeps their encoding.
- Do not copy features or settings from a similar project or host by analogy.
- Mark temporary workarounds with a one-line comment naming the reason.
- Temporary files go to the system temp area, never into the repository.
- A behaviour change updates its documentation in the same commit.
- Long or quoting-heavy commands go into a script file run with a timeout.

## Never without asking

Commit, push, delete, change a database or a running service, kill or cancel a process, write to
an external system (show a preview first), install packages, weaken a safety check. Never print or
commit secrets.

## Answer format

Plan -> Changes -> Verification (what it proves and what it does not) -> Risks and open questions.
Short, plain, impersonal; no filler, no emoji. Answer in the user's language; write repository
content in the language set in `PROJECT-CONTEXT.md`.

## Knowledge

Durable, confirmed knowledge goes into `knowledge/`, not into private tool memory. At the end of a
task propose at most five numbered knowledge updates, each with its target file.
