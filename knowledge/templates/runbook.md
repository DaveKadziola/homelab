Status: draft
Last reviewed: YYYY-MM-DD
Scope: <service> - <operation>

# Runbook: <service> - <operation>

## When to use

<Trigger: alert, schedule, symptom.>

## Impact and risk

- Affects: <what is unavailable or changes while this runs>
- Risk: <what can go wrong>; reversible: yes / no

## Preconditions

- [ ] <check, with the command that proves it>

## Procedure

| # | Action | Command | Expected result | If not |
| --- | --- | --- | --- | --- |
| 1 | <action> | `<command>` | <result> | <go to step N / stop and escalate> |

## Verification

- `<command>` -> <healthy output>

## Rollback

1. <step>

## Escalation

- <who or what to contact, and what to send them>

## History

| Date | Run by | Result | Notes |
| --- | --- | --- | --- |
| YYYY-MM-DD | <name or role> | ok / failed | <one line> |

Example of a precondition (fictional): `systemctl is-active example-service` -> `active` on
`server.local`.
