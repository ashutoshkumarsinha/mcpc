# MCPC

A pure Swift macOS [Model Context Protocol (MCP)](https://modelcontextprotocol.io) client. MCPC connects to MCP servers configured in `config.toml` over stdio, HTTP/SSE, or WebSocket transports. The only Python in this repository is the optional bundled `test-server/` used for integration tests.

It ships as libraries and executables:

| Product | Description |
|---------|-------------|
| **`MCPC`** | Core library: config, transports, session, CLI parsing, Cursor sync |
| **`MCPClientGUICore`** | GUI model and JSON argument helpers (testable without SwiftUI) |
| **`mcpc`** | Command-line client for scripting and automation |
| **`mcpc-gui`** | macOS SwiftUI app (**MCP Client**) for interactive exploration |

## Requirements

- macOS 14+
- Swift 6.0+
- [uv](https://docs.astral.sh/uv/) — only needed to run `make test` (bundled Python test server)

## Quick start

```bash
git clone <repo-url> mcpc && cd mcpc
swift build

# List configured servers
swift run mcpc list-servers

# Talk to the bundled test server (default in config.toml)
swift run mcpc ping
swift run mcpc list-tools
swift run mcpc call-tool echo --message "hello"

# Run all tests: unit tests + CLI + SSE integration (requires uv)
make test

# Launch the GUI
./scripts/run_gui.sh

# Build a distributable DMG (release MCP Client.app + installer image in dist/)
make dmg
```

Run commands from the project root so relative paths in the repo `config.toml` (for example `test-server/`) resolve correctly.

## Configuration

All servers and client settings live in **`config.toml`**. See [docs/USER_GUIDE.md](docs/USER_GUIDE.md) for full configuration examples.

### Development vs production

| Context | Config location | Logs |
|---------|-----------------|------|
| **Repo / CLI dev** | `./config.toml` in the project root (or `MCPC_CONFIG`) | `[logging].destination = "stderr"` (default) |
| **MCP Client GUI (DMG)** | `~/.mcpc/config.toml` — created on first launch | `~/.mcpc/mcpc.log` when `destination = "file"` |
| **CLI without local config** | `~/.mcpc/config.toml` — auto-created if missing | Per `[logging]` in that file |

The GUI always loads `~/.mcpc/config.toml` by default. The CLI resolves: `--config` → `MCPC_CONFIG` → `./config.toml` → `~/.mcpc/config.toml`.

```toml
[app]
name = "mcpc"
version = "1.0.0"

[client]
default_server = "test-server"
protocol_version = "2024-11-05"
request_timeout_seconds = 120

[logging]
level = "info"
destination = "stderr"

[[servers]]
name = "test-server"
transport = "stdio"
command = "uv"
args = ["run", "--directory", "test-server", "python", "server.py"]
env = { PYTHONUNBUFFERED = "1" }
```

For production use, edit `~/.mcpc/config.toml` (or launch **MCP Client** once to create it) and point `[[servers]]` at any stdio, HTTP/SSE, or WebSocket MCP server — see [docs/USER_GUIDE.md](docs/USER_GUIDE.md).

Override the config path with `--config`, set `MCPC_CONFIG`, or use **Choose config.toml…** in the GUI sidebar.

## CLI commands

```
mcpc list-servers
mcpc ping
mcpc list-tools
mcpc list-resources
mcpc list-prompts
mcpc call-tool <name> [--key value ...]
mcpc read-resource <uri>
mcpc get-prompt <name> [--key value ...]
```

Use `-s <name>` to select a server, or rely on `client.default_server`.

## Makefile targets

| Target | Description |
|--------|-------------|
| `make build` | Debug build of all products |
| `make test` | Unit tests + CLI + SSE integration |
| `make test-unit` | `swift test` only |
| `make gui` | Launch `mcpc-gui` |
| `make app` | Build `dist/MCP Client.app` (release) |
| `make dmg` | Build distributable DMG installer |
| `make install` | Install CLI and GUI to `$(PREFIX)/bin` |

## Project layout

```
mcpc/
├── config.toml              # Dev/test configuration (repo root)
├── Package.swift            # Swift package manifest
├── Sources/
│   ├── MCPC/                # Core library (config, ~/.mcpc, transports, session, MCPCLI)
│   ├── MCPClientGUICore/    # GUI model (MCPAppModel)
│   ├── MCPClientCLI/        # mcpc CLI
│   └── MCPClientGUI/        # mcpc-gui SwiftUI views
├── test-server/             # Python FastMCP server for integration tests
├── packaging/               # App bundle templates and DMG extras
├── Tests/
│   ├── MCPCTests/           # Config, CLI parser, Cursor import/sync unit tests
│   └── MCPClientGUITests/   # GUI model + live-server integration tests
├── scripts/
│   ├── test_all.sh
│   ├── test_swift_client.sh
│   ├── test_cli.sh
│   ├── test_sse_client.sh
│   ├── run_gui.sh
│   ├── package_app.sh
│   └── create_dmg.sh
└── docs/
    ├── SPEC.md              # Technical specification
    ├── USER_GUIDE.md        # End-user documentation
    └── HLD.md               # High-level design
```

## Documentation

| Document | Audience | Contents |
|----------|----------|----------|
| [docs/SPEC.md](docs/SPEC.md) | Implementers | Config schema, MCP coverage, tests, packaging, error model |
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | Users | Installation, testing, configuration, CLI/GUI, troubleshooting |
| [docs/HLD.md](docs/HLD.md) | Architects | Component diagram, data flow, transports, test and packaging design |

## Dependencies

- [SwiftMCPClient](https://github.com/jpurnell/SwiftMCPClient) — MCP protocol implementation
- [TOMLKit](https://github.com/LebJe/TOMLKit) — `config.toml` parsing
- [swift-log](https://github.com/apple/swift-log) — logging (GUI)

## License

See repository license file if present.
