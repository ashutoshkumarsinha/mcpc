import Foundation
import Logging
import TOMLKit

public struct AppConfig: Sendable {
    public var app: AppSettings
    public var client: ClientSettings
    public var logging: LoggingSettings
    public var servers: [ServerConfig]

    public init(
        app: AppSettings,
        client: ClientSettings,
        logging: LoggingSettings = .default,
        servers: [ServerConfig]
    ) {
        self.app = app
        self.client = client
        self.logging = logging
        self.servers = servers
    }

    public func server(named name: String) throws -> ServerConfig {
        guard let server = servers.first(where: { $0.name == name }) else {
            throw AppConfigError.serverNotFound(
                name: name,
                available: servers.map(\.name)
            )
        }
        return server
    }

    public func resolvedServerName(_ explicit: String?) throws -> String {
        if let explicit, !explicit.isEmpty {
            return explicit
        }
        guard !client.defaultServer.isEmpty else {
            throw AppConfigError.missingDefaultServer
        }
        return client.defaultServer
    }
}

public struct AppSettings: Codable, Sendable {
    public var name: String
    public var version: String

    public init(name: String = "mcpc", version: String = "1.0.0") {
        self.name = name
        self.version = version
    }
}

public struct ClientSettings: Sendable {
    public var defaultServer: String
    public var protocolVersion: String
    public var requestTimeoutSeconds: Int
    public var logServerStderr: Bool
    public var mcpJSONHotReload: Bool
    public var mcpJSONWatchPaths: [String]
    public var mcpJSONSyncedServers: [String]

    public init(
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

extension ClientSettings: Decodable {
    enum CodingKeys: String, CodingKey {
        case defaultServer = "default_server"
        case protocolVersion = "protocol_version"
        case requestTimeoutSeconds = "request_timeout_seconds"
        case logServerStderr = "log_server_stderr"
        case mcpJSONHotReload = "mcp_json_hot_reload"
        case mcpJSONWatchPaths = "mcp_json_watch_paths"
        case mcpJSONSyncedServers = "mcp_json_synced_servers"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultServer = try container.decodeIfPresent(String.self, forKey: .defaultServer) ?? ""
        protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion) ?? "2024-11-05"
        requestTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .requestTimeoutSeconds) ?? 120
        logServerStderr = try container.decodeIfPresent(Bool.self, forKey: .logServerStderr) ?? false
        mcpJSONHotReload = try container.decodeIfPresent(Bool.self, forKey: .mcpJSONHotReload) ?? false
        mcpJSONWatchPaths = try container.decodeIfPresent([String].self, forKey: .mcpJSONWatchPaths) ?? []
        mcpJSONSyncedServers = try container.decodeIfPresent([String].self, forKey: .mcpJSONSyncedServers) ?? []
    }
}

public enum ServerTransport: Sendable, Equatable {
    case stdio
    /// MCP HTTP with Server-Sent Events (2024-11-05): GET `/sse` stream + POST message endpoint.
    case sse
    /// MCP Streamable HTTP (2025-03-26): single `/mcp` endpoint with optional SSE streaming.
    case streamableHTTP
    case websocket

    public var configKey: String {
        switch self {
        case .stdio: "stdio"
        case .sse: "sse"
        case .streamableHTTP: "streamable_http"
        case .websocket: "websocket"
        }
    }

    public static func parse(_ raw: String) -> ServerTransport? {
        switch raw.lowercased() {
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

extension ServerTransport: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let transport = ServerTransport.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown transport '\(raw)'"
            )
        }
        self = transport
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(configKey)
    }
}

public struct ServerConfig: Sendable {
    public var name: String
    public var transport: ServerTransport
    public var command: String?
    public var args: [String]
    public var env: [String: String]
    public var workingDirectory: String?
    public var url: String?
    public var headers: [String: String]
    public var trustSelfSignedCertificates: Bool
    public var connectionTimeoutSeconds: Int
    public var maxReconnectAttempts: Int
    public var reconnectBaseDelaySeconds: Double

    public init(
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

extension ServerConfig: Decodable {
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
        name = try container.decode(String.self, forKey: .name)
        transport = try container.decode(ServerTransport.self, forKey: .transport)
        command = try container.decodeIfPresent(String.self, forKey: .command)
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

extension ServerConfig: Equatable {
    public static func == (lhs: ServerConfig, rhs: ServerConfig) -> Bool {
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

    public func validate() throws {
        switch transport {
        case .stdio:
            guard let command, !command.isEmpty else {
                throw AppConfigError.invalidServer(
                    name: name,
                    reason: "stdio transport requires 'command'"
                )
            }
        case .sse, .streamableHTTP, .websocket:
            guard let url, !url.isEmpty else {
                throw AppConfigError.invalidServer(
                    name: name,
                    reason: "\(transport.configKey) transport requires 'url'"
                )
            }
            guard URL(string: url) != nil else {
                throw AppConfigError.invalidServer(
                    name: name,
                    reason: "invalid url: \(url)"
                )
            }
        }
    }
}

private struct AppConfigDTO: Decodable {
    var app: AppSettings
    var client: ClientSettings
    var logging: LoggingSettings?
    var servers: [ServerConfig]
}

public enum AppConfigError: Error, CustomStringConvertible {
    case fileNotFound(URL)
    case parseFailed(String)
    case decodeFailed(String)
    case serverNotFound(name: String, available: [String])
    case missingDefaultServer
    case invalidServer(name: String, reason: String)
    case duplicateServerName(String)
    case writeFailed(URL, String)

    public var description: String {
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

public enum AppConfigLoader {
    public static let defaultFileName = "config.toml"
    private static let log = MCPCLogging.logger("config")

    public static func load(from url: URL) throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppConfigError.fileNotFound(url)
        }

        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AppConfigError.parseFailed(error.localizedDescription)
        }

        let table: TOMLTable
        do {
            table = try TOMLTable(string: contents)
        } catch {
            throw AppConfigError.parseFailed(error.localizedDescription)
        }

        let dto: AppConfigDTO
        do {
            dto = try TOMLDecoder().decode(AppConfigDTO.self, from: table)
        } catch {
            throw AppConfigError.decodeFailed(error.localizedDescription)
        }

        var seen = Set<String>()
        for server in dto.servers {
            if seen.contains(server.name) {
                throw AppConfigError.duplicateServerName(server.name)
            }
            seen.insert(server.name)
            try server.validate()
        }

        let logging = Self.mergedLogging(dto.logging)
        let config = AppConfig(app: dto.app, client: dto.client, logging: logging, servers: dto.servers)
        log.info(
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

    private static func mergedLogging(_ settings: LoggingSettings?) -> LoggingSettings {
        var merged = LoggingSettings.default
        guard let settings else { return merged }
        merged.level = settings.level
        merged.destination = settings.destination
        for (key, value) in settings.components {
            merged.components[key] = value
        }
        return merged
    }

    public static func defaultConfigURL(
        explicitPath: String? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        if let explicitPath, !explicitPath.isEmpty {
            return URL(fileURLWithPath: explicitPath).standardizedFileURL
        }
        if let envPath = ProcessInfo.processInfo.environment["MCPC_CONFIG"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath).standardizedFileURL
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(defaultFileName)
            .standardizedFileURL
    }
}
