# Prompt: plan a change

Follow `AGENTS.md` sections 3 and 11. Do not edit anything yet.

Request: <what should be different when done>
Context: <issue, notes, related files>

Steps:
1. Read `PROJECT-CONTEXT.md`, the relevant `knowledge/` documents and the code involved.
2. Fill the task card:

   | Field | Value |
   | --- | --- |
   | Goal | |
   | Scope | |
   | Mode | analysis / implement / test |
   | Done when | |
   | Permissions | commit: no, push: no, external writes: no, host/service changes: no |
   | Open fields | |

3. Ask for the open fields in one batch, with suggested options.
4. Write the plan:
   - steps, each small and with one intent;
   - files and systems touched;
   - how each step is verified, and what that does not prove;
   - risks, rollback, and anything irreversible;
   - placeholders still needed.
5. Stop and wait for approval.

Output: the task card, then the plan. Mark every assumption.
