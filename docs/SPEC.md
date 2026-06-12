# MCPC Technical Specification

**Version:** 1.0.0  
**Platform:** macOS 14+  
**Language:** Swift 6

## 1. Purpose

MCPC is a generic MCP client for macOS. It reads server definitions from a TOML configuration file, establishes a transport connection, performs the MCP initialize handshake, and exposes tools, resources, and prompts through a CLI, a GUI, and a reusable Swift library.

This document defines functional requirements, configuration schema, supported MCP operations, and behavioral contracts.

## 2. Scope

### In scope

- MCP protocol version `2024-11-05` (configurable via `client.protocol_version`)
- Transports: **stdio**, **sse**, **streamable_http**, **websocket** (`http_sse` accepted as alias for `sse`)
- MCP operations: `initialize`, `ping`, `tools/list`, `tools/call`, `resources/list`, `resources/read`, `prompts/list`, `prompts/get`
- TOML-based multi-server configuration
- Cursor `mcp.json` import and optional hot-reload into `config.toml` (GUI)
- CLI with structured exit codes
- macOS GUI for interactive server exploration
- Custom stdio subprocess transport with deadlock-safe I/O
- DMG packaging for the GUI app (`make dmg`)
- Automated test suite: Swift unit tests + CLI/SSE integration scripts

### Out of scope

- Acting as an MCP server
- OAuth or dynamic credential flows beyond static HTTP headers
- Windows or Linux client targets (library stdio transport includes Linux guards, but the package targets macOS only)
- Persistent connection pooling across CLI invocations
- MCP sampling or elicitation callbacks

## 3. Products

| Product | Type | Entry point |
|---------|------|-------------|
| `MCPC` | Library | `import MCPC` |
| `MCPClientGUICore` | Library | `import MCPClientGUICore` |
| `mcpc` | CLI executable | `Sources/MCPClientCLI/main.swift` |
| `mcpc-gui` | GUI executable | `Sources/MCPClientGUI/MCPClientGUIApp.swift` |

## 4. Configuration specification

### 4.1 File location

Resolution order:

1. Path given by `--config` / `-c`
2. `MCPC_CONFIG` environment variable
3. `./config.toml` relative to the process current working directory

### 4.2 Schema

#### `[app]`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `name` | string | `"mcpc"` | Client name sent in MCP `initialize` |
| `version` | string | `"1.0.0"` | Client version sent in MCP `initialize` |

#### `[client]`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `default_server` | string | `""` | Server name used when `--server` is omitted |
| `protocol_version` | string | `"2024-11-05"` | MCP protocol version for handshake |
| `request_timeout_seconds` | integer | `120` | Per-request timeout for MCP calls |
| `log_server_stderr` | boolean | `false` | Forward subprocess stderr to client stderr (stdio only) |
| `mcp_json_hot_reload` | boolean | `false` | Watch Cursor `mcp.json` and sync into `config.toml` (GUI) |
| `mcp_json_watch_paths` | string array | `[]` | Override watch paths (default: `~/.cursor/mcp.json`, `.cursor/mcp.json`) |
| `mcp_json_synced_servers` | string array | `[]` | Server names managed by Cursor sync (written by importer) |

#### `[logging]`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `level` | enum | `info` | Global log level: `trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical`, `none` |
| `destination` | enum | `stderr` | Log output: `stderr`, `stdout`, or `none` (disable MCPC logs) |

#### `[logging.components]`

Optional per-label overrides. Keys match logger labels exactly or as prefixes (longest prefix wins). Unspecified labels use the global `level`. Defaults always include `MCPClient = warning` unless overridden.

| Key | Example | Description |
|-----|---------|-------------|
| `mcpc` | `debug` | MCPC library loggers (`mcpc.config`, `mcpc.session`, …) |
| `MCPClient` | `error` | SwiftMCPClient dependency loggers |

#### `[[servers]]`

Each table defines one named MCP server.

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | string | yes | Unique server identifier |
| `transport` | enum | yes | `stdio`, `sse`, `streamable_http`, or `websocket` |
| `command` | string | stdio | Executable to spawn |
| `args` | string array | no | Command-line arguments |
| `env` | string map | no | Extra environment variables for subprocess |
| `working_directory` | string | no | Subprocess cwd (stdio only) |
| `url` | string | sse, streamable_http, websocket | Endpoint URL |
| `headers` | string map | no | HTTP headers for remote transports |
| `trust_self_signed_certificates` | boolean | no | TLS trust override (default `false`) |
| `connection_timeout_seconds` | integer | no | Connect timeout for HTTP/SSE (default `30`) |
| `max_reconnect_attempts` | integer | no | SSE reconnect attempts (default `3`) |
| `reconnect_base_delay_seconds` | number | no | SSE reconnect backoff base in seconds (default `1.0`) |

Server names must be unique. Each server entry is validated at load time.

#### Transport validation rules

- **stdio:** `command` must be non-empty
- **sse:** `url` must be the SSE GET endpoint (e.g. `http://host/sse`)
- **streamable_http:** `url` must be the MCP POST endpoint (e.g. `http://host/mcp`)
- **websocket:** `url` must be non-empty and parseable as a URL

### 4.3 Example: stdio server (Swift binary)

```toml
[[servers]]
name = "my-swift-server"
transport = "stdio"
command = "/path/to/mcp-server"
args = []
```

### 4.4 Example: stdio server (external subprocess)

```toml
[[servers]]
name = "external-stdio"
transport = "stdio"
command = "uv"
args = ["run", "--directory", "/path/to/project", "python", "mcp_server.py"]
env = { PYTHONUNBUFFERED = "1" }
```

### 4.5 Example: SSE server (MCP 2024-11-05)

```toml
[[servers]]
name = "remote-sse"
transport = "sse"
url = "http://127.0.0.1:8080/sse"
trust_self_signed_certificates = false
connection_timeout_seconds = 30
max_reconnect_attempts = 3
reconnect_base_delay_seconds = 1.0

[servers.remote-sse.headers]
Authorization = "Bearer <token>"
```

### 4.6 Example: Streamable HTTP server (MCP 2025-03-26)

```toml
[[servers]]
name = "remote-streamable"
transport = "streamable_http"
url = "http://127.0.0.1:8080/mcp"
```

## 5. MCP protocol coverage

### 5.1 Handshake

On connect, `MCPClientSession` calls `initialize` with:

- `clientName` ← `app.name`
- `clientVersion` ← `app.version`
- `protocolVersion` ← `client.protocol_version`

The `InitializeResult` (server name, version, capabilities) is stored on the session.

### 5.2 Supported methods

| MCP method | Library API | CLI command | GUI action |
|------------|-------------|-------------|------------|
| `ping` | `ping()` | `ping` | Ping button |
| `tools/list` | `listTools()` | `list-tools` | Auto on connect |
| `tools/call` | `callTool(name:arguments:)` | `call-tool` | Run Tool |
| `resources/list` | `listResources()` | `list-resources` | Auto on connect |
| `resources/read` | `readResource(uri:)` | `read-resource` | Read Resource |
| `prompts/list` | `listPrompts()` | `list-prompts` | Auto on connect |
| `prompts/get` | `getPrompt(name:arguments:)` | `get-prompt` | Run Prompt |

### 5.3 Content handling

- **Tool results:** Text content is concatenated with newlines. Images and embedded resources are summarized with bracketed placeholders.
- **Resource contents:** Text and blob URIs are formatted with MIME type annotations.
- **Prompt messages:** Each message is printed as `role: body`, where body is extracted from text, image, or resource content.

### 5.4 Tool argument encoding (CLI)

Arguments to `call-tool` are passed as `--key value` pairs. All values are initially strings. If `--args '{"key":"value"}'` is present, its JSON object is merged in (and the `--args` key itself is removed). Values are decoded as `AnyCodableValue` for MCP transport.

### 5.5 Prompt arguments (CLI)

`get-prompt` accepts `--key value` pairs; all values are strings.

## 6. CLI specification

### 6.1 Global options

| Option | Description |
|--------|-------------|
| `-c, --config <path>` | Config file path |
| `-s, --server <name>` | Server name override |
| `-h, --help` | Print usage and exit 0 |

### 6.2 Commands

| Command | Arguments | Exit code |
|---------|-----------|-----------|
| `list-servers` | none | 0 |
| `ping` | none | 0 on pong |
| `list-tools` | none | 0 |
| `list-resources` | none | 0 |
| `list-prompts` | none | 0 |
| `call-tool` | `<name> [--key value ...]` | 0 on success, **2** on tool error |
| `read-resource` | `<uri>` | 0 |
| `get-prompt` | `<name> [--key value ...]` | 0 |

General errors (config, connection, parse) exit **1**.

### 6.3 Argument parsing

CLI parsing is implemented in **`MCPCLI`** (`Sources/MCPC/MCPCLI.swift`) and unit-tested. The CLI executable delegates to `MCPCLI.parseArguments(_:)` and handles `MCPCLIError.helpRequested` by printing usage.

### 6.4 Connection lifecycle

Each CLI invocation:

1. Loads config
2. Creates transport and connects
3. Runs `initialize`
4. Executes the command
5. Awaits `disconnect()` before exit

`list-servers` does not open an MCP connection.

## 7. GUI specification

### 7.1 Layout

- **Sidebar:** Config file picker, server list with transport endpoint labels, Cursor import, hot-reload toggle
- **Connection bar:** Status indicator, connect/disconnect, ping
- **Tabs:** Tools, Resources, Prompts
- **Output panel:** Monospaced results and error display

### 7.2 Behavior

| Action | Behavior |
|--------|----------|
| Choose config | Reload servers from selected `config.toml` |
| Select server | Highlight server; used on next connect |
| Connect | Disconnect existing session, connect, refresh catalog |
| Disconnect | Tear down session, clear catalog |
| Run Tool | Send JSON arguments from editor; show formatted result |
| Read Resource | Fetch selected URI |
| Run Prompt | Send JSON string-map arguments |
| Import Cursor servers | Parse `mcp.json`, merge into `config.toml` (skip or replace on conflict) |
| Toggle hot reload | Enable/disable `mcp_json_hot_reload`; watch paths and sync on file change |

Argument editors are pre-filled from tool `inputSchema` or prompt argument definitions when an item is selected.

GUI application logic lives in **`MCPClientGUICore`** (`MCPAppModel`, `JSONArgumentsParser`). SwiftUI views in `MCPClientGUI` bind to the model.

### 7.3 Cursor `mcp.json` sync

When `mcp_json_hot_reload` is enabled, `MCPJSONFileWatcher` watches configured paths (default: `~/.cursor/mcp.json` and `.cursor/mcp.json` relative to the config directory). On change, `CursorMCPSync` merges imported servers into `config.toml`:

- Servers previously synced from Cursor but absent from the new JSON are **removed**
- Manually defined servers (not in `mcp_json_synced_servers`) are **preserved**
- If the connected server's config changes, the GUI disconnects and prompts reconnect

Import supports stdio (`command`/`args`/`cwd`/`env`), SSE (`url` with `/sse`), streamable HTTP (`type: streamable-http`), and WebSocket (`ws://`/`wss://`).

### 7.4 Lifecycle

- On scene background or app termination: `shutdown()` disconnects cleanly
- MCP client library warnings during shutdown are suppressed (log level `.error` for `MCPClient` labels)

## 8. Transport specification

### 8.1 stdio (`SubprocessStdioTransport`)

- Spawns subprocess with `Process`, pipes for stdin/stdout/stderr
- Resolves bare command names via `PATH` (`ExecutableResolver`)
- Subprocess environment: minimal inherited vars + `PYTHONUNBUFFERED=1` + server `env` overrides
- **Send:** Appends `\n` to each JSON-RPC message
- **Receive:** Background task reads stdout, splits on newlines, delivers via `LineBuffer` actor
- **stderr:** Drained on background task to prevent pipe deadlock
- **Disconnect:** Close stdin → cancel reader → terminate process → cancel pending receivers

Design constraint: `send` and `receive` must not block each other (prior actor-based design caused deadlock).

### 8.2 sse (`SSETransportAdapter` → `HTTPSSETransport`)

MCPC wraps SwiftMCPClient's `HTTPSSETransport` with `SSETransportAdapter` to support servers (e.g. FastMCP) that acknowledge POST requests with `202 Accepted` and a non-JSON body (`Accepted`) while delivering JSON-RPC responses on SSE `message` events.

Supports headers, connection timeout, reconnect attempts, reconnect backoff, and self-signed certificate trust.

### 8.3 streamable_http (`StreamableHTTPTransport`)

Provided by SwiftMCPClient. Single-endpoint HTTP transport for MCP 2025-03-26.

### 8.4 websocket (`WebSocketTransport`)

Provided by SwiftMCPClient. Supports headers and self-signed certificate trust.

## 9. Error model

### 9.1 `AppConfigError`

| Case | Cause |
|------|-------|
| `fileNotFound` | Config path does not exist |
| `parseFailed` | TOML syntax error |
| `decodeFailed` | Schema mismatch |
| `serverNotFound` | Unknown `--server` name |
| `missingDefaultServer` | No default and no explicit server |
| `invalidServer` | Validation failure per transport |
| `duplicateServerName` | Repeated `[[servers]].name` |

### 9.2 MCP errors

Transport and protocol errors propagate from SwiftMCPClient (`MCPError`). Notable case: `transportClosed` (error 5) during intentional disconnect.

### 9.3 CLI errors

`MCPCLIError`: missing values, unknown options, missing command, invalid JSON for `--args`, help requested.

## 10. Test server specification

The bundled `test-server/` is the **only Python code** in the repository — a [FastMCP](https://github.com/modelcontextprotocol/python-sdk) server used for integration tests. The MCPC client, CLI, and GUI are pure Swift.

| Capability | Name | Details |
|------------|------|---------|
| Tool | `echo` | Returns `message` unchanged |
| Tool | `add` | Sums integers `a` + `b` |
| Tool | `server_info` | JSON capability snapshot |
| Resource | `test://info` | Static JSON metadata |
| Resource | `test://time/{zone}` | Dynamic timestamp |
| Prompt | `greet` | Args: `name`, optional `tone` |

Run via stdio (default):

```bash
uv run --directory test-server python server.py
```

Run via SSE (for `make test-sse`):

```bash
uv run --directory test-server python server.py --transport sse --port 8765
```

## 11. Test suite specification

### 11.1 Swift unit tests (`swift test`)

| Target | Scope |
|--------|-------|
| `MCPCTests` | Config load/validation, `AppConfigWriter` round-trip, `MCPCLI` parsing, `CursorMCPConfigImporter`, `CursorMCPSync`, `SSEJSONMessageFilter` |
| `MCPClientGUITests` | `JSONArgumentsParser`, `MCPAppModel` (config load, Cursor import), live-server integration (connect, catalog, call tool, ping) |

Requires [uv](https://docs.astral.sh/uv/) for GUI integration tests that spawn the bundled test server.

### 11.2 Integration scripts

| Script | Validates |
|--------|-----------|
| `scripts/test_all.sh` | `swift test` + all integration scripts below |
| `scripts/test_swift_client.sh` | CLI over stdio: all MCP commands |
| `scripts/test_cli.sh` | CLI help, custom config, error paths |
| `scripts/test_sse_client.sh` | CLI over SSE: ping, list-tools, call-tool |

### 11.3 Makefile targets

| Target | Action |
|--------|--------|
| `make test` / `make test-all` | Unit tests + CLI + SSE integration |
| `make test-unit` | `swift test` only |
| `make test-cli` | CLI integration scripts |
| `make test-sse` | SSE integration script |

## 12. Packaging specification

### 12.1 App bundle (`make app`)

`scripts/package_app.sh` builds release `mcpc-gui`, assembles `dist/MCPC.app` with `Info.plist`, and ad-hoc codesigns by default.

Environment overrides: `APP_NAME`, `BUNDLE_ID`, `APP_VERSION`, `CODE_SIGN_IDENTITY`, `BUILD_CONFIG`.

### 12.2 DMG (`make dmg`)

`scripts/create_dmg.sh` packages `MCPC.app` into `dist/MCPC-<version>.dmg` with an Applications symlink, `config.toml.example`, and `README.txt`.

Version is read from `[app].version` in `config.toml`.

## 13. Non-functional requirements

| Requirement | Target |
|-------------|--------|
| Concurrency | Swift 6 `Sendable` / actor isolation for session and line buffer |
| Request timeout | Configurable, default 120s |
| macOS version | 14.0 minimum |
| Build | `swift build` produces all library and executable products |
| Tests | `make test` runs 38+ unit tests and integration scripts |

## 14. Future extensions (not implemented)

- SwiftUI / XCUITest GUI automation
- Tool call history and saved argument presets
- MCP notifications / server-initiated messages in the GUI
- Linux GUI or cross-platform packaging
