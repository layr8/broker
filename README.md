# layr8-broker

Single-file binaries and a one-line installer for **`layr8-broker`** — the local
MCP broker that connects Claude Code, Claude Desktop, Cursor, Codex, and other
MCP clients to a layr8 Space over a single stable identity.

## Install (no Node required)

```sh
curl -fsSL https://raw.githubusercontent.com/layr8/broker/main/install.sh | sh
```

macOS and Linux (arm64 / x64). Installs to `~/.local/bin` (override with
`LAYR8_BIN_DIR`). Prefer npm? `npm i -g @layr8/mcp` (needs Node ≥ 20).

Then connect an agent from the portal (**Agents → Connect an agent**), and
optionally run it always-on with automatic updates:

```sh
layr8-broker service install --env <label>
```

## Releases

Each [release](https://github.com/layr8/broker/releases) attaches the
per-platform binaries and a `SHA256SUMS`. `latest.json` tracks the current
version (used for self-update). The installer verifies the SHA-256 of every
download.
