#!/usr/bin/env python3
"""Next release tag and bullet-point notes for what Apps Deploy Prod just deployed (decision 0009).

  utils/release-notes.py --target <sha> --run-url <url> --out notes.md   # prints the tag, or nothing
  utils/release-notes.py --target origin/homelab-v2                      # local preview to stdout
  utils/release-notes.py --self-test

Reads the merge commits between the newest vX.Y.Z tag and the target. Each "Merge pull request #N"
carries the PR title as its body; a title follows `type(scope): subject`. A merge from
.../homelab-v2 is the release PR and is named in the header, not listed. The bump: `!` after the
type or BREAKING CHANGE -> major, any feat -> minor, else patch. Prints nothing when the target
already has a vX.Y.Z tag, so a redeploy of the same commit makes no second release.
Exit code: 0 done, 1 self-test failed, 2 git error.
"""
import argparse
import datetime
import os
import re
import subprocess
import sys

TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
MERGE = re.compile(r"^Merge pull request #(\d+) from (\S+)")
TITLE = re.compile(r"^(\w+)(?:\(([^)]*)\))?(!)?:\s*(.+)$")
GROUPS = [("feat", "Features"), ("fix", "Fixes"), ("docs", "Docs"), (None, "Other")]
RELEASE_BRANCH = "/homelab-v2"


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def parse_tag(name):
    m = TAG.match(name)
    return tuple(int(x) for x in m.groups()) if m else None


def classify(merges):
    """[(number, branch, title, body)] -> (release PR numbers, [(type, bullet, breaking)])."""
    releases, items = [], []
    for number, branch, title, body in merges:
        if branch.endswith(RELEASE_BRANCH):
            releases.append(number)
            continue
        m = TITLE.match(title)
        if m:
            kind, scope, bang, subject = m.groups()
            text = f"{scope}: {subject}" if scope else subject
        else:
            kind, bang, text = None, None, title
        items.append((kind, f"{text} (#{number})", bool(bang) or "BREAKING CHANGE" in body))
    return releases, items


def bump(prev, items):
    major, minor, patch = prev
    if any(b for _, _, b in items):
        return (major + 1, 0, 0)
    if any(k == "feat" for k, _, _ in items):
        return (major, minor + 1, 0)
    return (major, minor, patch + 1)


def render(prev_tag, new_tag, releases, items, run_url, today, repo):
    if run_url:
        head = f"Deployed to prod by Apps Deploy Prod ({run_url}) on {today}"
        head += f", from release PR #{releases[0]}." if releases else "."
    else:
        head = f"Preview on {today}, not deployed."
    lines = [head, ""]
    known = {k for k, _ in GROUPS if k}
    for kind, heading in GROUPS:
        bullets = [t for k, t, _ in items if (k == kind if kind else k not in known)]
        if bullets:
            lines += [f"### {heading}", *(f"- {b}" for b in bullets), ""]
    if repo:
        lines.append(f"**Full Changelog**: https://github.com/{repo}/compare/{prev_tag}...{new_tag}")
    return "\n".join(lines).rstrip() + "\n"


def merges_between(prev_tag, target):
    log = git("log", "--merges", "--format=%s%x1f%b%x1e", f"{prev_tag}..{target}" if prev_tag else target)
    out = []
    for record in filter(None, (r.strip() for r in log.split("\x1e"))):
        subject, _, body = record.partition("\x1f")
        m = MERGE.match(subject)
        if m:
            title = next((line.strip() for line in body.splitlines() if line.strip()), subject)
            out.append((m.group(1), m.group(2), title, body))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--target", default="HEAD")
    ap.add_argument("--run-url", default="")
    ap.add_argument("--out", help="write the notes here and print only the tag")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()

    try:
        if any(parse_tag(t) for t in git("tag", "--points-at", args.target).split()):
            return 0
        # The newest tag sits on a main merge commit that homelab-v2 never contains; prev..target
        # still lists only what came after it.
        tags = [(parse_tag(t), t) for t in git("tag", "--list", "v*").split()]
        tags = sorted(t for t in tags if t[0])
        prev, prev_tag = tags[-1] if tags else ((0, 0, 0), "")
        merges = merges_between(prev_tag, args.target)
    except subprocess.CalledProcessError as e:
        print(f"release-notes: git {e.cmd[1]} failed: {e.stderr.strip()[:200]}", file=sys.stderr)
        return 2
    releases, items = classify(merges)
    new_tag = "v%d.%d.%d" % bump(prev, items)
    today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    notes = render(prev_tag, new_tag, releases, items, args.run_url, today, os.environ.get("GITHUB_REPOSITORY", ""))
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(notes)
        print(new_tag)
    else:
        print(new_tag)
        print(notes, end="")
    return 0


def self_test():
    merges = [
        ("160", "o/homelab-v2", "release: homelab-v2 to main", ""),
        ("158", "o/fix/vsum-pin", "fix(f4): pin vsum to master", ""),
        ("156", "o/feat/vsum", "feat(f4): add vsum", ""),
        ("152", "o/docs/x", "docs: audit decisions", ""),
        ("149", "o/odd", "Increase timeout for deploy-prod job", ""),
    ]
    releases, items = classify(merges)
    assert releases == ["160"], releases
    assert items[0] == ("fix", "f4: pin vsum to master (#158)", False), items[0]
    assert items[2] == ("docs", "audit decisions (#152)", False) and items[3][0] is None, items
    assert bump((2, 1, 0), items) == (2, 2, 0)
    assert bump((2, 1, 3), [i for i in items if i[0] != "feat"]) == (2, 1, 4)
    _, breaking = classify([("1", "o/a", "feat(x)!: drop y", ""), ("2", "o/b", "fix: z", "BREAKING CHANGE: w")])
    assert [b for _, _, b in breaking] == [True, True] and bump((2, 1, 0), breaking) == (3, 0, 0)
    assert bump((2, 1, 0), []) == (2, 1, 1)

    text = render("v2.1.0", "v2.2.0", releases, items, "https://run/1", "2026-10-24", "o/r")
    assert text.startswith("Deployed to prod by Apps Deploy Prod (https://run/1) on 2026-10-24, from release PR #160.\n")
    assert "### Features\n- f4: add vsum (#156)\n" in text, text
    assert "### Fixes\n- f4: pin vsum to master (#158)\n" in text, text
    assert "### Other\n- Increase timeout for deploy-prod job (#149)\n" in text, text
    assert text.index("### Features") < text.index("### Fixes") < text.index("### Docs") < text.index("### Other")
    assert text.rstrip().endswith("compare/v2.1.0...v2.2.0"), text
    assert "###" not in render("v1", "v2", [], [], "", "d", "")
    assert parse_tag("v2.10.0") == (2, 10, 0) and parse_tag("legacy-pre-v2") is None
    print("release-notes self-test: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
