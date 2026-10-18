# Prompt: analyse logs

Follow `AGENTS.md` sections 4, 6 and 7. Read-only unless stated otherwise.

Logs: <paths or attached files>
Time window: <from - to, timezone>
Question: <why did X fail / what happened at T / is Y healthy>
Comparison run (optional): <log of a known good run>

Rules:
- Confirm the logs belong to the run in question (host, service, time, process id).
- Read the whole relevant window, not only the tail; the first error is usually the cause, the
  last one is usually the consequence.
- With a comparison run: strip timestamps, ids and addresses, then diff the normalized flows;
  report the first divergence.
- Count repeated events and compare with what should have happened.
- Quote only the lines that matter, with file and line number. Never quote secrets.
- If the logs cannot answer the question, say which log or setting would.

Output:
1. Answer: one to three sentences, with verdict proved / correlated / inconclusive.
2. Timeline: time - event - `file:line`.
3. First divergence or first error, and why it is the lead.
4. Counts that matter.
5. Assumptions and missing data.
