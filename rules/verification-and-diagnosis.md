# Rule: verification and diagnosis

Detail for `AGENTS.md` sections 6 and 7. Read it before running tests, judging a result or
diagnosing a failure.

## Verification

- **Evidence must match the claim.** A syntax check proves syntax; a unit test proves the unit; only
  a real run proves the behaviour. Always say what the verification does not prove.
- Run the project's test and lint commands from `PROJECT-CONTEXT.md` after every change. If none
  exist, run the narrowest meaningful check (syntax check, dry run, `--help`, a single invocation
  against test data) and say that it is weaker.
- **Comparisons need equal conditions.** When two runs share a resource (a database, a directory,
  a port), run them one after another, in the same order. Two runs in parallel are not a comparison.
- **After a change, reload what reads it** before testing again: restart a service that reads its
  config at start, re-source an environment file in an open shell, recreate a container. Change the
  source, not the deployed copy - the next deploy overwrites a hand-patched copy.
- **Read the whole log**, not only the tail - the decisive line is often far above the end. Use a
  binary-safe search (`grep -a`) on logs that may contain non-text bytes; plain `grep` then only
  reports "binary file matches". Bundle a large collection of logs into one archive before
  attaching it anywhere.
- **Read a CI status together with how the run was triggered.** A green result after a manual
  rerun or with skipped checks does not prove what a full run proves.

## Attributing a failure to a change

The order that works:

1. **Measure the change surface before reading any log.** Group `git diff --name-only <base>..<head>`
   by directory. "Only one config file changed" turns a vague failure into a single variable.
2. **Look for an existing control run** - an earlier green run with the same inputs. If a green and
   a red run differ in exactly one parameter, the comparison is already done.
3. **Diff a normalized trace, not raw logs.** Strip timestamps, PIDs, addresses and other noise,
   keep the meaningful flow (entry points, commands, values), write one file per run and `diff`
   them. The first divergence is the lead.
4. **Treat a quantity as evidence.** Count events and compare them with what should have happened.
   A backup that copied 40000 files from a directory holding 400 is not slow, it is following a
   symlink loop.
5. **The error message is often the consequence**, not the cause. Follow it back.
6. **Close the loop with a positive control.** Baseline passes, change fails, change without the
   suspected cause passes: that is proof. Two of the three is a correlation - say which you have.

Before testing, check `knowledge/` for a known symptom. A matching entry may mean the environment
needs preparing first, which is not part of the test and must be reported as such.
