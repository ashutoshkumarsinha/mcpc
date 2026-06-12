# MCPC User Guide

This guide explains how to install MCPC, configure MCP servers, and use the command-line client and macOS GUI.

## What is MCPC?

MCPC is a **client** for the [Model Context Protocol (MCP)](https://modelcontextprotocol.io). MCP servers expose **tools** (callable functions), **resources** (readable data), and **prompts** (templated instructions). MCPC connects to those servers so you can list and invoke their capabilities from the terminal or a desktop app.

MCPC is a **pure Swift** client. It is **server-agnostic**: you define MCP servers in `config.toml` (stdio subprocess, HTTP/SSE, or WebSocket). The only Python in this repo is the bundled `test-server/` used for integration tests.

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

- `dist/MCPC.app` — drag to Applications
- `dist/MCPC-<version>.dmg` — shareable installer image

The DMG includes `config.toml.example` and a short README. Copy the example to a working directory, edit your MCP servers, then launch MCPC. The app reads `config.toml` from the current working directory unless `MCPC_CONFIG` is set.

Customize packaging:

```bash
APP_NAME=MCPC BUNDLE_ID=com.example.mcpc CODE_SIGN_IDENTITY="-" make dmg
```

Use `make app` to build only the `.app` bundle without creating a DMG.

## Configuration

### Config file location

MCPC looks for configuration in this order:

1. `--config /path/to/config.toml` (CLI) or a file chosen in the GUI
2. `MCPC_CONFIG` environment variable
3. `./config.toml` in the **current working directory**

Always run MCPC from a directory where paths in the config resolve correctly, or use absolute paths in `args`.

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

### Logging settings

MCPC writes structured logs to stderr by default. Configure in `config.toml`:

```toml
[logging]
level = "info"
destination = "stderr"

[logging.components]
mcpc = "debug"
MCPClient = "warning"
```

| Setting | Values | Description |
|---------|--------|-------------|
| `level` | `trace` … `critical`, `none` | Default verbosity for all loggers |
| `destination` | `stderr`, `stdout`, `none` | Where MCPC writes its own logs |
| `logging.components` | label → level | Per-component overrides (prefix match) |

Examples:

- **Debug transport issues:** set `mcpc = "debug"` or global `level = "debug"`.
- **Silence everything:** `destination = "none"`.
- **Quiet SwiftMCPClient shutdown warnings:** `MCPClient = "error"`.

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

1. **Choose config** — Click "Choose config.toml…" in the sidebar if your config is not the default `./config.toml`.
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

Run the full integration test:

```bash
./scripts/test_swift_client.sh
```

## Troubleshooting

### `Config not found at ...`

MCPC cannot find `config.toml`. Either:

- `cd` to the directory containing the config, or
- Pass `-c /full/path/config.toml`, or
- Set `MCPC_CONFIG`.

### `Server 'foo' not found`

The `-s` name does not match any `[[servers]].name`. Run `mcpc list-servers` to see valid names.

### `uv: command not found`

Only required for the bundled `test-server`. Install [uv](https://docs.astral.sh/uv/) or use a non-Python MCP server in `config.toml`.

### CLI hangs or times out

- Increase `request_timeout_seconds` in config.
- Enable `log_server_stderr = true` to see server errors.
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

- Keep one `config.toml` per project, or use `MCPC_CONFIG` in shell profiles.
- Use `config.local.toml` (gitignored) for machine-specific paths and secrets.
- Prefer `mcpc` in scripts and CI; use `mcpc-gui` for exploratory debugging.
- After changing server code, disconnect and reconnect (or restart the CLI) to pick up changes.

## Further reading

- [Technical Specification](SPEC.md) — full config schema and behavioral contracts
- [High-Level Design](HLD.md) — architecture and component interactions
- [MCP documentation](https://modelcontextprotocol.io) — protocol reference
