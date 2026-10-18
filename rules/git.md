# Rule: git

Detail for `AGENTS.md` section 10. Read it before any git operation beyond `git status`.

- **Check before editing:** current branch and `git status`. If the branch is not the one agreed
  for the task, stop and ask.
- **Before implementing, check whether the change already exists** in another branch or an open
  pull request (`git branch -a`, the forge's pull request list). If it does, say so before writing
  code, and verify the existing change instead of rewriting it.
- **When the repository has a remote, create a new branch from the freshly fetched remote default
  branch** (`git fetch origin && git switch -c <branch> origin/<default>`), never from a possibly
  stale local copy.
- **Leave the repository on the branch you found it on.** Record it before switching, switch back
  when done - unless a merge is unresolved or the tree is dirty; then report and leave it.
- **Save an in-flight edit as a patch** (`git diff -- <file> > /tmp/x.patch`) before any stash or
  switch.
- **After a merge, revert or rebase, check full `git status`**: no operation in progress, no
  unmerged paths, no lock file. Never delete a lock held by a running process.
- **Never without an explicit request:** commit, push, force-push, `reset --hard`, rewrite history,
  delete a branch, discard someone's local changes. Never auto-resolve a merge conflict.
- **One topic per commit.** Commit message:
  - subject: one line, imperative, about 70 characters, says what changed
    (`Rotate backup logs after 14 days`);
  - body only when it adds what git cannot show - why, what was verified, what was left alone;
    two or three sentences, wrapped at about 72 characters;
  - no headings, no file lists, no restating the diff, no emoji, no tool or model mention.
