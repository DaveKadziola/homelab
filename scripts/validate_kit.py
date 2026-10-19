#!/usr/bin/env python3
"""Check the agent kit files for structural problems.

Checks:
- every role file in agents/ (except README.md) has the five sections, in order;
- every Cursor rule in .cursor/rules/ has frontmatter with description, globs and alwaysApply,
  and no value that strict YAML would reject (for example an unquoted value starting with '*');
- relative Markdown links in kit files point to existing files;
- kit paths written in backticks (rules/..., agents/..., knowledge/..., prompts/..., scripts/...)
  point to existing files;
- no absolute machine-specific paths (drive letters, user home directories);
- AGENTS.md stays within the line limit (it is loaded in every session);
- with --ascii: every kit file is plain ASCII.

Exit code 0 when clean, 1 when a problem was found.
"""
import argparse
import re
import sys
from pathlib import Path

ROLE_SECTIONS = ["## Goal", "## Input", "## Steps", "## Output format", "## Does NOT"]
RULE_KEYS = ["description", "globs", "alwaysApply"]
YAML_BAD_START = "*&!%@`|>"
MAX_AGENTS_LINES = 260
KIT_PATHS = [
    "AGENTS.md",
    "CLAUDE.md",
    "README.md",
    "PROJECT-CONTEXT.template.md",
    ".github/copilot-instructions.md",
    ".cursor/rules",
    "agents",
    "knowledge/README.md",
    "knowledge/templates",
    "prompts",
    "rules",
    "scripts",
]
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
KIT_REF_RE = re.compile(r"`((?:rules|agents|knowledge|prompts|scripts)/[A-Za-z0-9_./-]+\.(?:md|mdc|py))`")
MACHINE_PATH_RES = [
    re.compile(r"\b[A-Za-z]:\\[^\s`]"),
    re.compile(r"(?<![\w<])/(?:home|Users)/[A-Za-z0-9_.-]+"),
]


def kit_files(root):
    for entry in KIT_PATHS:
        path = root / entry
        if path.is_file():
            yield path
        elif path.is_dir():
            yield from sorted(p for p in path.rglob("*") if p.is_file())


def check_roles(root, problems):
    agents_dir = root / "agents"
    if not agents_dir.is_dir():
        problems.append("agents/: directory missing")
        return
    for path in sorted(agents_dir.glob("*.md")):
        if path.name == "README.md":
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        positions = []
        for section in ROLE_SECTIONS:
            if section in lines:
                positions.append(lines.index(section))
            else:
                problems.append(f"{path.relative_to(root)}: missing section '{section}'")
        if len(positions) == len(ROLE_SECTIONS) and positions != sorted(positions):
            problems.append(f"{path.relative_to(root)}: sections out of order")


def check_cursor_rules(root, problems):
    rules_dir = root / ".cursor" / "rules"
    if not rules_dir.is_dir():
        return
    for path in sorted(rules_dir.glob("*.mdc")):
        rel = path.relative_to(root)
        text = path.read_text(encoding="utf-8")
        match = re.match(r"---\r?\n(.*?)\r?\n---\r?\n", text, re.S)
        if not match:
            problems.append(f"{rel}: no frontmatter")
            continue
        keys = set()
        for line in match.group(1).splitlines():
            if ":" not in line or line.startswith((" ", "\t", "-")):
                continue
            key, value = line.split(":", 1)
            keys.add(key.strip())
            value = value.strip()
            if value and value[0] in YAML_BAD_START:
                problems.append(
                    f"{rel}: value of '{key.strip()}' starts with '{value[0]}' - "
                    "invalid unquoted YAML, quote it or use a list"
                )
        for key in RULE_KEYS:
            if key not in keys:
                problems.append(f"{rel}: frontmatter lacks '{key}'")


def check_agents_length(root, problems):
    path = root / "AGENTS.md"
    if path.is_file():
        count = len(path.read_text(encoding="utf-8").splitlines())
        if count > MAX_AGENTS_LINES:
            problems.append(
                f"AGENTS.md: {count} lines, limit {MAX_AGENTS_LINES} - move procedures to rules/"
            )


def check_file(root, path, ascii_only, problems):
    rel = path.relative_to(root)
    raw = path.read_bytes()
    if ascii_only:
        try:
            raw.decode("ascii")
        except UnicodeDecodeError as exc:
            problems.append(f"{rel}: non-ASCII byte at offset {exc.start}")
    text = raw.decode("utf-8", errors="replace")
    for number, line in enumerate(text.splitlines(), 1):
        for pattern in MACHINE_PATH_RES:
            if pattern.search(line):
                problems.append(f"{rel}:{number}: absolute machine path")
        if path.suffix not in (".md", ".mdc"):
            continue
        for target in LINK_RE.findall(line):
            if re.match(r"[a-z]+:", target) or target.startswith("#"):
                continue
            target_path = (path.parent / target.split("#", 1)[0]).resolve()
            if not target_path.exists():
                problems.append(f"{rel}:{number}: dead link '{target}'")
        for target in KIT_REF_RE.findall(line):
            if not (root / target).exists():
                problems.append(f"{rel}:{number}: referenced kit file does not exist '{target}'")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=Path(__file__).resolve().parent.parent, type=Path,
                        help="kit or repository root (default: parent of scripts/)")
    parser.add_argument("--ascii", action="store_true", help="require plain ASCII in kit files")
    args = parser.parse_args()
    root = args.root.resolve()

    problems = []
    check_roles(root, problems)
    check_cursor_rules(root, problems)
    check_agents_length(root, problems)
    for path in kit_files(root):
        check_file(root, path, args.ascii, problems)

    for problem in problems:
        print(problem)
    print(f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
