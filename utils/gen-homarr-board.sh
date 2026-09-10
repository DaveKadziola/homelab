#!/usr/bin/env bash
# Generate the Homarr board seed from config/services.yml (F7-B).
#
# The board is never hand-maintained: every tile comes from the service list,
# ordered by `dashboard.group`, skipping `dashboard.hidden` entries. IDs are
# derived from the service name, so regenerating produces a stable diff and
# utils/bootstrap/homarr.sh can apply the seed idempotently.
#
# Usage:
#   ./utils/gen-homarr-board.sh --env dev
#   ./utils/gen-homarr-board.sh --env prod -o /tmp/board.json
#
# Output: compose/core/homarr/board-<env>.json

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES="${ROOT}/config/services.yml"

ENVIRONMENT=""
OUTPUT=""

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="$2"; shift 2 ;;
    -o|--output) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$ENVIRONMENT" ]] || { echo "--env dev|prod is required" >&2; exit 1; }
[[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "prod" ]] || { echo "--env must be dev or prod" >&2; exit 1; }
[[ -f "$SERVICES" ]] || { echo "Missing ${SERVICES}" >&2; exit 1; }

OUTPUT="${OUTPUT:-${ROOT}/compose/core/homarr/board-${ENVIRONMENT}.json}"
mkdir -p "$(dirname "$OUTPUT")"

python3 - "$SERVICES" "$ENVIRONMENT" "$OUTPUT" <<'PY'
import hashlib
import json
import sys

import yaml

services_path, environment, output_path = sys.argv[1:4]
doc = yaml.safe_load(open(services_path))
host = doc["environments"][environment]["host"]

GROUP_ORDER = ["infra", "apps", "media", "tools"]
COLUMNS = 10
TILE_WIDTH = 2
TILE_HEIGHT = 1
ICON_BASE = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg"


def stable_id(kind: str, name: str) -> str:
    """A cuid2-shaped id (24 lowercase alphanumerics) derived from the name."""
    digest = hashlib.sha256(f"homelab:{kind}:{name}".encode()).digest()
    alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
    value = int.from_bytes(digest, "big")
    out = []
    while len(out) < 24:
        value, index = divmod(value, len(alphabet))
        out.append(alphabet[index])
    return "".join(out)


def base_url(service: dict) -> str:
    if service.get("public_url"):
        return service["public_url"].rstrip("/")
    scheme = "https" if service.get("check") == "https" else "http"
    return f"{scheme}://{host}:{service['port']}"


def href_for(service: dict) -> str:
    """Where a click should land — a health path under /api is not a UI."""
    path = service.get("path", "/")
    if path.startswith("/api"):
        path = "/"
    return f"{base_url(service)}{path}"


def ping_for(service: dict) -> str | None:
    if service.get("check") not in ("http", "https"):
        return None
    return f"{base_url(service)}{service.get('path', '/')}"


apps, items = [], []
column = row = 0

for group in GROUP_ORDER:
    members = [
        service
        for service in doc["services"]
        if (service.get("dashboard") or {}).get("group") == group
        and not (service.get("dashboard") or {}).get("hidden")
        and service.get("port")
    ]
    if not members:
        continue
    if column:  # start every group on a fresh row
        column = 0
        row += TILE_HEIGHT
    for service in members:
        app_id = stable_id("app", service["name"])
        icon = (service.get("dashboard") or {}).get("icon", service["name"])
        apps.append({
            "id": app_id,
            "name": service.get("title", service["name"]),
            "description": f"{group} · {service.get('priority', '')}".strip(" ·"),
            "iconUrl": f"{ICON_BASE}/{icon}.svg",
            "href": href_for(service),
            "pingUrl": ping_for(service),
        })
        items.append({
            "id": stable_id("item", service["name"]),
            "kind": "app",
            "appId": app_id,
            "xOffset": column,
            "yOffset": row,
            "width": TILE_WIDTH,
            "height": TILE_HEIGHT,
        })
        column += TILE_WIDTH
        if column + TILE_WIDTH > COLUMNS:
            column = 0
            row += TILE_HEIGHT

board_name = f"homelab-{environment}"
seed = {
    "generatedFrom": "config/services.yml",
    "environment": environment,
    "board": {
        "id": stable_id("board", board_name),
        "name": board_name,
        "pageTitle": f"Homelab ({environment})",
        "isPublic": False,
    },
    "layout": {
        "id": stable_id("layout", board_name),
        "name": "Base",
        "columnCount": COLUMNS,
        "breakpoint": 0,
    },
    "section": {
        "id": stable_id("section", board_name),
        "kind": "empty",
        "xOffset": 0,
        "yOffset": 0,
    },
    "apps": apps,
    "items": items,
}

with open(output_path, "w") as handle:
    json.dump(seed, handle, indent=2, ensure_ascii=False)
    handle.write("\n")

print(f"{output_path}: {len(items)} tiles from {len(GROUP_ORDER)} groups")
PY
