# AGENTS.md - how an AI agent works in this repository

Single source of truth for every AI coding agent used here (Claude Code, Cursor, VS Code Copilot
or any other). Tool-specific files only point back to it; if they disagree, this file wins.

It describes HOW to work. WHAT the project is lives in `PROJECT-CONTEXT.md` and in the repository.
Long procedures live in `rules/` and are read on demand (section 14).

---

## 1. Ground truth and precedence

1. **Read `PROJECT-CONTEXT.md` before any work.** It holds the goal, stack, constraints, commands,
   local conventions and glossary. If it is missing or a field you need is empty, say so and ask;
   do not fill the gap from general knowledge.
2. **Assume nothing that is not in `PROJECT-CONTEXT.md` or in the repository.** Outside knowledge
   is allowed only when marked as general and unverified (section 4).
3. Order of trust: the user's instruction in this conversation -> the repository (code, config,
   tests) -> `knowledge/` -> `PROJECT-CONTEXT.md` -> general knowledge (marked). When code and a
   document disagree, the code describes what happens; report the document as stale.
4. **Similar environments are never mixed.** With several similar environments (a test host and a
   production host), establish which one the task targets and never reuse a value (port, path,
   credential name, host) from another. Ask when unclear.

## 2. Session start (always, in this order)

1. Read `PROJECT-CONTEXT.md` and this file.
2. Read the documents in `knowledge/` that cover the request. A document is only in your context
   if you open it.
3. Check the repository you will touch: branch, uncommitted changes and, before implementing,
   whether the change already exists elsewhere (section 10). Never switch the user's branch or
   discard their work to get started.
4. Decide whether the request is a question, a small edit or a non-trivial task (section 3).

## 3. Work process

### 3.1 Size the request

- **Question or single small edit:** answer or edit directly. No ceremony.
- **Non-trivial task** (several files, anything that changes state outside the working copy,
  anything you cannot undo with one revert): run the full flow below.

### 3.2 Full flow

1. **Read first, ask second.** Collect what the repository, logs and documents can tell you.
2. **Fill the task card** (3.3). Ask for the fields you could not read, all in one batch.
3. **Plan.** Show the card, then a short plan: steps, files touched, how it will be verified, what
   could go wrong. Wait for approval. Analysis-only requests need no approval.
4. **Implement in small steps**, one intent per change.
5. **Verify** with evidence of the right scope (section 6).
6. **Report** in the fixed format (section 5).
7. **Close** with the knowledge check (section 12).

### 3.3 Task card

| Field | Content |
| --- | --- |
| Goal | One sentence: what is different when the task is done |
| Scope | Repository, branch, files or services involved |
| Mode | analysis / implement / test - several are allowed |
| Done when | The observable check that proves it (test, command output, diff) |
| Permissions | Commit, push, external writes, changes on a host or service - default for each is **no** |
| Open fields | Anything not answered; say what each one blocks |

A field nobody answered stays open. "Probably" is not an answer. Permissions are asked once, up
front; anything outside the card is asked again when it comes up.

### 3.4 Asking for missing information

- Name the unknown, check where it should be (code, config, `knowledge/`), and only then ask.
- Batch the questions: at most about five, each answerable in a few words, with suggested options.
  A value you found yourself becomes the suggested option - it does not remove the question.
- Never ask the user to type a structured line such as `key=value; key2=value2`.
- Never ask about waiting. Ask only about decisions.
- Use `<placeholder>` for a value you do not have, and list every placeholder at the end.

## 4. Anti-hallucination rules

These are not optional.

1. **Do not guess.** When information is missing, ask or write "I do not know".
2. **Separate facts from assumptions.** A fact comes from the repository, a command output or the
   user. Everything else is an assumption and is labelled `Assumption:`.
3. **Do not invent APIs, flags, options, paths, file names, hostnames, versions, package names or
   configuration keys.** Check them in the code, the installed tool (`--help`, man page) or its
   documentation. If you cannot check, use `<placeholder>` and say so.
4. **Cite the source.** For every claim about the code, give file and line
   (`scripts/backup.sh:42`). For a claim from a command, name the command.
5. **No success without a result.** After a change, run the tests / linter / the relevant command.
   Never write "fixed", "works" or "passes" without the output that shows it.
6. **A run without evidence is inconclusive, not a pass.** Before reporting pass or fail, prove the
   run was valid: right target, right input, your own output, and no infrastructure failure that
   ended it early. A missing error message can mean the code was never reached.
7. **One investigation, two facts.** The diagnosis is proved by the evidence you collected; the fix
   is proved by nothing until a run confirms it. Report them separately.
8. **A claim about a neighbouring file is still a claim.** "The other script does the same" means
   you opened it, not that you expect it.
9. **Small changes, one intent per change, summary at the end.**
10. **Fixed answer format** for task work (section 5).
11. **Knowledge from outside `PROJECT-CONTEXT.md` and the repository is marked** as general and
    unverified, e.g. `General knowledge, not verified here: ...`.

## 5. Answer format

For any task that changed or analysed something:

```
Plan
- <what was intended, 1-5 lines>

Changes
- <file or system> - <what changed and why>

Verification
- <command / test / diff> -> <result>
- Not proved by this: <scope limits>

Risks and open questions
- <risk, assumption, placeholder or decision still needed>
```

Style of every answer, document, commit message and comment:

- Short, plain, impersonal. State the finding, the evidence and what follows from it.
- No restating the question, no summary of what was just said, no sign-off, no filler words, no
  emoji, no mention of the tool or model that wrote it.
- A sentence beats a bullet, a bullet beats a table. Use a table only when there are real columns.
- Answer in the language the user writes in. Write repository content (code, comments, documents,
  commit messages) in the language set in `PROJECT-CONTEXT.md`.
- If `PROJECT-CONTEXT.md` says the toolchain mangles non-ASCII characters, write repository content
  in plain ASCII: `->`, `-`, `...`, straight quotes, ASCII trees.

## 6. Verification

Details: `rules/verification-and-diagnosis.md`.

- **Evidence must match the claim.** A syntax check proves syntax, a unit test the unit, only a real
  run the behaviour. Always say what the verification does not prove.
- Run the test and lint commands from `PROJECT-CONTEXT.md` after every change. With none, run the
  narrowest meaningful check and say that it is weaker.
- Runs that share a resource go one after another, in the same order - never in parallel.
- After a change, reload what reads it (restart, re-source) and change the source, not the
  deployed copy.
- Read the whole log, not only the tail. Read a CI status together with how the run was triggered.

## 7. Attributing a failure to a change

Details: `rules/verification-and-diagnosis.md`. Order: measure the change surface, find a control
run, diff normalized traces, count events, remember that the error message is often the
consequence, close with a positive control. Say whether you have proof or only correlation. Check
`knowledge/` for a known symptom before testing.

## 8. Editing discipline

Details: `rules/editing-and-scripts.md`.

- Smallest change that does the job. No tidying, features or abstractions nobody asked for.
- Start from the closest working example; follow the conventions of the file you are in.
- Preserve encoding and line endings; confirm with `git diff --stat` that only intended lines
  changed. Files that are not UTF-8 are edited by a script that keeps their encoding.
- Do not copy features or settings from a similar project or host by analogy.
- Edit in place. Scratch files go to the system temp area, never into the repository.
- A behaviour change updates its documentation (and release notes, if kept) in the same commit.

## 9. Code, scripts and comments

Details: `rules/editing-and-scripts.md`.

- Follow the conventions and tooling language in `PROJECT-CONTEXT.md`. Shell wrappers stay thin.
- Comments explain why. Mark a temporary workaround with a one-line `# TEMP: <reason, when it can go>`.
- Scripts fail fast, return non-zero on failure and are idempotent. Destructive or risky operations
  get a dry-run mode.
- Never print, log or commit a secret. Least privilege for every credential.
- Long or quoting-heavy commands go into a script file run with a timeout; copy it to a remote
  host instead of nesting quotes in `ssh`.
- A long job is not a reason to hand control back: poll a progress signal and continue. A slow
  command is not necessarily hung; check progress before killing it.

## 10. Git

Details: `rules/git.md`.

- Before editing check the branch and `git status`; if the branch is not the agreed one, stop and
  ask. Check whether the change already exists in another branch or open pull request.
- With a remote, branch from the freshly fetched default branch. Leave the repository on the
  branch you found it on.
- **Never without an explicit request:** commit, push, force-push, `reset --hard`, rewrite history,
  delete a branch, discard someone's local changes, auto-resolve a merge conflict.
- One topic per commit. Subject: imperative, about 70 characters, says what changed. Body only for
  why, what was verified, what was left alone. No headings, file lists, emoji or tool mentions.

## 11. Boundaries - never without asking

| Action | Rule |
| --- | --- |
| Push, force-push, history rewrite, branch deletion | Ask. Force-push and history rewrite only on explicit request. |
| Deleting files, directories, environments, data | Ask, every time. Prove it was created by this task. |
| Writing to a database, changing a running service, editing live config on a host | Ask each time, even after a general yes. Save the old value, make the smallest change, verify it took effect, report the command that restores it. |
| Stopping, killing or cancelling a process or job | Ask. On shared resources, prove it is yours (owner, parameters, start time) before touching it. |
| Writing to an external system (issue tracker, chat, wiki, email, remote API) | Show a preview of exactly what will be sent; send only after a yes on that preview. A general yes is not a yes to the text. |
| Installing packages or changing system configuration | Ask. Name the package, version and source. |
| Publishing or deploying when each run has a lasting cost (a restart users notice, a new published version, notifications) | Ask. Batch the changes and publish once per review cycle. |
| Weakening a safety check (disabling tests, skipping hooks, lowering a quality gate) | Never as a shortcut. Propose it and wait. |
| Handling secrets | Never print, copy or commit them. Never ask for them in chat. |

At the end of a task, list every change that outlives the session (files on a host, running
processes, created resources) with the command that reverses it.

## 12. Knowledge base (`knowledge/`)

Details: `rules/knowledge-closing-check.md`; document types and citation rules:
`knowledge/README.md`.

- **Durable knowledge goes into `knowledge/`, not into a tool's private memory.** Tool memory is
  per tool, per user and per machine; the agent without it falls back to guessing. Private memory
  is for machine-local state only.
- **Record only what was confirmed** - by the user or by a run. Smallest edit, most specific
  document, one topic per commit.
- **Closing check:** at the end of a task, name what the knowledge base did not know - verified
  facts (propose the exact sentence and file), unverified ones (one line, do not write), gaps
  (name the document). At most five numbered items; ask once; skip when nothing durable came up.

## 13. Roles and delegation

Role definitions live in `agents/` (see `agents/README.md`). Pick the role by what the request is
about. Answer directly when the request is a question or a small edit - a handover that costs more
than the work helps nobody.

- Delegate in parallel only when the pieces are independent and touch different files.
- Go sequentially when they would write the same file, or one needs the other's output.
- A delegated role receives the filled task card and starts at its plan; it does not repeat the
  intake.
- Delegating does not delegate responsibility: check the specialist's evidence and limits.
- Keep one model for a whole task. Switching models midway loses context and changes behaviour.

## 14. Rules read on demand

Not every tool loads `rules/` automatically. Reading the matching file is part of the task:

| Before | Read |
| --- | --- |
| Running tests, judging a result or diagnosing a failure | `rules/verification-and-diagnosis.md` |
| Editing files, writing scripts, running long or remote commands | `rules/editing-and-scripts.md` |
| Any git operation beyond `git status` | `rules/git.md` |
| Closing a task | `rules/knowledge-closing-check.md` |
