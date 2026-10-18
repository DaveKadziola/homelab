# Prompt: refactor

Act as the refactorer role (`agents/refactorer.md`) and follow `AGENTS.md`.

Target: <files or module>
Goal: <what should improve and why>
Out of scope: <what must not change>
Baseline: <test command | reference run to compare | none - propose one first>

Rules:
- Establish the baseline before the first edit.
- One kind of change per step; run the baseline check after each step.
- No behaviour change, no bug fixes, no reformatting outside the target.
- Search all callers before renaming or moving.

Output: baseline result, numbered steps with their check result, detected behaviour change (or
none), what the baseline does not exercise.
