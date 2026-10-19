# Rule: editing, scripts and commands

Detail for `AGENTS.md` sections 8 and 9. Read it before editing files, writing scripts or running
long or remote commands.

## Editing discipline

- **Smallest change that does the job.** Do not reformat, reorder, rename or "tidy" surrounding
  code. No features, abstractions, docstrings or error handling nobody asked for.
- **Start from the closest working example** in the repository and adapt it, instead of designing
  from scratch. Follow the existing conventions of the file you are in.
- **Preserve encoding and line endings** of existing files. After editing, confirm with
  `git diff --stat` that only the intended lines changed; a whole-file diff for a one-line change
  means the encoding or line endings were rewritten.
- **Files that are not UTF-8** are edited with a small script that reads and writes the same
  encoding and newline mode, not with an editor tool that saves as UTF-8. Check the diff stat
  afterwards.
- **Do not copy by analogy.** A feature, option or parameter set that exists in a similar project or
  on a similar host is ported only on a confirmed requirement. Differences between similar setups
  may be deliberate; keep them unless told otherwise.
- **Edit files in place.** Do not delete and recreate a file you only meant to change.
- **Temporary scripts, dumps and scratch files go to the system temp area** (`/tmp`, `%TEMP%`),
  never into the repository. Remove them after verification. Keep rollback backups until the user
  says they are no longer needed.
- **Change behaviour, change its documentation in the same commit** - the README first, then any
  document in `knowledge/` that describes it. Search the docs for the old behaviour's key words.
- **If the project keeps release notes or a change log**, a user-visible change adds its entry in
  the same commit, about as long as the entries around it.

## Code, scripts and comments

- Follow the language, formatter and naming conventions in `PROJECT-CONTEXT.md`; where it is
  silent, follow the surrounding code.
- Write tooling in the scripting language set in `PROJECT-CONTEXT.md`. Shell wrappers stay thin:
  environment, arguments, the call into the real tool. Put real logic in a testable script or
  module. Complex parsing belongs in a real programming language, not in inline shell.
- Comments explain **why**, not what. No comment that restates the code.
- **Mark a temporary workaround** with a one-line comment directly above the changed line, naming
  the reason or issue and when it can go (`# TEMP: skip mount check until the disk is replaced`).
- Scripts fail fast (`set -euo pipefail` in bash or the equivalent) and return a non-zero exit code
  on failure.
- **Scripts are idempotent**: running one twice leaves the same result as running it once.
- **Destructive or risky operations get a dry-run mode** and print what they would do.
- **Never print, log or commit a secret.** Read credentials from the place the project defines;
  report only whether they were found. Least privilege for every credential.
- Hint for larger tools with several transformation steps: one orchestrator that calls stages,
  each stage idempotent and runnable on its own, configured by a file with one flag per feature
  that command-line options can override. Not needed for small scripts.

## Running commands

- **Anything long, complex or quoting-heavy goes into a script file**, run with a timeout - not an
  inline one-liner. One unbalanced quote can leave a shell waiting for input until the tool gives
  up. For remote commands, copy a script to the host and run it rather than nesting quotes in `ssh`.
- **A long job is not a reason to hand control back.** Do not end with "I will let you know when
  it finishes"; poll a real progress signal (a growing log, a status command) and continue.
- **A slow command is not necessarily a hung one.** Before killing it, check a progress signal
  (CPU, I/O, a growing file). Never delete a tool's internal files (locks, indexes, caches) while a
  process may still hold them.
- **A dropped connection that needs no human login is restored by the agent**, and the task
  continues in the same turn. If restoring it needs a password, MFA or a browser, ask once and wait.
- **When exact bytes matter, capture output byte-safely** (a script that writes bytes, or an
  explicit encoding) instead of shell redirection, which may re-encode the output. Know whether the
  shell adds a byte-order mark when writing UTF-8.
