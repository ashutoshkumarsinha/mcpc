import Foundation // FileManager, URL, ProcessInfo, Codable
import Logging // Logging types used by loader
import TOMLKit // TOML parsing/decoding library

public struct AppConfig: Sendable { // Top-level configuration loaded from config.toml; `Sendable` for concurrency
    public var app: AppSettings // Application metadata (name, version)
    public var client: ClientSettings // Client behavior settings
    public var logging: LoggingSettings // Logging configuration
    public var servers: [ServerConfig] // Array of MCP server definitions

    public init( // Memberwise initializer
        app: AppSettings,
        client: ClientSettings,
        logging: LoggingSettings = .default, // Default logging when omitted
        servers: [ServerConfig]
    ) {
        self.app = app
        self.client = client
        self.logging = logging
        self.servers = servers
    }

    public func server(named name: String) throws -> ServerConfig { // Look up one server by name or throw
        guard let server = servers.first(where: { $0.name == name }) else { // `guard` fails when not found
            throw AppConfigError.serverNotFound(
                name: name,
                available: servers.map(\.name) // Include available names in error
            )
        }
        return server // Return matching ServerConfig
    }

    public func resolvedServerName(_ explicit: String?) throws -> String { // Choose CLI/GUI server name
        if let explicit, !explicit.isEmpty { // Use explicit name when provided
            return explicit
        }
        guard !client.defaultServer.isEmpty else { // Otherwise require default_server in config
            throw AppConfigError.missingDefaultServer
        }
        return client.defaultServer // Fall back to configured default
    }
}

public struct AppSettings: Codable, Sendable { // `[app]` table in TOML
    public var name: String // Client name sent during MCP initialize
    public var version: String // Client version sent during MCP initialize

    public init(name: String = "mcpc", version: String = "1.0.0") { // Defaults for new configs
        self.name = name
        self.version = version
    }
}

public struct ClientSettings: Sendable { // `[client]` table in TOML
    public var defaultServer: String // Name of default [[servers]] entry
    public var protocolVersion: String // MCP protocol version string
    public var requestTimeoutSeconds: Int // Per-request timeout in seconds
    public var logServerStderr: Bool // Forward stdio server stderr to our stderr
    public var mcpJSONHotReload: Bool // Watch Cursor mcp.json and auto-sync
    public var mcpJSONWatchPaths: [String] // Optional override paths to watch
    public var mcpJSONSyncedServers: [String] // Server names managed by JSON sync

    public init( // Defaults for programmatic construction
        defaultServer: String = "",
        protocolVersion: String = "2024-11-05",
        requestTimeoutSeconds: Int = 120,
        logServerStderr: Bool = false,
        mcpJSONHotReload: Bool = false,
        mcpJSONWatchPaths: [String] = [],
        mcpJSONSyncedServers: [String] = []
    ) {
        self.defaultServer = defaultServer
        self.protocolVersion = protocolVersion
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.logServerStderr = logServerStderr
        self.mcpJSONHotReload = mcpJSONHotReload
        self.mcpJSONWatchPaths = mcpJSONWatchPaths
        self.mcpJSONSyncedServers = mcpJSONSyncedServers
    }
}

extension ClientSettings: Decodable { // Custom decode maps snake_case TOML keys to camelCase properties
    enum CodingKeys: String, CodingKey { // `CodingKey` enum lists JSON/TOML field names
        case defaultServer = "default_server" // Map TOML key to property
        case protocolVersion = "protocol_version"
        case requestTimeoutSeconds = "request_timeout_seconds"
        case logServerStderr = "log_server_stderr"
        case mcpJSONHotReload = "mcp_json_hot_reload"
        case mcpJSONWatchPaths = "mcp_json_watch_paths"
        case mcpJSONSyncedServers = "mcp_json_synced_servers"
    }

    public init(from decoder: Decoder) throws { // `throws` when required values are invalid
        let container = try decoder.container(keyedBy: CodingKeys.self) // Keyed decoding container
        defaultServer = try container.decodeIfPresent(String.self, forKey: .defaultServer) ?? "" // Optional with default ""
        protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion) ?? "2024-11-05"
        requestTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .requestTimeoutSeconds) ?? 120
        logServerStderr = try container.decodeIfPresent(Bool.self, forKey: .logServerStderr) ?? false
        mcpJSONHotReload = try container.decodeIfPresent(Bool.self, forKey: .mcpJSONHotReload) ?? false
        mcpJSONWatchPaths = try container.decodeIfPresent([String].self, forKey: .mcpJSONWatchPaths) ?? []
        mcpJSONSyncedServers = try container.decodeIfPresent([String].self, forKey: .mcpJSONSyncedServers) ?? []
    }
}

public enum ServerTransport: Sendable, Equatable { // Transport kind for a server entry
    case stdio // Local subprocess
    /// MCP HTTP with Server-Sent Events (2024-11-05): GET `/sse` stream + POST message endpoint.
    case sse
    /// MCP Streamable HTTP (2025-03-26): single `/mcp` endpoint with optional SSE streaming.
    case streamableHTTP
    case websocket // WebSocket transport

    public var configKey: String { // String written to/read from config.toml `transport` field
        switch self {
        case .stdio: "stdio"
        case .sse: "sse"
        case .streamableHTTP: "streamable_http"
        case .websocket: "websocket"
        }
    }

    public static func parse(_ raw: String) -> ServerTransport? { // Parse config/import string to enum; nil if unknown
        switch raw.lowercased() { // Case-insensitive matching
        case "stdio":
            return .stdio
        case "sse", "http_sse":
            return .sse
        case "streamable_http", "streamable-http":
            return .streamableHTTP
        case "websocket", "ws":
            return .websocket
        default:
            return nil
        }
    }
}

extension ServerTransport: Codable { // Encode/decode as single string value
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer() // Transport is a scalar string in TOML
        let raw = try container.decode(String.self) // Read raw transport string
        guard let transport = ServerTransport.parse(raw) else { // `guard` throws on unknown value
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown transport '\(raw)'"
            )
        }
        self = transport // Assign parsed enum case
    }

    public func encode(to encoder: Encoder) throws { // Write transport back as config key string
        var container = encoder.singleValueContainer()
        try container.encode(configKey)
    }
}

public struct ServerConfig: Sendable { // One `[[servers]]` table worth of settings
    public var name: String // Unique server name
    public var transport: ServerTransport // How to connect (stdio/sse/etc.)
    public var command: String? // stdio executable path
    public var args: [String] // stdio CLI arguments
    public var env: [String: String] // stdio environment overrides
    public var workingDirectory: String? // stdio working directory
    public var url: String? // Remote transport URL
    public var headers: [String: String] // HTTP/WebSocket headers
    public var trustSelfSignedCertificates: Bool // TLS setting for remote transports
    public var connectionTimeoutSeconds: Int // Connect timeout for network transports
    public var maxReconnectAttempts: Int // SSE reconnect attempts
    public var reconnectBaseDelaySeconds: Double // SSE reconnect backoff base

    public init( // Programmatic initializer with defaults
        name: String,
        transport: ServerTransport,
        command: String? = nil,
        args: [String] = [],
        env: [String: String] = [:],
        workingDirectory: String? = nil,
        url: String? = nil,
        headers: [String: String] = [:],
        trustSelfSignedCertificates: Bool = false,
        connectionTimeoutSeconds: Int = 30,
        maxReconnectAttempts: Int = 3,
        reconnectBaseDelaySeconds: Double = 1.0
    ) {
        self.name = name
        self.transport = transport
        self.command = command
        self.args = args
        self.env = env
        self.workingDirectory = workingDirectory
        self.url = url
        self.headers = headers
        self.trustSelfSignedCertificates = trustSelfSignedCertificates
        self.connectionTimeoutSeconds = connectionTimeoutSeconds
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectBaseDelaySeconds = reconnectBaseDelaySeconds
    }
}

extension ServerConfig: Decodable { // Decode one server table from TOML
    enum CodingKeys: String, CodingKey {
        case name
        case transport
        case command
        case args
        case env
        case workingDirectory = "working_directory"
        case url
        case headers
        case trustSelfSignedCertificates = "trust_self_signed_certificates"
        case connectionTimeoutSeconds = "connection_timeout_seconds"
        case maxReconnectAttempts = "max_reconnect_attempts"
        case reconnectBaseDelaySeconds = "reconnect_base_delay_seconds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name) // Required name
        transport = try container.decode(ServerTransport.self, forKey: .transport) // Required transport
        command = try container.decodeIfPresent(String.self, forKey: .command) // Optional stdio command
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        trustSelfSignedCertificates = try container.decodeIfPresent(
            Bool.self,
            forKey: .trustSelfSignedCertificates
        ) ?? false
        connectionTimeoutSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .connectionTimeoutSeconds
        ) ?? 30
        maxReconnectAttempts = try container.decodeIfPresent(
            Int.self,
            forKey: .maxReconnectAttempts
        ) ?? 3
        reconnectBaseDelaySeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .reconnectBaseDelaySeconds
        ) ?? 1.0
    }
}

extension ServerConfig: Equatable { // Value equality for change detection during JSON sync
    public static func == (lhs: ServerConfig, rhs: ServerConfig) -> Bool { // Compare all stored fields
        lhs.name == rhs.name
            && lhs.transport == rhs.transport
            && lhs.command == rhs.command
            && lhs.args == rhs.args
            && lhs.env == rhs.env
            && lhs.workingDirectory == rhs.workingDirectory
            && lhs.url == rhs.url
            && lhs.headers == rhs.headers
            && lhs.trustSelfSignedCertificates == rhs.trustSelfSignedCertificates
            && lhs.connectionTimeoutSeconds == rhs.connectionTimeoutSeconds
            && lhs.maxReconnectAttempts == rhs.maxReconnectAttempts
            && lhs.reconnectBaseDelaySeconds == rhs.reconnectBaseDelaySeconds
    }
}

extension ServerConfig {

    public func validate() throws { // Ensure transport-specific required fields are present
        switch transport {
        case .stdio:
            guard let command, !command.isEmpty else { // stdio needs non-empty command
                throw AppConfigError.invalidServer(
                    name: name,
                    reason: "stdio transport requires 'command'"
                )
            }
        case .sse, .streamableHTTP, .websocket:
            guard let url, !url.isEmpty else { // Remote transports need URL string
                throw AppConfigError.invalidServer(
                    name: name,
                    reason: "\(transport.configKey) transport requires 'url'"
                )
            }
            guard URL(string: url) != nil else { // URL must parse as Foundation URL
                throw AppConfigError.invalidServer(
                    name: name,
                    reason: "invalid url: \(url)"
                )
            }
        }
    }
}

private struct AppConfigDTO: Decodable { // Intermediate decode shape matching TOML top-level tables
    var app: AppSettings
    var client: ClientSettings
    var logging: LoggingSettings? // Optional in file; merged with defaults
    var servers: [ServerConfig]

    enum CodingKeys: String, CodingKey {
        case app
        case client
        case logging
        case servers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decode(AppSettings.self, forKey: .app)
        client = try container.decode(ClientSettings.self, forKey: .client)
        logging = try container.decodeIfPresent(LoggingSettings.self, forKey: .logging)
        servers = try container.decodeIfPresent([ServerConfig].self, forKey: .servers) ?? []
    }
}

public enum AppConfigError: Error, CustomStringConvertible { // Typed config load/write/validation errors
    case fileNotFound(URL)
    case parseFailed(String)
    case decodeFailed(String)
    case serverNotFound(name: String, available: [String])
    case missingDefaultServer
    case invalidServer(name: String, reason: String)
    case duplicateServerName(String)
    case writeFailed(URL, String)

    public var description: String { // String representation for logging/UI
        switch self {
        case .fileNotFound(let url):
            return "Config not found at \(url.path)"
        case .parseFailed(let reason):
            return "Failed to parse config.toml: \(reason)"
        case .decodeFailed(let reason):
            return "Failed to decode config.toml: \(reason)"
        case .serverNotFound(let name, let available):
            let names = available.sorted().joined(separator: ", ")
            return "Server '\(name)' not found. Configured servers: \(names)"
        case .missingDefaultServer:
            return "No server specified and client.default_server is empty"
        case .invalidServer(let name, let reason):
            return "Invalid server '\(name)': \(reason)"
        case .duplicateServerName(let name):
            return "Duplicate server name in config: \(name)"
        case .writeFailed(let url, let reason):
            return "Failed to write config to \(url.path): \(reason)"
        }
    }
}

public enum AppConfigLoader { // Load config.toml from disk
    public static let defaultFileName = "config.toml" // Default filename in cwd/user dir
    private static let log = MCPCLogging.logger("config") // Logger for config loading

    public static func load(from url: URL) throws -> AppConfig { // Parse + validate config file
        guard FileManager.default.fileExists(atPath: url.path) else { // File must exist
            throw AppConfigError.fileNotFound(url)
        }

        let contents: String // Raw TOML text
        do {
            contents = try String(contentsOf: url, encoding: .utf8) // Read UTF-8 file contents
        } catch {
            throw AppConfigError.parseFailed(error.localizedDescription)
        }

        let table: TOMLTable // Parsed TOML root table
        do {
            table = try TOMLTable(string: contents) // Parse TOML syntax
        } catch {
            throw AppConfigError.parseFailed(error.localizedDescription)
        }

        let dto: AppConfigDTO // Decode into DTO struct
        do {
            dto = try TOMLDecoder().decode(AppConfigDTO.self, from: table) // Map TOML -> Swift types
        } catch {
            throw AppConfigError.decodeFailed(error.localizedDescription)
        }

        var seen = Set<String>() // Track duplicate server names
        for server in dto.servers { // Validate each server entry
            if seen.contains(server.name) {
                throw AppConfigError.duplicateServerName(server.name)
            }
            seen.insert(server.name)
            try server.validate() // Transport-specific validation
        }

        let logging = Self.mergedLogging(dto.logging) // Merge optional logging section with defaults
        let config = AppConfig(app: dto.app, client: dto.client, logging: logging, servers: dto.servers) // Build public AppConfig
        log.info( // Log successful load summary
            "Loaded config",
            metadata: [
                "path": .string(url.path),
                "servers": .stringConvertible(config.servers.count),
                "default_server": .string(config.client.defaultServer),
                "log_level": .string(logging.level.rawValue),
            ]
        )
        return config
    }

    private static func mergedLogging(_ settings: LoggingSettings?) -> LoggingSettings { // Overlay file logging onto defaults
        var merged = LoggingSettings.default // Start from defaults
        guard let settings else { return merged } // No [logging] table => defaults only
        merged.level = settings.level
        merged.destination = settings.destination
        merged.logFile = settings.logFile
        for (key, value) in settings.components { // Merge per-component overrides
            merged.components[key] = value
        }
        return merged
    }

    public static func defaultConfigURL( // Resolve which config.toml path to use
        explicitPath: String? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        if let explicitPath, !explicitPath.isEmpty { // CLI --config wins
            return URL(fileURLWithPath: explicitPath).standardizedFileURL
        }
        if let envPath = ProcessInfo.processInfo.environment["MCPC_CONFIG"], !envPath.isEmpty { // Env var override
            return URL(fileURLWithPath: envPath).standardizedFileURL
        }
        let cwdConfig = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(defaultFileName) // ./config.toml in current working directory
        if fileManager.fileExists(atPath: cwdConfig.path) {
            return cwdConfig.standardizedFileURL
        }
        let userConfig = MCPCUserDirectory.configURL(fileManager: fileManager) // Application Support config path
        if fileManager.fileExists(atPath: userConfig.path) {
            return userConfig
        }
        _ = try? MCPCUserDirectory.prepareForFirstLaunch(fileManager: fileManager) // Best-effort first-launch setup
        return userConfig // Return user config path even if we had to create scaffolding
    }
}
