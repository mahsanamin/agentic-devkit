#!/usr/bin/env bash
# install.sh — download the latest mdcf release for this machine and install
# it to /usr/local/bin. Requires curl.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/mahsanamin/mdcf/main/install.sh | bash
#
# Env overrides:
#   MDCF_REPO    Owner/repo to pull from (default: mahsanamin/mdcf)
#   MDCF_PREFIX  Install prefix (default: /usr/local/bin)
set -euo pipefail

REPO="${MDCF_REPO:-mahsanamin/mdcf}"
PREFIX="${MDCF_PREFIX:-/usr/local/bin}"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Darwin)
    case "$arch" in
      arm64)  asset="mdcf-darwin-arm64" ;;
      x86_64) asset="mdcf-darwin-amd64" ;;
      *) echo "unsupported macOS architecture: $arch" >&2; exit 1 ;;
    esac
    ;;
  Linux)
    case "$arch" in
      x86_64) asset="mdcf-linux-amd64" ;;
      *) echo "unsupported Linux architecture: $arch" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "unsupported OS: $os" >&2; exit 1 ;;
esac

url="https://github.com/${REPO}/releases/latest/download/${asset}"
tmp="$(mktemp -t mdcf.XXXXXX)"
trap 'rm -f "$tmp"' EXIT

echo "Downloading $url…"
curl -fsSL -o "$tmp" "$url"
chmod +x "$tmp"

dest="${PREFIX}/mdcf"
if [ -w "$PREFIX" ]; then
  mv "$tmp" "$dest"
else
  sudo mv "$tmp" "$dest"
fi

echo "Installed $dest"
"$dest" --version || true
