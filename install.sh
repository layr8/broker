#!/bin/sh
# layr8-broker installer (LAYR8-752a) — downloads the single-file binary for this
# OS/arch from the latest GitHub Release and installs it. No Node/npm needed.
#
#   curl -fsSL https://raw.githubusercontent.com/layr8/broker/main/install.sh | sh
#
# Env overrides: LAYR8_BIN_DIR (install dir, default ~/.local/bin),
#                LAYR8_VERSION (a specific tag, e.g. v0.1.7; default: latest).
set -eu

REPO="layr8/broker"
BIN="layr8-broker"

os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *) echo "unsupported OS: $os (binaries: darwin, linux). Use: npm i -g @layr8/mcp" >&2; exit 1 ;;
esac
case "$arch" in
  arm64 | aarch64) arch="arm64" ;;
  x86_64 | amd64) arch="x64" ;;
  *) echo "unsupported arch: $arch. Use: npm i -g @layr8/mcp" >&2; exit 1 ;;
esac
asset="${BIN}-${os}-${arch}"

tag="${LAYR8_VERSION:-}"
if [ -z "$tag" ]; then
  tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4)"
fi
if [ -z "$tag" ]; then
  echo "could not resolve the latest release tag from GitHub" >&2
  exit 1
fi

base="https://github.com/${REPO}/releases/download/${tag}"
dest="${LAYR8_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$dest"
tmp="$(mktemp)"

echo "Installing ${asset} (${tag}) → ${dest}/${BIN}"
curl -fsSL "${base}/${asset}" -o "$tmp"

# Verify the checksum when the release ships SHA256SUMS (all current releases do).
if sums="$(curl -fsSL "${base}/SHA256SUMS" 2>/dev/null)"; then
  want="$(echo "$sums" | grep " ${asset}\$" | awk '{print $1}')"
  if [ -n "$want" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
      got="$(sha256sum "$tmp" | awk '{print $1}')"
    else
      got="$(shasum -a 256 "$tmp" | awk '{print $1}')"
    fi
    if [ "$want" != "$got" ]; then
      echo "checksum mismatch for ${asset} (want ${want}, got ${got}) — aborting" >&2
      rm -f "$tmp"
      exit 1
    fi
    echo "checksum ok"
  fi
fi

chmod +x "$tmp"
mv "$tmp" "${dest}/${BIN}"

echo "Installed ${dest}/${BIN}"
case ":${PATH}:" in
  *":${dest}:"*) : ;;
  *) echo "NOTE: ${dest} is not on your PATH — add it, e.g.  export PATH=\"${dest}:\$PATH\"" ;;
esac
if "${dest}/${BIN}" --help >/dev/null 2>&1; then
  echo "OK. Next:"
  echo "  1. ${BIN} enrol --code <code> --at <stratus-url>   # from the portal"
  echo "  2. ${BIN} service install --env <label>            # always-on + auto-update"
fi
