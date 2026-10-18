#!/usr/bin/env python3
"""Push local secret values to a GitHub Environment, without printing them.

The laptop cache is the working copy of the secrets: ~/.homelab-secrets/<env>/<NAME>
(written by utils/gen-app-credentials.sh) plus a few single files for Proxmox. GitHub
secrets are write-only, so this tool cannot compare values; it overwrites what you select.

Usage:
  utils/sync-secrets-to-github.py --env dev                 # dry run: names and actions only
  utils/sync-secrets-to-github.py --env dev --apply         # write every secret that has a source
  utils/sync-secrets-to-github.py --env dev --only POSTGRES_PASSWORD,BESZEL_KEY --apply

Values go to `gh secret set NAME --env ENV --repo REPO` on standard input. Never use
`--body -`: gh then stores the literal "-" (that is how every secret became "-" before).
Exit code: 0 ok, 1 a write failed, 2 usage or environment error.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
NAME_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
EXTRA_SOURCES = {
    "dev": {
        "PROXMOX_API_TOKEN_SECRET": HOME / ".homelab-pve-dev-token-secret",
        "PROXMOX_SSH_PASSWORD": HOME / ".homelab-pve-dev-root-pass",
    },
    "prod": {},
}


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def default_repo():
    res = run(["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"])
    return res.stdout.strip() if res.returncode == 0 and res.stdout.strip() else None


def local_sources(env):
    sources = {}
    cache = HOME / ".homelab-secrets" / env
    if cache.is_dir():
        for path in sorted(cache.iterdir()):
            if path.is_file() and NAME_RE.match(path.name):
                sources[path.name] = path
    for name, path in EXTRA_SOURCES.get(env, {}).items():
        if path.is_file():
            sources[name] = path
    return sources


def github_secrets(env, repo):
    res = run(["gh", "secret", "list", "--env", env, "--repo", repo, "--json", "name,updatedAt"])
    if res.returncode != 0:
        print(f"error: cannot list secrets of environment '{env}': {res.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return {item["name"]: item["updatedAt"] for item in json.loads(res.stdout or "[]")}


def read_value(path):
    value = path.read_text(encoding="utf-8")
    # Several files are written with a trailing newline (printf '%s\n'); a secret never ends with one.
    return value[:-1] if value.endswith("\n") else value


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--env", required=True, choices=sorted(EXTRA_SOURCES))
    parser.add_argument("--repo", help="owner/name (default: the current gh repository)")
    parser.add_argument("--only", help="comma-separated secret names to sync")
    parser.add_argument("--apply", action="store_true", help="write to GitHub (default: dry run)")
    args = parser.parse_args()

    repo = args.repo or default_repo()
    if not repo:
        print("error: cannot determine the repository; pass --repo owner/name", file=sys.stderr)
        return 2

    sources = local_sources(args.env)
    remote = github_secrets(args.env, repo)
    selected = sorted(sources)
    if args.only:
        wanted = [n.strip() for n in args.only.split(",") if n.strip()]
        unknown = [n for n in wanted if n not in sources]
        if unknown:
            print(f"error: no local source for: {', '.join(unknown)}", file=sys.stderr)
            return 2
        selected = wanted

    print(f"repo {repo}, environment {args.env}, {'APPLY' if args.apply else 'dry run'}")
    print(f"{'secret':<28} {'action':<10} {'github updated':<22} source")
    for name in selected:
        action = "overwrite" if name in remote else "create"
        updated = remote.get(name, "-")
        print(f"{name:<28} {action:<10} {updated:<22} {sources[name]}")
    untouched = sorted(set(remote) - set(sources))
    if untouched:
        print(f"no local source, left untouched on GitHub: {', '.join(untouched)}")

    if not args.apply:
        print("dry run - nothing written. Rerun with --apply to write.")
        return 0

    failed = []
    for name in selected:
        value = read_value(sources[name])
        if not value:
            failed.append(f"{name} (empty source)")
            continue
        res = run(["gh", "secret", "set", name, "--env", args.env, "--repo", repo], input=value)
        if res.returncode != 0:
            failed.append(f"{name} ({res.stderr.strip()[:120]})")
        del value
    written = len(selected) - len(failed)
    print(f"written: {written}/{len(selected)}")
    for item in failed:
        print(f"FAILED {item}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
