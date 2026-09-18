# layr8-broker

Single-file binaries and a one-line installer for **`layr8-broker`** — the local
MCP broker that connects Claude Code, Claude Desktop, Cursor, Codex, and other
MCP clients to a layr8 Space over a single stable identity.

## Install (no Node required)

```sh
curl -fsSL https://raw.githubusercontent.com/layr8/broker/main/install.sh | sh
```

macOS and Linux (arm64 / x64). Installs to `~/.local/bin` (override with
`LAYR8_BIN_DIR`). Two more environment variables pick something other than the
newest stable release:

```sh
# exactly one version, a prerelease included
curl -fsSL https://raw.githubusercontent.com/layr8/broker/main/install.sh | LAYR8_VERSION=0.4.0 sh
# the next channel: the newest release, prereleases included, followed from then on
curl -fsSL https://raw.githubusercontent.com/layr8/broker/main/install.sh | LAYR8_CHANNEL=next sh
```

Prefer npm? `npm i -g @layr8/mcp` (needs Node ≥ 20).

Then connect an agent from the portal (**Agents → Connect an agent**), and
optionally run it always-on with automatic updates:

```sh
layr8-broker service install --env <label>
```

## Distribution

Binaries are published to the public OCI registry **`ghcr.io/layr8/broker`**
(per-platform `latest-<os>-<arch>` tags). The installer and the broker's
self-update pull anonymously from there and verify each download against its
content digest.

This repo publishes the installer script; it is written and reviewed in the
broker's own repository, and copied here unchanged. A check there compares this
published copy with the source and fails when the two differ.
