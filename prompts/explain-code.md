# Prompt: explain code

Act as the researcher role (`agents/researcher.md`) and follow `AGENTS.md`. Read-only.

Code: <file, function or directory>
Audience: <me later / someone new to the project / reviewer>
Question: <what should become clear - overall purpose, a specific behaviour, why it is built this way>

Rules:
- Read the code and its callers; do not explain from names alone.
- Cite `file:line` for every statement about behaviour.
- Separate what the code does (fact) from why it might do it (assumption, labelled).
- Mention side effects: files written, services touched, network calls, anything destructive.
- Say what you did not read.

Output:
1. Purpose in two or three sentences.
2. Flow: numbered steps with `file:line`.
3. Inputs, outputs, side effects.
4. Surprises or risks noticed.
5. Assumptions and unread parts.
