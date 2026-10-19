#!/usr/bin/env python3
"""Copy the portable agent kit from this master copy into a project.

Run it from the master copy:  python scripts/sync_kit.py <project-dir> [--apply]

Default is a dry run: it prints what would happen and writes nothing.

How files are classified (per kit file):
  new         not in the project yet -> copied
  update      project copy is unchanged since the last sync -> overwritten with the new kit file
  unchanged   identical to the kit file (line endings are ignored)
  conflict    project copy differs and was changed locally (or this is the first sync into an
              existing file) -> left alone; shown with --diff; overwritten only with --force
  kept        knowledge/README.md holds the project's own index, so an existing copy is never
              overwritten (merge changes by hand)
  refused     the target path goes through a symlink or outside the project -> never written

Never touched: PROJECT-CONTEXT.md, the project's knowledge documents, anything not in the kit.
The sync state is stored in <project-dir>/.agent-kit.json (file hashes, no secrets); commit it
together with the kit files. Files removed from the kit are only reported, and deleted from the
project with --prune --apply when the project copy is still unchanged.

Exit code: 0 when everything is in sync or was applied, 1 when conflicts or refused files remain,
2 on a usage error.
"""
import argparse
import difflib
import hashlib
import json
import shutil
import sys
from pathlib import Path

KIT_ENTRIES = [
    "AGENTS.md",
    "CLAUDE.md",
    "PROJECT-CONTEXT.template.md",
    "claude-settings.example.json",
    ".github/copilot-instructions.md",
    ".cursor/rules",
    "agents",
    "knowledge/README.md",
    "knowledge/templates",
    "prompts",
    "rules",
    "scripts",
]
KEEP_IF_EXISTS = {"knowledge/README.md"}
MANIFEST = ".agent-kit.json"
SKIP_PARTS = {"__pycache__", ".DS_Store"}
DIFF_LINES = 60


def normalized(data):
    return data.replace(b"\r\n", b"\n")


def digest(data):
    return hashlib.sha256(normalized(data)).hexdigest()


def kit_files(root):
    files = {}
    for entry in KIT_ENTRIES:
        path = root / entry
        candidates = [path] if path.is_file() else sorted(path.rglob("*")) if path.is_dir() else []
        for item in candidates:
            if not item.is_file() or item.is_symlink():
                continue
            if SKIP_PARTS & set(item.relative_to(root).parts) or item.suffix == ".pyc":
                continue
            files[item.relative_to(root).as_posix()] = item
    return files


def load_manifest(target):
    path = target / MANIFEST
    if not path.is_file():
        return {}
    try:
        return dict(json.loads(path.read_text(encoding="utf-8")).get("files", {}))
    except (ValueError, AttributeError) as exc:
        print(f"error: {MANIFEST} is not valid JSON ({exc}); fix or delete it", file=sys.stderr)
        sys.exit(2)


def safe_destination(target, rel):
    """Return the destination path, or None when it would leave the project or follow a symlink."""
    dst = target / rel
    if dst.is_symlink():
        return None
    try:
        dst.parent.resolve().relative_to(target)
    except ValueError:
        return None
    return dst


def show_diff(rel, dst, src):
    old = normalized(dst.read_bytes()).decode("utf-8", "replace").splitlines()
    new = normalized(src.read_bytes()).decode("utf-8", "replace").splitlines()
    lines = list(difflib.unified_diff(old, new, f"project/{rel}", f"kit/{rel}", lineterm=""))
    for line in lines[:DIFF_LINES]:
        print("    " + line)
    if len(lines) > DIFF_LINES:
        print(f"    ... {len(lines) - DIFF_LINES} more diff lines")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("target", type=Path, help="project directory to sync the kit into")
    parser.add_argument("--apply", action="store_true", help="write changes (default: dry run)")
    parser.add_argument("--diff", action="store_true", help="show diffs for update and conflict files")
    parser.add_argument("--force", action="store_true", help="overwrite conflict files with the kit version")
    parser.add_argument("--prune", action="store_true",
                        help="delete files removed from the kit (only unchanged ones, needs --apply)")
    args = parser.parse_args()

    source = Path(__file__).resolve().parent.parent
    if not args.target.is_dir():
        print(f"error: {args.target} is not a directory", file=sys.stderr)
        return 2
    target = args.target.resolve()
    if target == source:
        print("error: the target is the master copy itself", file=sys.stderr)
        return 2
    if args.prune and not args.apply:
        print("error: --prune needs --apply", file=sys.stderr)
        return 2

    kit = kit_files(source)
    recorded = load_manifest(target)
    new_state = {}
    plan = []  # (status, rel, src, dst)

    for rel, src in kit.items():
        dst = safe_destination(target, rel)
        src_hash = digest(src.read_bytes())
        if dst is None:
            plan.append(("refused", rel, src, None))
        elif not dst.exists():
            plan.append(("new", rel, src, dst))
        else:
            dst_hash = digest(dst.read_bytes())
            if dst_hash == src_hash:
                plan.append(("unchanged", rel, src, dst))
            elif rel in KEEP_IF_EXISTS:
                plan.append(("kept", rel, src, dst))
            elif recorded.get(rel) == dst_hash:
                plan.append(("update", rel, src, dst))
            else:
                plan.append(("conflict", rel, src, dst))

    removed = []
    for rel, old_hash in recorded.items():
        if rel in kit:
            continue
        dst = safe_destination(target, rel)
        if dst is not None and dst.exists():
            removed.append((rel, dst, digest(dst.read_bytes()) == old_hash))

    counts = {}
    for status, rel, src, dst in plan:
        counts[status] = counts.get(status, 0) + 1
        if status != "unchanged":
            print(f"{status:<10} {rel}")
            if args.diff and status in ("update", "conflict"):
                show_diff(rel, dst, src)
    for rel, dst, pristine in removed:
        label = "removed" if pristine else "removed*"
        print(f"{label:<10} {rel}")
    if any(not pristine for _, _, pristine in removed):
        print("  (* removed from the kit but changed in the project: left alone)")

    unresolved = counts.get("refused", 0) + (0 if args.force else counts.get("conflict", 0))
    summary = ", ".join(f"{n} {s}" for s, n in sorted(counts.items()))
    print(f"\n{summary}; {len(removed)} removed upstream")

    if not args.apply:
        print("dry run - nothing written. Rerun with --apply to write.")
        return 1 if unresolved else 0

    for status, rel, src, dst in plan:
        src_hash = digest(src.read_bytes())
        if status in ("new", "update") or (status == "conflict" and args.force):
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            new_state[rel] = src_hash
        elif status == "unchanged":
            new_state[rel] = src_hash
        elif status == "conflict" and rel in recorded:
            new_state[rel] = recorded[rel]
    for rel, dst, pristine in removed:
        if args.prune and pristine:
            dst.unlink()
        else:
            new_state[rel] = recorded[rel]

    manifest = {
        "note": "State of the last sync from the master agent kit. Commit it with the kit files.",
        "files": dict(sorted(new_state.items())),
    }
    (target / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"written. Next: python scripts/validate_kit.py --root <project-dir>; commit {MANIFEST} too.")
    return 1 if unresolved else 0


if __name__ == "__main__":
    sys.exit(main())
