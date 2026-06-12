import Foundation
import Logging
import MCPClient

/// Generic MCP client session for any configured server.
public actor MCPClientSession {
    public let config: AppConfig
    public let server: ServerConfig
    public private(set) var serverInfo: InitializeResult?

    private let connection: MCPClientConnection
    private let log = MCPCLogging.logger("session")

    public init(config: AppConfig, serverName: String) async throws {
        self.config = config
        self.server = try config.server(named: serverName)

        let transport = try TransportFactory.makeTransport(
            for: self.server,
            client: config.client
        )
        let timeout = Duration.seconds(config.client.requestTimeoutSeconds)
        let connection = MCPClientConnection(transport: transport, requestTimeout: timeout)
        self.connection = connection
        self.serverInfo = try await connection.initialize(
            clientName: config.app.name,
            clientVersion: config.app.version,
            protocolVersion: config.client.protocolVersion
        )
        if let info = self.serverInfo {
            log.info(
                "Connected",
                metadata: [
                    "server": .string(server.name),
                    "transport": .string(server.transport.rawValue),
                    "remote_name": .string(info.serverInfo.name),
                    "remote_version": .string(info.serverInfo.version),
                ]
            )
        }
    }

    public static func connect(
        configURL: URL,
        serverName: String? = nil
    ) async throws -> MCPClientSession {
        let config = try AppConfigLoader.load(from: configURL)
        let resolvedName = try config.resolvedServerName(serverName)
        return try await MCPClientSession(config: config, serverName: resolvedName)
    }

    public func listTools() async throws -> [MCPTool] {
        try await connection.listTools()
    }

    public func callTool(
        name: String,
        arguments: [String: AnyCodableValue]
    ) async throws -> MCPToolResult {
        try await connection.callTool(name: name, arguments: arguments)
    }

    public func listResources() async throws -> [MCPResource] {
        try await connection.listResources()
    }

    public func readResource(uri: String) async throws -> [MCPResourceContents] {
        try await connection.readResource(uri: uri)
    }

    public func listPrompts() async throws -> [MCPPrompt] {
        try await connection.listPrompts()
    }

    public func getPrompt(
        name: String,
        arguments: [String: String] = [:]
    ) async throws -> MCPPromptResult {
        try await connection.getPrompt(name: name, arguments: arguments)
    }

    public func ping() async throws -> Bool {
        try await connection.ping()
    }

    public func disconnect() async throws {
        log.info("Disconnecting", metadata: ["server": .string(server.name)])
        try await connection.disconnect()
        log.debug("Disconnected", metadata: ["server": .string(server.name)])
    }
}

public enum MCPToolContentFormatter {
    public static func text(from result: MCPToolResult) -> String {
        result.content.compactMap { item in
            switch item {
            case .text(let text, _):
                return text
            case .image(_, let mimeType, _):
                return "[image: \(mimeType)]"
            case .resource(let contents, _):
                switch contents {
                case .text(let uri, let mimeType, let text):
                    return "[resource \(uri) (\(mimeType ?? "unknown"))]\n\(text)"
                case .blob(let uri, let mimeType, _):
                    return "[resource blob \(uri) (\(mimeType ?? "unknown"))]"
                }
            }
        }
        .joined(separator: "\n")
    }
}

public enum MCPResourceContentFormatter {
    public static func text(from contents: [MCPResourceContents]) -> String {
        contents.map { item in
            switch item {
            case .text(let uri, let mimeType, let text):
                return "[\(uri) (\(mimeType ?? "text/plain"))]\n\(text)"
            case .blob(let uri, let mimeType, _):
                return "[\(uri) blob (\(mimeType ?? "application/octet-stream"))]"
            }
        }
        .joined(separator: "\n\n")
    }
}
