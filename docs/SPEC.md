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
- Transports: **stdio**, **http_sse**, **websocket**
- MCP operations: `initialize`, `ping`, `tools/list`, `tools/call`, `resources/list`, `resources/read`, `prompts/list`, `prompts/get`
- TOML-based multi-server configuration
- CLI with structured exit codes
- macOS GUI for interactive server exploration
- Custom stdio subprocess transport with deadlock-safe I/O

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
| `transport` | enum | yes | `stdio`, `http_sse`, or `websocket` |
| `command` | string | stdio | Executable to spawn |
| `args` | string array | no | Command-line arguments |
| `env` | string map | no | Extra environment variables for subprocess |
| `url` | string | http_sse, websocket | Endpoint URL |
| `headers` | string map | no | HTTP headers for remote transports |
| `trust_self_signed_certificates` | boolean | no | TLS trust override (default `false`) |
| `connection_timeout_seconds` | integer | no | Connect timeout for HTTP/SSE (default `30`) |
| `max_reconnect_attempts` | integer | no | SSE reconnect attempts (default `3`) |

Server names must be unique. Each server entry is validated at load time.

#### Transport validation rules

- **stdio:** `command` must be non-empty
- **http_sse / websocket:** `url` must be non-empty and parseable as a URL

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

### 4.5 Example: HTTP/SSE server

```toml
[[servers]]
name = "remote-sse"
transport = "http_sse"
url = "http://127.0.0.1:8080/sse"
trust_self_signed_certificates = false

[servers.remote-sse.headers]
Authorization = "Bearer <token>"
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

### 6.3 Connection lifecycle

Each CLI invocation:

1. Loads config
2. Creates transport and connects
3. Runs `initialize`
4. Executes the command
5. Disconnects on exit (`defer` block)

`list-servers` does not open an MCP connection.

## 7. GUI specification

### 7.1 Layout

- **Sidebar:** Config file picker, server list with transport endpoint labels
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

Argument editors are pre-filled from tool `inputSchema` or prompt argument definitions when an item is selected.

### 7.3 Lifecycle

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

### 8.2 http_sse (`HTTPSSETransport`)

Provided by SwiftMCPClient. Supports headers, connection timeout, reconnect attempts, and self-signed certificate trust.

### 8.3 websocket (`WebSocketTransport`)

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

`CLIError`: missing values, unknown options, missing command, invalid JSON for `--args`.

## 10. Test server specification

The bundled `test-server/` is the **only Python code** in the repository — a [FastMCP](https://github.com/modelcontextprotocol/python-sdk) stdio server used for integration tests. The MCPC client, CLI, and GUI are pure Swift.

| Capability | Name | Details |
|------------|------|---------|
| Tool | `echo` | Returns `message` unchanged |
| Tool | `add` | Sums integers `a` + `b` |
| Tool | `server_info` | JSON capability snapshot |
| Resource | `test://info` | Static JSON metadata |
| Resource | `test://time/{zone}` | Dynamic timestamp |
| Prompt | `greet` | Args: `name`, optional `tone` |

Run via: `uv run --directory test-server python server.py`

Integration script `scripts/test_swift_client.sh` validates all CLI operations against this server.

## 11. Non-functional requirements

| Requirement | Target |
|-------------|--------|
| Concurrency | Swift 6 `Sendable` / actor isolation for session and line buffer |
| Request timeout | Configurable, default 120s |
| macOS version | 14.0 minimum |
| Build | `swift build` produces all three products |

## 12. Future extensions (not implemented)

- Config hot-reload without reconnect
- Tool call history and saved argument presets
- MCP notifications / server-initiated messages
- Linux GUI or cross-platform packaging
