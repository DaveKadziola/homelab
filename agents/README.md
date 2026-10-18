# Agent roles

Every role uses the same five sections, in this order:

1. **Goal** - what the role is for, in one or two sentences.
2. **Input** - what it needs before starting; missing items are asked for, never guessed.
3. **Steps** - the working order.
4. **Output format** - the exact shape of the result.
5. **Does NOT** - the limits that matter most.

All roles follow `AGENTS.md`. A role file only adds what is specific to that role.

| Role | Use when |
| --- | --- |
| [reviewer](reviewer.md) | A change, branch or file needs a review before it lands |
| [test-writer](test-writer.md) | Behaviour needs tests, or a bug needs a reproducing test |
| [refactorer](refactorer.md) | Structure should change without changing behaviour |
| [researcher](researcher.md) | A question needs an answer from the code, docs or tool help - read-only |
| [troubleshooter](troubleshooter.md) | Something fails and the cause is unknown |
| [doc-writer](doc-writer.md) | A README or knowledge document must be written or brought in line with the code |
| [retrospective](retrospective.md) | A multi-step task is finished and the knowledge base should learn from it |

Choosing a role: pick by what the request is about. A question or a one-line edit needs no role.
A delegated role receives the filled task card (`AGENTS.md` section 3.3) and starts at its steps.

Adding a role: copy an existing file, keep the five sections, keep "Does NOT" to the limits that
would surprise someone, add a row to the table above, and run `python scripts/validate_kit.py`.
