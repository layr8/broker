#!/bin/sh
# layr8-broker installer (LAYR8-752). Pulls the single-file binary for this
# OS/arch from the public OCI registry (ghcr.io/layr8/broker) — anonymous, no
# Node/npm, no auth. The binary self-updates after this, forward only.
#
# Published from the public layr8/broker repository — layr8/mcp is private, so
# only that copy can be curled without a GitHub login:
#
#   curl -fsSL https://raw.githubusercontent.com/layr8/broker/main/install.sh | sh
#
# This file is the source; scripts/check-public-installer.mjs compares the
# published copy with it.
#
# Env:
#   LAYR8_BIN_DIR   install dir, default ~/.local/bin
#   LAYR8_VERSION   install exactly this version, e.g. 0.4.0-rc.1
#   LAYR8_CHANNEL   latest (default: newest stable) or next (newest release,
#                   prereleases included). A channel given here is saved to
#                   ~/.layr8/update.json, so the binary's own update check
#                   keeps following it.
set -eu

REGISTRY="ghcr.io"
IMAGE="layr8/broker"
BIN="layr8-broker"
# oras' empty config ({} = 2 bytes); the manifest's OTHER sha256 is the binary.
EMPTY_CONFIG="44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
MANIFEST_ACCEPT="application/vnd.oci.image.manifest.v1+json"

version="${LAYR8_VERSION:-}"
version="${version#v}"
channel="${LAYR8_UPDATE_CHANNEL:-}"

# A running Layr8 session exports LAYR8_CHANNEL=1 to mean "the bridge is on"
# (layr8/agents claude-code/bin/8claude), so a `curl … | sh` typed inside one
# arrives with LAYR8_CHANNEL=1 — a value that is not a channel. This installer
# used to exit 1 on it, which meant the documented one-liner failed for exactly
# the people most likely to run it: someone already in a session. Say so and
# carry on with the default. LAYR8_UPDATE_CHANNEL is the unambiguous spelling
# and wins when both are set; layr8/agents launcher/install.sh does the same.
if [ -z "$channel" ] && [ -n "${LAYR8_CHANNEL:-}" ]; then
  case "${LAYR8_CHANNEL}" in
    latest | next) channel="${LAYR8_CHANNEL}" ;;
    *)
      echo "NOTE: LAYR8_CHANNEL is '${LAYR8_CHANNEL}', which is not an update channel — a" >&2
      echo "      running Layr8 session exports LAYR8_CHANNEL=1 to mean something else." >&2
      echo "      Ignoring it. To choose a channel here, set LAYR8_UPDATE_CHANNEL=latest|next." >&2
      ;;
  esac
fi

if [ -n "$version" ] && [ -n "$channel" ]; then
  echo "set LAYR8_VERSION or LAYR8_UPDATE_CHANNEL, not both" >&2; exit 1
fi
if [ -n "$version" ] && ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
  echo "LAYR8_VERSION is not a version: ${version}" >&2; exit 1
fi
case "$channel" in
  "" | latest | next) : ;;
  *) echo "LAYR8_UPDATE_CHANNEL must be latest or next (got ${channel})" >&2; exit 1 ;;
esac

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

api="https://${REGISTRY}/v2/${IMAGE}"

# 1. anonymous pull token (public package)
token="$(curl -fsSL "https://${REGISTRY}/token?scope=repository:${IMAGE}:pull" \
  | tr ',' '\n' | grep '"token"' | head -1 | sed 's/.*"token":"//; s/".*//')"
[ -n "$token" ] || { echo "couldn't get a registry token" >&2; exit 1; }
auth="Authorization: Bearer ${token}"

fetch_manifest() {
  curl -fsSL -H "$auth" -H "Accept: ${MANIFEST_ACCEPT}" "${api}/manifests/$1"
}

# 2. the manifest: a version's own tag, or the channel's tag
if [ -n "$version" ]; then
  tag="${version}-${os}-${arch}"
  manifest="$(fetch_manifest "$tag")" || { echo "no published ${BIN} ${version} for ${os}-${arch} (${tag})" >&2; exit 1; }
elif [ "$channel" = "next" ]; then
  tag="next-${os}-${arch}"
  if ! manifest="$(fetch_manifest "$tag" 2>/dev/null)"; then
    # next-* is maintained from the first release after it was introduced;
    # until then the newest release of any kind is the stable one.
    echo "no ${tag} published yet; installing latest instead"
    tag="latest-${os}-${arch}"
    manifest="$(fetch_manifest "$tag")" || { echo "couldn't fetch the manifest for ${tag}" >&2; exit 1; }
  fi
else
  tag="latest-${os}-${arch}"
  manifest="$(fetch_manifest "$tag")" || { echo "couldn't fetch the manifest for ${tag}" >&2; exit 1; }
fi

published="$(printf '%s' "$manifest" | tr ',{}' '\n\n\n' \
  | grep '"org.opencontainers.image.version"' | head -1 | sed 's/.*"org.opencontainers.image.version":"//; s/".*//')"
if [ -n "$version" ] && [ "$published" != "$version" ]; then
  echo "tag ${tag} carries version '${published}', not ${version} — aborting" >&2; exit 1
fi

# 3. the binary layer digest = the sha256 that isn't the empty config
digest="$(printf '%s' "$manifest" | grep -o '[0-9a-f]\{64\}' | grep -v "${EMPTY_CONFIG}" | head -1)"
[ -n "$digest" ] || { echo "no binary layer in the manifest" >&2; exit 1; }

dest="${LAYR8_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$dest"
tmp="$(mktemp)"

echo "Installing ${BIN} ${published:-?} (${os}-${arch}, ${tag}) → ${dest}/${BIN}"
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

echo "Installed ${dest}/${BIN} (sha256:${got})"

# 5. remember an explicitly chosen channel for the binary's own update check
if [ -n "$channel" ]; then
  mkdir -p "$HOME/.layr8"
  printf '{"channel":"%s"}\n' "$channel" > "$HOME/.layr8/update.json"
  echo "Update channel: ${channel} (saved to ~/.layr8/update.json)"
fi

case ":${PATH}:" in
  *":${dest}:"*) : ;;
  *) echo "NOTE: ${dest} is not on your PATH — add it, e.g.  export PATH=\"${dest}:\$PATH\"" ;;
esac
if "${dest}/${BIN}" --help >/dev/null 2>&1; then
  echo "OK. Next:"
  echo "  1. ${BIN} enrol --code <code> --at <stratus-url>   # from the portal"
  echo "  2. ${BIN} service install --env <label>            # always-on + auto-update"
fi
