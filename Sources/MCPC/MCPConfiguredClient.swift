import Foundation
import MCPClient

/// High-level MCP client that launches a configured stdio server subprocess.
public actor MCPConfiguredClient {
    public let serverName: String
    public let definition: MCPServerDefinition
    public private(set) var serverInfo: InitializeResult?

    private let connection: MCPClientConnection

    public init(
        serverName: String,
        definition: MCPServerDefinition,
        clientName: String = "mcpc",
        clientVersion: String = "1.0.0"
    ) async throws {
        self.serverName = serverName
        self.definition = definition

        var environment = ProcessInfo.processInfo.environment
        if let overrides = definition.env {
            for (key, value) in overrides {
                environment[key] = value
            }
        }

        let transport = SubprocessStdioTransport(
            command: ExecutableResolver.resolve(definition.command, environment: environment),
            arguments: definition.args,
            environment: environment
        )
        let connection = MCPClientConnection(transport: transport)
        self.connection = connection
        self.serverInfo = try await connection.initialize(
            clientName: clientName,
            clientVersion: clientVersion
        )
    }

    public static func connect(
        configURL: URL,
        serverName: String,
        clientName: String = "mcpc",
        clientVersion: String = "1.0.0"
    ) async throws -> MCPConfiguredClient {
        let config = try MCPServerConfigLoader.load(from: configURL)
        let definition = try MCPServerConfigLoader.definition(named: serverName, in: config)
        return try await MCPConfiguredClient(
            serverName: serverName,
            definition: definition,
            clientName: clientName,
            clientVersion: clientVersion
        )
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

    public func listPrompts() async throws -> [MCPPrompt] {
        try await connection.listPrompts()
    }

    public func disconnect() async throws {
        try await connection.disconnect()
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
