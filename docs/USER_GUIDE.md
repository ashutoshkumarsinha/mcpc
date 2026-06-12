# MCPC User Guide

This guide explains how to install MCPC, configure MCP servers, and use the command-line client and macOS GUI.

## What is MCPC?

MCPC is a **client** for the [Model Context Protocol (MCP)](https://modelcontextprotocol.io). MCP servers expose **tools** (callable functions), **resources** (readable data), and **prompts** (templated instructions). MCPC connects to those servers so you can list and invoke their capabilities from the terminal or a desktop app.

MCPC is a **pure Swift** client. It is **server-agnostic**: you define MCP servers in `config.toml` (stdio subprocess, HTTP/SSE, or WebSocket). The packaged macOS app is branded **MCP Client** and stores config in `~/.mcpc/`. The only Python in this repo is the bundled `test-server/` used for integration tests.

## Installation

### Prerequisites

1. **macOS 14 or later**
2. **Xcode Command Line Tools** (provides Swift):
   ```bash
   xcode-select --install
   ```

**Optional (integration tests only):** [uv](https://docs.astral.sh/uv/) to run the bundled Python test server via `make test`.

### Build from source

```bash
cd /path/to/mcpc
swift build
```

Binaries are placed in `.build/debug/`:

- `mcpc` — CLI
- `mcpc-gui` — GUI

Optional: add to your PATH:

```bash
export PATH="/path/to/mcpc/.build/debug:$PATH"
```

### DMG distribution (GUI app)

Build a release `.app` bundle and compressed DMG installer:

```bash
make dmg
```

Output:

- `dist/MCP Client.app` — drag to Applications
- `dist/MCP Client-<version>.dmg` — shareable installer image

The DMG includes `config.toml.example` and `DMG_README.txt` as references. **You do not copy these into the app bundle.** On first launch, **MCP Client** creates `~/.mcpc/` automatically (see below).

Customize packaging:

```bash
APP_NAME=MCPC BUNDLE_ID=com.example.mcpc CODE_SIGN_IDENTITY="-" make dmg
```

Use `make app` to build only the `.app` bundle without creating a DMG.

### Install CLI binaries to PATH

```bash
make install
# Installs .build/release/mcpc and mcpc-gui to $(PREFIX)/bin (default /usr/local/bin)
```

## Testing

MCPC includes Swift unit tests and shell integration tests against the bundled test server.

| Command | What it runs |
|---------|--------------|
| `make test` | Everything: `swift test` + CLI stdio + CLI errors + SSE |
| `make test-unit` | Swift unit tests only (`MCPCTests`, `MCPClientGUITests`) |
| `make test-cli` | CLI integration scripts (`test_swift_client.sh`, `test_cli.sh`) |
| `make test-sse` | SSE transport integration (`test_sse_client.sh`) |

**Prerequisite:** [uv](https://docs.astral.sh/uv/) for integration tests and GUI live-server tests.

```bash
make test
# or run scripts directly:
./scripts/test_all.sh
swift test
```

Unit tests cover config validation, CLI argument parsing, Cursor `mcp.json` import/sync, SSE message filtering, and GUI model operations (including connect → call tool → disconnect against the test server).

## Configuration

### User data directory (`~/.mcpc`)

**MCP Client** (the packaged GUI) stores per-user configuration and logs under your home directory:

| Path | Purpose |
|------|---------|
| `~/.mcpc/` | Created on first app launch (or first CLI run when no other config exists) |
| `~/.mcpc/config.toml` | MCP server definitions and client settings |
| `~/.mcpc/mcpc.log` | Application diagnostic log (when file logging is enabled) |

**First launch** — opening **MCP Client** from Applications:

1. Creates `~/.mcpc/` if it does not exist
2. Writes a starter `config.toml` (only if missing — your existing config is never overwritten)
3. Creates an empty `mcpc.log` if missing

The starter config enables Cursor hot reload, sets `destination = "file"`, and includes commented `[[servers]]` examples. Add servers by editing the file, using **Import Cursor MCP JSON…**, or enabling hot reload to sync from `~/.cursor/mcp.json`.

Open the config quickly:

```bash
open -e ~/.mcpc/config.toml    # TextEdit
# or
$EDITOR ~/.mcpc/config.toml
```

View recent logs:

```bash
tail -f ~/.mcpc/mcpc.log
```

### Config file location

**GUI** — always defaults to `~/.mcpc/config.toml`. Use **Choose config.toml…** in the sidebar or set `MCPC_CONFIG` to override.

**CLI** — resolution order:

1. `--config /path/to/config.toml` (`-c`)
2. `MCPC_CONFIG` environment variable
3. `./config.toml` in the **current working directory** (if the file exists — typical for repo development)
4. `~/.mcpc/config.toml` — created automatically when steps 1–3 do not find a config

When developing in the repository, run CLI commands from the project root so paths like `test-server/` in the repo `config.toml` resolve. For production CLI use without a project config, rely on `~/.mcpc/config.toml`.

Always use absolute paths in `args` when the config file and server working directory may differ.

### Minimal config

```toml
[app]
name = "mcpc"
version = "1.0.0"

[client]
default_server = "test-server"
protocol_version = "2024-11-05"
request_timeout_seconds = 120
log_server_stderr = false

[[servers]]
name = "test-server"
transport = "stdio"
command = "uv"
args = ["run", "--directory", "test-server", "python", "server.py"]
env = { PYTHONUNBUFFERED = "1" }
```

### Adding a stdio MCP server

Spawn any executable that speaks MCP over stdin/stdout:

```toml
[[servers]]
name = "my-swift-server"
transport = "stdio"
command = "/absolute/path/to/.build/debug/my-mcp-server"
args = []
```

```toml
[[servers]]
name = "cursor-style-server"
transport = "stdio"
command = "uv"
args = ["run", "--directory", "/path/to/project", "python", "mcp_server.py"]
env = { PYTHONUNBUFFERED = "1" }
```

Tips:

- Use **absolute paths** for `command` and in `args` unless you always launch from a known cwd.
- Set `log_server_stderr = true` to forward subprocess stderr (useful when debugging stdio servers).
- Per-server `env` merges into a minimal subprocess environment (`HOME`, `PATH`, etc.).

### Adding a remote SSE server

SSE (MCP 2024-11-05): open a GET stream at `url`, POST JSON-RPC to the session endpoint announced in the first `endpoint` event.

```toml
[[servers]]
name = "remote-api"
transport = "sse"
url = "https://example.com/mcp/sse"
trust_self_signed_certificates = false
max_reconnect_attempts = 3
reconnect_base_delay_seconds = 1.0

[servers.remote-api.headers]
Authorization = "Bearer YOUR_TOKEN_HERE"
```

`http_sse` is accepted as an alias for `sse`. FastMCP and similar servers that return `202 Accepted` with a plain-text body are supported.

### Adding a Streamable HTTP server

```toml
[[servers]]
name = "remote-streamable"
transport = "streamable_http"
url = "http://127.0.0.1:8080/mcp"
```

### Adding a WebSocket server

```toml
[[servers]]
name = "ws-server"
transport = "websocket"
url = "wss://example.com/mcp/ws"
```

### Client settings explained

| Setting | What it does |
|---------|--------------|
| `default_server` | Server used when you do not pass `-s` |
| `protocol_version` | MCP protocol version for the handshake |
| `request_timeout_seconds` | How long to wait for a server response |
| `log_server_stderr` | Print subprocess stderr (useful for debugging stdio servers) |
| `mcp_json_hot_reload` | Sync Cursor `mcp.json` into `config.toml` when the file changes (GUI) |
| `mcp_json_watch_paths` | Override which `mcp.json` files to watch |
| `mcp_json_synced_servers` | Names of servers managed by Cursor sync (auto-maintained) |

### Logging settings

MCPC writes structured logs to stderr by default. The production GUI template uses file logging under `~/.mcpc`. Configure in `config.toml`:

```toml
[logging]
level = "info"
destination = "file"
log_file = "mcpc.log"

[logging.components]
mcpc = "debug"
MCPClient = "warning"
```

| Setting | Values | Description |
|---------|--------|-------------|
| `level` | `trace` … `critical`, `none` | Default verbosity for all loggers |
| `destination` | `stderr`, `stdout`, `none`, `file` | Where MCPC writes its own logs |
| `log_file` | file name or path | Log file when `destination = "file"` (relative paths resolve under `~/.mcpc`) |
| `logging.components` | label → level | Per-component overrides (prefix match) |

Examples:

- **Production GUI (default):** `destination = "file"` and `log_file = "mcpc.log"` → logs append to `~/.mcpc/mcpc.log`.
- **Development / CLI:** `destination = "stderr"` to see logs in the terminal.
- **Debug transport issues:** set `mcpc = "debug"` or global `level = "debug"`.
- **Silence everything:** `destination = "none"`.
- **Quiet SwiftMCPClient shutdown warnings:** `MCPClient = "error"`.
- **Custom log path:** `log_file = "/tmp/mcpc-debug.log"` or `log_file = "~/Desktop/mcpc.log"`.

Note: `log_server_stderr` forwards the **MCP server's** stderr; `[logging]` controls **MCPC's** own diagnostic output.

## Using the CLI

### Help

```bash
swift run mcpc --help
```

### List configured servers

```bash
mcpc list-servers
```

Output shows transport type and launch command or URL. The default server is marked `(default)`.

### Select a server

```bash
mcpc -s my-project ping
```

Or set `default_server` in config and omit `-s`.

### Check connectivity

```bash
mcpc ping
# Connected to MCPC Test Server v1.27.2
# pong
```

### Explore capabilities

```bash
mcpc list-tools
mcpc list-resources
mcpc list-prompts
```

### Call a tool

Pass arguments as `--key value` pairs:

```bash
mcpc call-tool echo --message "hello world"
mcpc call-tool add --a 2 --b 40
```

For complex nested arguments, use JSON:

```bash
mcpc call-tool my_tool --args '{"query":"search term","limit":10}'
```

Tool errors print to stderr and exit with code 2.

### Read a resource

```bash
mcpc read-resource "test://info"
```

### Run a prompt

```bash
mcpc get-prompt greet --name "Alice" --tone "formal"
```

### Use a different config file

```bash
mcpc -c /path/to/other-config.toml list-servers
export MCPC_CONFIG=/path/to/other-config.toml
mcpc ping
```

## Using the GUI

### Launch

```bash
./scripts/run_gui.sh
# or
swift run mcpc-gui
```

### Workflow

1. **Choose config** — The sidebar shows `~/.mcpc/config.toml` by default. Click "Choose config.toml…" to use a different file.
2. **Select a server** — Click a server name in the sidebar.
3. **Connect** — Click **Connect** (⌘↩). The status indicator turns green when connected.
4. **Explore tabs:**
   - **Tools** — Select a tool, edit JSON arguments, click **Run Tool** (⌘⇧↩).
   - **Resources** — Select a resource URI, click **Read Resource**.
   - **Prompts** — Select a prompt, edit arguments, click **Run Prompt**.
5. **Output** — Results appear in the bottom panel. Errors are shown in red.
6. **Disconnect** — Click **Disconnect** when finished.

### Ping

While connected, use the **Ping** button to verify the server is responsive.

### Import Cursor servers

1. Click **Import from Cursor…** in the sidebar.
2. Paste JSON, load a file, or use `~/.cursor/mcp.json`.
3. Preview imported servers and choose **Skip existing** or **Replace existing** on name conflicts.
4. Imported servers are written to the active `config.toml`.

### Cursor hot reload

When `mcp_json_hot_reload = true` (default in the project `config.toml`), the GUI watches `~/.cursor/mcp.json` and `.cursor/mcp.json` next to your config file. Changes are merged into `config.toml` automatically. Toggle the feature from the sidebar; manually added servers are preserved unless they share a name with a synced server.

If you are connected and a synced server's definition changes, the GUI disconnects and asks you to reconnect.

### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘↩ | Connect |
| ⌘⇧↩ | Run selected tool |

## Bundled test server (Python)

The repository includes a small **Python** [FastMCP](https://github.com/modelcontextprotocol/python-sdk) server for integration tests only. MCPC itself is Swift; you do not need Python unless you run `make test` or use `test-server` as your configured server.

```bash
# Manual server start (usually MCPC spawns it automatically)
cd test-server
uv run python server.py
```

Capabilities:

| Type | Name | Example |
|------|------|---------|
| Tool | `echo` | `--message "hi"` |
| Tool | `add` | `--a 1 --b 2` |
| Tool | `server_info` | (no args) |
| Resource | `test://info` | static JSON |
| Resource | `test://time/utc` | UTC timestamp |
| Prompt | `greet` | `--name Swift` |

Run the full test suite:

```bash
make test
```

Or individual integration scripts:

```bash
./scripts/test_swift_client.sh   # CLI over stdio
./scripts/test_cli.sh            # CLI help and error paths
./scripts/test_sse_client.sh     # CLI over SSE
```

## Troubleshooting

### `Config not found at ...`

MCPC cannot find `config.toml`. Either:

- Launch MCP Client once to create `~/.mcpc/config.toml`, or
- `cd` to the directory containing the config, or
- Pass `-c /full/path/config.toml`, or
- Set `MCPC_CONFIG`.

### `Server 'foo' not found`

The `-s` name does not match any `[[servers]].name`. Run `mcpc list-servers` to see valid names.

### `uv: command not found`

Only required for the bundled `test-server`. Install [uv](https://docs.astral.sh/uv/) or use a non-Python MCP server in `config.toml`.

### Where are my logs?

| Setup | Location |
|-------|----------|
| **MCP Client** (default template) | `~/.mcpc/mcpc.log` |
| `destination = "stderr"` or `"stdout"` | Terminal / Console.app (when launched from CLI) |
| Custom `log_file` | Path you set (relative paths are under `~/.mcpc`) |

```bash
tail -f ~/.mcpc/mcpc.log
```

If the log file is empty, raise verbosity: set `level = "debug"` or `mcpc = "debug"` in `[logging.components]`, then restart the app.

### CLI hangs or times out

- Increase `request_timeout_seconds` in config.
- Enable `log_server_stderr = true` to see server errors.
- Check `~/.mcpc/mcpc.log` (GUI) or stderr (CLI) for transport errors.
- Confirm the server command works standalone:
  ```bash
  uv run --directory test-server python server.py
  ```
- Heavy servers (large ML models) may take minutes on first start.

### Relative path errors for stdio servers

Paths like `test-server` in `args` are relative to the **process cwd**, not the config file. Run from the project root or switch to absolute paths.

### GUI warning on quit

A `transport receive failed` / `MCPError error 5` message during shutdown is expected when disconnecting; recent versions suppress this in the GUI. It does not indicate a functional problem.

### Tool returns exit code 2

The server reported a tool error (`isError: true`). Check stderr for the message and verify your arguments match the tool schema (`mcpc list-tools` shows descriptions).

### HTTP/SSE certificate errors

For local dev servers with self-signed TLS:

```toml
trust_self_signed_certificates = true
```

Use with caution in production.

## Tips for daily use

- **GUI / DMG installs:** edit `~/.mcpc/config.toml`; logs are in `~/.mcpc/mcpc.log` by default.
- **Per-project CLI:** keep `config.toml` in the repo and run `mcpc` from that directory, or set `MCPC_CONFIG` in shell profiles.
- Use `config.local.toml` (gitignored) for machine-specific paths and secrets in development trees.
- Prefer `mcpc` in scripts and CI; use **MCP Client** for exploratory debugging.
- Run `make test` before committing changes that touch config, transports, or the GUI model.
- Distribute the GUI with `make dmg`; share `dist/MCP Client-<version>.dmg`.
- After changing server code, disconnect and reconnect (or restart the CLI) to pick up changes.

## Further reading

- [Technical Specification](SPEC.md) — full config schema and behavioral contracts
- [High-Level Design](HLD.md) — architecture and component interactions
- [MCP documentation](https://modelcontextprotocol.io) — protocol reference
