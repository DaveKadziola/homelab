#!/usr/bin/env bash
# Register a self-hosted GitHub Actions runner for homelab v2.
# Usage: ./utils/setup-github-runner.sh --label homelab-dev --name homelab-dev-laptop
set -euo pipefail

REPO="${GITHUB_REPO:-DaveKadziola/homelab}"
RUNNER_VERSION="${RUNNER_VERSION:-2.325.0}"
INSTALL_DIR="${RUNNER_INSTALL_DIR:-$HOME/actions-runner-homelab}"
LABELS=""
RUNNER_NAME=""

usage() {
  echo "Usage: $0 --label LABEL [--name NAME] [--install-dir DIR]"
  echo "  --label   Runner label (homelab-dev or homelab-prod)"
  echo "  --name    Runner display name (default: hostname-label)"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABELS="$2"; shift 2 ;;
    --name) RUNNER_NAME="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -n "$LABELS" ]] || usage
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-${LABELS}}"

command -v gh >/dev/null || { echo "gh CLI required"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated"; exit 1; }

TOKEN=$(gh api -X POST "repos/${REPO}/actions/runners/registration-token" --jq .token)

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [[ ! -f ./config.sh ]]; then
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Unsupported arch: $ARCH"; exit 1 ;;
  esac
  curl -fsSL -o actions-runner.tar.gz \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"
  tar xzf actions-runner.tar.gz
  rm -f actions-runner.tar.gz
fi

./config.sh \
  --url "https://github.com/${REPO}" \
  --token "$TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "self-hosted,linux,${LABELS}" \
  --unattended \
  --replace

echo "Runner configured in ${INSTALL_DIR}"
echo "Start interactively: cd ${INSTALL_DIR} && ./run.sh"
echo "Install as service (requires sudo): cd ${INSTALL_DIR} && sudo ./svc.sh install && sudo ./svc.sh start"
