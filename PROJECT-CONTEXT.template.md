# PROJECT-CONTEXT.md

Copy this file to `PROJECT-CONTEXT.md` and fill it in. Leave a field empty rather than guessing:
the agent asks about empty fields it needs and assumes nothing that is not written here or in the
repository.

Last reviewed: YYYY-MM-DD

## 1. Goal

- What this project is for: <one or two sentences>
- Who uses it: <people, systems>
- What is out of scope: <items>

## 2. Stack

| Area | Choice and version |
| --- | --- |
| Languages | |
| Runtime / OS | |
| Frameworks / libraries | |
| Package manager | |
| Infrastructure (hosts, containers, services) | |
| CI | |

## 3. Constraints

- Hard limits: <hardware, network, budget, availability windows>
- Security: <where secrets live and how they are read; what must never leave the machine>
- Compatibility: <versions that must keep working>
- Things the agent must never touch: <paths, hosts, services>

## 4. Commands

| Purpose | Command | Notes |
| --- | --- | --- |
| Install dependencies | | |
| Build | | |
| Test (all) | | |
| Test (single) | | |
| Lint / format | | |
| Run locally | | |
| Deploy | | Never run by the agent without an explicit request |

## 5. Local conventions

- Repository layout: <where code, scripts, config, docs live>
- Naming: <files, functions, branches>
- Code style: <formatter, line length, comment language>
- Scripting language for tooling: <e.g. Python; shell only as thin wrappers>
- Toolchain mangles non-ASCII characters: <yes / no> (yes -> repository content in plain ASCII)
- Release notes / change log file: <path, or none>
- README reference examples: <kind of README -> path of the example to copy>
- Commits: <message format, issue references, signing>
- Branching and review: <default branch, how changes land>
- Language of answers and of repository content: <e.g. answers in the user's language, files in English>
- Deviations from `AGENTS.md`: <only if deliberate, with the reason>

## 6. Environments

| Name | Host / location | Purpose | Agent may change it? |
| --- | --- | --- | --- |
| | | | no |

## 7. Glossary

| Term | Meaning here |
| --- | --- |
| | |

## 8. Open questions

- <anything not decided yet; the agent treats these as unknown>
