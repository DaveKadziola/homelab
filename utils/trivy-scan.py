#!/usr/bin/env python3
"""Scan the images of the running containers with Trivy; with --mail, mail when the findings change.

  sudo utils/trivy-scan.py           # print the HIGH and CRITICAL findings that have a fix
  sudo HOMELAB_ENV=prod HOMELAB_SECRETS_DIR=/opt/homelab/secrets utils/trivy-scan.py --mail
  utils/trivy-scan.py --self-test

A finding is image, vulnerability, package and installed version. Only HIGH and CRITICAL with a
fixed version count: that is what an image update would remove. --mail compares with the list in
/var/lib/homelab/trivy-findings.json, mails through utils/alert-mail.sh only when it differs and
then stores the new list; a failed mail keeps the old one, so the next run tries again. An image
whose scan fails keeps its previous findings and is named in the mail. Not a merge gate (audit S15).
Exit code: 0 done, 1 self-test failed, 2 Trivy or docker missing.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE = Path("/var/lib/homelab/trivy-findings.json")
CACHE = "/var/cache/trivy"
SEVERITIES = ("HIGH", "CRITICAL")
MAX_LINES = 150


def findings(image, report):
    """Set of (image, id, severity, package, installed, fixed) from one Trivy JSON report."""
    out = set()
    for result in report.get("Results") or []:
        for v in result.get("Vulnerabilities") or []:
            if v.get("Severity") in SEVERITIES and v.get("FixedVersion"):
                out.add((image, v["VulnerabilityID"], v["Severity"], v["PkgName"],
                         v.get("InstalledVersion", ""), v["FixedVersion"]))
    return out


def key(f):
    # The fixed version can move with a DB update; that is not a new finding.
    return f[:2] + f[3:5]


def diff(old, new):
    old_keys, new_keys = {key(f) for f in old}, {key(f) for f in new}
    return (sorted(f for f in new if key(f) not in old_keys),
            sorted(f for f in old if key(f) not in new_keys))


def report(env, new, added, gone, failed):
    images = sorted({f[0] for f in new})
    lines = [f"Trivy on {env}: {len(new)} HIGH/CRITICAL findings with a fix in {len(images)} images."]
    if added:
        lines.append(f"New ({len(added)}):")
        lines += [f"  {f[0]}: {f[1]} {f[2]} {f[3]} {f[4]} -> {f[5]}" for f in added[:MAX_LINES]]
        if len(added) > MAX_LINES:
            lines.append(f"  ... {len(added) - MAX_LINES} more")
    if gone:
        lines.append(f"Gone: {len(gone)}")
    if failed:
        lines.append("Not scanned (previous findings kept):")
        lines += [f"  {image}: {why}" for image, why in sorted(failed.items())]
    if images:
        lines.append("Per image:")
        lines += [f"  {i}: {sum(1 for f in new if f[0] == i)}" for i in images]
    return "\n".join(lines) + "\n"


def scan(image):
    try:
        p = subprocess.run(
            ["trivy", "image", "--quiet", "--format", "json", "--scanners", "vuln", "--image-src", "docker",
             "--severity", ",".join(SEVERITIES), "--ignore-unfixed", "--cache-dir", CACHE, image],
            capture_output=True, text=True, timeout=1800)
    except subprocess.TimeoutExpired:
        return None, "trivy timed out after 30 min"
    if p.returncode != 0:
        return None, f"trivy exit {p.returncode}: {(p.stderr.strip().splitlines() or [''])[-1][:200]}"
    try:
        return findings(image, json.loads(p.stdout)), None
    except (json.JSONDecodeError, KeyError) as e:
        return None, f"unreadable trivy output ({type(e).__name__})"


def load_state():
    if not STATE.is_file():
        return set(), {}
    data = json.loads(STATE.read_text())
    return {tuple(f) for f in data["findings"]}, data.get("failed", {})


def save_state(new, failed):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=STATE.parent, delete=False) as t:
        json.dump({"findings": sorted(new), "failed": failed}, t)
    os.replace(t.name, STATE)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--mail", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()

    try:
        ps = subprocess.run(["docker", "ps", "--format", "{{.Image}}"], capture_output=True, text=True, check=True)
        subprocess.run(["trivy", "--version"], capture_output=True, check=True)
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"trivy-scan: {type(e).__name__}: docker or trivy not usable", file=sys.stderr)
        return 2
    old, old_failed = load_state() if args.mail else (set(), {})
    new, failed = set(), {}
    for image in sorted(set(ps.stdout.split())):
        got, why = scan(image)
        if got is None:
            failed[image] = why
            got = {f for f in old if f[0] == image}
        new |= got

    env = os.environ.get("HOMELAB_ENV", "?")
    added, gone = diff(old, new)
    text = report(env, new, added if args.mail else sorted(new), gone, failed)
    print(text, end="")
    if not args.mail:
        return 0
    if not added and not gone and set(failed) == set(old_failed):
        return 0
    subject = f"trivy {env}: {len(added)} new, {len(gone)} gone"
    subprocess.run([str(ROOT / "utils" / "alert-mail.sh"), subject], input=text, text=True, check=True)
    save_state(new, failed)
    return 0


def self_test():
    rep = {"Results": [{"Vulnerabilities": [
        {"VulnerabilityID": "CVE-1", "Severity": "HIGH", "PkgName": "openssl", "InstalledVersion": "3.0.1",
         "FixedVersion": "3.0.2"},
        {"VulnerabilityID": "CVE-2", "Severity": "CRITICAL", "PkgName": "zlib", "InstalledVersion": "1.2",
         "FixedVersion": ""},
        {"VulnerabilityID": "CVE-3", "Severity": "MEDIUM", "PkgName": "curl", "InstalledVersion": "8.0",
         "FixedVersion": "8.1"},
    ]}, {"Target": "no vulns", "Vulnerabilities": None}]}
    a = findings("img:1", rep)
    assert a == {("img:1", "CVE-1", "HIGH", "openssl", "3.0.1", "3.0.2")}, a
    assert findings("img:1", {"Results": None}) == set()

    b = {("img:1", "CVE-1", "HIGH", "openssl", "3.0.1", "3.0.3"),  # only the fixed version moved
         ("img:2", "CVE-9", "CRITICAL", "glibc", "2.39", "2.40")}
    added, gone = diff(a, b)
    assert [f[1] for f in added] == ["CVE-9"] and gone == [], (added, gone)
    added, gone = diff(b, a)
    assert added == [] and [f[1] for f in gone] == ["CVE-9"], (added, gone)

    text = report("dev", b, sorted(b), [], {"local:latest": "trivy exit 1: x"})
    assert "2 HIGH/CRITICAL findings with a fix in 2 images" in text, text
    assert "img:2: CVE-9 CRITICAL glibc 2.39 -> 2.40" in text and "local:latest: trivy exit 1" in text, text
    many = [("i", f"CVE-{n}", "HIGH", "p", "1", "2") for n in range(MAX_LINES + 5)]
    assert "... 5 more" in report("dev", set(many), many, [], {}), "cap"
    print("trivy-scan self-test: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
