# Rule: knowledge closing check

Detail for `AGENTS.md` section 12. Read it at the end of a task. Document types, header fields and
citation rules are in `knowledge/README.md`.

## When

At the end of a task - when the result is reported, or when the user switches to an unrelated
topic - check what the knowledge base did not know.

## What to do

| Kind | What to do |
| --- | --- |
| Verified (user confirmed, or a run proved it) | Propose the exact sentence and the target document; write it when allowed. |
| Unverified (held once, or a guessed cause) | Do not write it. Mention it as one line. |
| Gap (a document was silent, wrong or pointed elsewhere) | Name the document and what it should say. |

## How to ask

Ask in a form that can be answered in three words: at most five numbered items, each already
phrased as the sentence to add, with its target file. Ask once; no answer means no. Skip the whole
check when nothing durable and new came up.

Collect candidates as they appear during the task - reconstructing them at the end loses half of
them.
