# Prompt: take over an in-progress project

Use when an existing project, often started in another tool (for example Cursor), is handed over to
an agent that follows this kit. Goal: adopt the kit, establish the true state of the project, and
stop with a report before any new implementation. Follow `AGENTS.md`; this file adds the order.

Project: <the current working directory>
Master copy of the kit: <kit-master-path>
Where the plan lives: <path, or "find it">
Planned changes to the plan: <notes, or "to be discussed after the audit">

## Ground rules for the whole takeover

- Analysis only until the user approves the revised plan (phase 6). Before that the only writes
  are the kit files (phase 2), `PROJECT-CONTEXT.md` (phase 3) and the audit report (phase 5),
  each after the user said yes.
- No commands on hosts, devices or services: no `ssh`, no API calls, no restarts, no config
  changes. If the audit needs live state, list the read-only command and ask the user to run it
  or to allow it.
- Never commit, push, stash or discard anything without an explicit request.
- Never read out, copy or print a secret. If the repository contains one, report only `file:line`
  and its type.
- Answer in the user's language. Stop at the end of every phase with the `AGENTS.md` section 5
  format and wait.

## Phase 0 - Safety snapshot

1. Report: current branch, `git status`, last 10 commits, remotes, stashes, untracked files. No
   git repository: say so and propose `git init` with a first commit of the current state.
2. Uncommitted changes: do not touch them. Ask whether to commit them first as the state left by
   the previous tool.
3. Propose a working branch from the current HEAD (for example `agent-takeover`); create it only
   after a yes.
4. Ask the user to stop editing the project in the other tool while the takeover runs.

## Phase 1 - Inventory of what the previous tool left

List with path, size, last commit date and a one-line purpose:

- Agent configuration: `.cursor/rules/`, `.cursorrules`, anything else under `.cursor/`,
  `AGENTS.md`, `CLAUDE.md`, `.claude/`, `.github/copilot-instructions.md`, AI settings in `.vscode/`.
- Plans and notes: files named like plan, roadmap, todo, tasks, notes, design, changelog; `docs/`;
  plan folders of the previous tool if present; files with checklists (`- [ ]`); TODO and FIXME
  comments (count per file).
- Code and configuration: top-level layout, languages, infrastructure files (compose, Ansible,
  Terraform, Kubernetes, systemd units), scripts, CI.
- Secret risk: `.env` files, key files, password or token assignments (path and type only).

Classify each piece of agent configuration: (A) generic working rules - replaced by the kit;
(B) project facts - move to `PROJECT-CONTEXT.md` or `knowledge/`; (C) unclear - ask.

## Phase 2 - Adopt the kit

1. Run `python <kit-master-path>/scripts/sync_kit.py <project> --diff` (dry run) and show it.
2. Conflicting files (for example an existing `AGENTS.md`): never `--force` first. Per file,
   propose: move its project facts to phase 3, then overwrite; or keep it. Ask.
3. Old rule files of the previous tool that duplicate or contradict the kit: propose moving them
   to a `-legacy` folder (for example `.cursor/rules-legacy/`) instead of deleting. Ask.
4. After a yes: rerun with `--apply`, then `python scripts/validate_kit.py`. Report both outputs.

## Phase 3 - PROJECT-CONTEXT.md

Copy `PROJECT-CONTEXT.template.md` to `PROJECT-CONTEXT.md`. Fill every field you can prove from
the repository and put the source next to it (`<!-- source: file:line -->`). Leave the rest
empty. Then ask one batch of questions for the empty fields that block work: environments and
hosts, how they are reached (method only, never credentials), what must never be touched, backup
and rollback. Do not invent hosts, addresses, versions or services.

## Phase 4 - Audit of the state

- Split the plan into items, keeping its own numbering. For each item give a status - done,
  implemented but unverified, partial, not started, diverged, unclear - with evidence
  (`file:line`, commit, test or command output). "Done" needs evidence that it works, not only
  that code exists.
- Run the local build, test and lint commands if the project has them; nothing that touches a
  host. Report the commands and results.
- Findings, by severity: secrets in the repository, destructive scripts without dry-run,
  hard-coded addresses or credentials, missing rollback, plan and code disagreeing, unfinished
  work (branches, TODOs), work present in the code but missing from the plan.
- Fix nothing in this phase.

## Phase 5 - Report

Write `docs/audit/YYYY-MM-DD-takeover.md`: summary in at most five lines, the table of plan items
with status and evidence, findings by severity, open questions, and at most three proposed next
steps. Propose knowledge entries only for confirmed facts (`AGENTS.md` section 12).

## Phase 6 - Change the plan, together with the user

1. Ask what the user wants to change. Do not guess the intent.
2. Propose the revised plan as a difference from the old one: kept, changed, dropped and new
   items, each with its reason and its effect on work already done.
3. Record each significant change as a decision from `knowledge/templates/decision.md`.
4. Edit the plan file only after a yes. Continue implementation one item at a time through the
   normal `AGENTS.md` flow (task card, plan, approval, small steps, verification).
