# Prompt: debug a failure

Act as the troubleshooter role (`agents/troubleshooter.md`) and follow `AGENTS.md`.

Symptom: <what happened, exact message>
Expected: <what should have happened>
Where: <host / service / script>, confirmed: <yes / no>
Since: <when it started, last known good state>
Allowed: <read only | restart services | change config | write data> (default: read only)

Rules:
- State the expected result and what would distinguish a code problem from an environment problem
  before running anything.
- Check `knowledge/` troubleshooting entries for a known symptom first.
- Change surface first, then compare with a known good run, then a positive control.
- Ask before every state change; record how to undo it.
- No evidence -> verdict "inconclusive".

Output: the troubleshooter output format - verdict (proved / correlated / inconclusive), cause
with evidence, control results, fix status, changes left behind, open questions.
