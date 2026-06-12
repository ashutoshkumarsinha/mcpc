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

    public init(
        defaultServer: String = "",
        protocolVersion: String = "2024-11-05",
        requestTimeoutSeconds: Int = 120,
        logServerStderr: Bool = false
    ) {
        self.defaultServer = defaultServer
        self.protocolVersion = protocolVersion
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.logServerStderr = logServerStderr
    }
}

extension ClientSettings: Decodable {
    enum CodingKeys: String, CodingKey {
        case defaultServer = "default_server"
        case protocolVersion = "protocol_version"
        case requestTimeoutSeconds = "request_timeout_seconds"
        case logServerStderr = "log_server_stderr"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultServer = try container.decodeIfPresent(String.self, forKey: .defaultServer) ?? ""
        protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion) ?? "2024-11-05"
        requestTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .requestTimeoutSeconds) ?? 120
        logServerStderr = try container.decodeIfPresent(Bool.self, forKey: .logServerStderr) ?? false
    }
}

public enum ServerTransport: String, Codable, Sendable {
    case stdio
    case httpSSE = "http_sse"
    case websocket
}

public struct ServerConfig: Sendable {
    public var name: String
    public var transport: ServerTransport
    public var command: String?
    public var args: [String]
    public var env: [String: String]
    public var url: String?
    public var headers: [String: String]
    public var trustSelfSignedCertificates: Bool
    public var connectionTimeoutSeconds: Int
    public var maxReconnectAttempts: Int

    public init(
        name: String,
        transport: ServerTransport,
        command: String? = nil,
        args: [String] = [],
        env: [String: String] = [:],
        url: String? = nil,
        headers: [String: String] = [:],
        trustSelfSignedCertificates: Bool = false,
        connectionTimeoutSeconds: Int = 30,
        maxReconnectAttempts: Int = 3
    ) {
        self.name = name
        self.transport = transport
        self.command = command
        self.args = args
        self.env = env
        self.url = url
        self.headers = headers
        self.trustSelfSignedCertificates = trustSelfSignedCertificates
        self.connectionTimeoutSeconds = connectionTimeoutSeconds
        self.maxReconnectAttempts = maxReconnectAttempts
    }
}

extension ServerConfig: Decodable {
    enum CodingKeys: String, CodingKey {
        case name
        case transport
        case command
        case args
        case env
        case url
        case headers
        case trustSelfSignedCertificates = "trust_self_signed_certificates"
        case connectionTimeoutSeconds = "connection_timeout_seconds"
        case maxReconnectAttempts = "max_reconnect_attempts"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        transport = try container.decode(ServerTransport.self, forKey: .transport)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
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
        case .httpSSE, .websocket:
            guard let url, !url.isEmpty else {
                throw AppConfigError.invalidServer(
                    name: name,
                    reason: "\(transport.rawValue) transport requires 'url'"
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
