#!/bin/sh
# layr8-broker installer (LAYR8-752). Pulls the single-file binary for this
# OS/arch from the public OCI registry (ghcr.io/layr8/broker) — anonymous, no
# Node/npm, no auth. The binary self-updates after this.
#
#   curl -fsSL https://raw.githubusercontent.com/layr8/broker/main/install.sh | sh
#
# Env: LAYR8_BIN_DIR (install dir, default ~/.local/bin).
set -eu

REGISTRY="ghcr.io"
IMAGE="layr8/broker"
BIN="layr8-broker"
# oras' empty config ({} = 2 bytes); the manifest's OTHER sha256 is the binary.
EMPTY_CONFIG="44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"

os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *) echo "unsupported OS: $os. Use: npm i -g @layr8/mcp" >&2; exit 1 ;;
esac
case "$arch" in
  arm64 | aarch64) arch="arm64" ;;
  x86_64 | amd64) arch="x64" ;;
  *) echo "unsupported arch: $arch. Use: npm i -g @layr8/mcp" >&2; exit 1 ;;
esac
tag="latest-${os}-${arch}"

api="https://${REGISTRY}/v2/${IMAGE}"

# 1. anonymous pull token (public package)
token="$(curl -fsSL "https://${REGISTRY}/token?scope=repository:${IMAGE}:pull" \
  | tr ',' '\n' | grep '"token"' | head -1 | sed 's/.*"token":"//; s/".*//')"
[ -n "$token" ] || { echo "couldn't get a registry token" >&2; exit 1; }
auth="Authorization: Bearer ${token}"

# 2. manifest for latest-<platform>
manifest="$(curl -fsSL -H "$auth" \
  -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  "${api}/manifests/${tag}")" || { echo "couldn't fetch the manifest for ${tag}" >&2; exit 1; }

# 3. the binary layer digest = the sha256 that isn't the empty config
digest="$(printf '%s' "$manifest" | grep -o '[0-9a-f]\{64\}' | grep -v "${EMPTY_CONFIG}" | head -1)"
[ -n "$digest" ] || { echo "no binary layer in the manifest" >&2; exit 1; }

dest="${LAYR8_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$dest"
tmp="$(mktemp)"

echo "Installing ${BIN} (${os}-${arch}) → ${dest}/${BIN}"
curl -fsSL -H "$auth" "${api}/blobs/sha256:${digest}" -o "$tmp"

# 4. verify the blob against its content digest (integrity for free)
if command -v sha256sum >/dev/null 2>&1; then
  got="$(sha256sum "$tmp" | awk '{print $1}')"
else
  got="$(shasum -a 256 "$tmp" | awk '{print $1}')"
fi
if [ "$digest" != "$got" ]; then
  echo "checksum mismatch (want ${digest}, got ${got}) — aborting" >&2
  rm -f "$tmp"; exit 1
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
