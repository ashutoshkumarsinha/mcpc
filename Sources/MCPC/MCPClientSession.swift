import Foundation // Core Swift/Foundation types
import Logging // Structured logging
import MCPClient // MCP protocol client types

/// Generic MCP client session for any configured server.
public actor MCPClientSession { // `actor` serializes access; one session per connected server
    public let config: AppConfig // Full loaded application configuration
    public let server: ServerConfig // The specific server this session targets
    public private(set) var serverInfo: InitializeResult? // MCP initialize result; `private(set)` = public read, internal write

    private let connection: MCPClientConnection // Underlying JSON-RPC connection over a transport
    private let log = MCPCLogging.logger("session") // Logger for session lifecycle events

    public init(config: AppConfig, serverName: String) async throws { // Connect + initialize in one step
        self.config = config // Store config snapshot
        self.server = try config.server(named: serverName) // `try` resolves named server or throws

        let transport = try TransportFactory.makeTransport( // Build transport from server settings
            for: self.server,
            client: config.client
        )
        let timeout = Duration.seconds(config.client.requestTimeoutSeconds) // Request timeout as Swift Duration
        let connection = MCPClientConnection(transport: transport, requestTimeout: timeout) // Wrap transport in connection
        self.connection = connection // Save connection for later RPC calls

        do { // Initialize handshake may fail
            self.serverInfo = try await connection.initialize( // `async` MCP initialize RPC
                clientName: config.app.name,
                clientVersion: config.app.version,
                protocolVersion: config.client.protocolVersion
            )
        } catch { // On failure, clean up partially opened connection
            try? await connection.disconnect() // `try?` ignores disconnect errors
            throw error // Re-throw the original initialize error
        }

        if let info = self.serverInfo { // Log successful connection details when available
            log.info(
                "Connected",
                metadata: [
                    "server": .string(server.name),
                    "transport": .string(server.transport.configKey),
                    "remote_name": .string(info.serverInfo.name),
                    "remote_version": .string(info.serverInfo.version),
                ]
            )
        }
    }

    public static func connect( // Convenience factory: load config file then connect
        configURL: URL,
        serverName: String? = nil // Optional override; nil uses default_server
    ) async throws -> MCPClientSession {
        let config = try AppConfigLoader.load(from: configURL) // Parse config.toml
        let resolvedName = try config.resolvedServerName(serverName) // Pick explicit or default server name
        return try await MCPClientSession(config: config, serverName: resolvedName) // Create initialized session
    }

    public func listTools() async throws -> [MCPTool] { // MCP tools/list RPC
        try await connection.listTools() // Delegate to connection; `try await` propagates errors
    }

    public func callTool( // MCP tools/call RPC
        name: String,
        arguments: [String: AnyCodableValue]
    ) async throws -> MCPToolResult {
        try await connection.callTool(name: name, arguments: arguments) // Invoke named tool with JSON args
    }

    public func listResources() async throws -> [MCPResource] { // MCP resources/list RPC
        try await connection.listResources()
    }

    public func readResource(uri: String) async throws -> [MCPResourceContents] { // MCP resources/read RPC
        try await connection.readResource(uri: uri)
    }

    public func listPrompts() async throws -> [MCPPrompt] { // MCP prompts/list RPC
        try await connection.listPrompts()
    }

    public func getPrompt( // MCP prompts/get RPC
        name: String,
        arguments: [String: String] = [:] // Prompt arguments default to empty map
    ) async throws -> MCPPromptResult {
        try await connection.getPrompt(name: name, arguments: arguments)
    }

    public func ping() async throws -> Bool { // MCP ping/health check
        try await connection.ping()
    }

    public func disconnect() async throws { // Gracefully close transport
        log.info("Disconnecting", metadata: ["server": .string(server.name)]) // Log disconnect start
        try await connection.disconnect() // Close underlying connection
        log.debug("Disconnected", metadata: ["server": .string(server.name)]) // Log disconnect complete
    }
}

public enum MCPToolContentFormatter { // Helpers to turn tool results into display text
    public static func text(from result: MCPToolResult) -> String { // Flatten tool result content items
        result.content.compactMap { item in // `compactMap` drops nils from the mapping
            switch item { // Pattern-match each content union case
            case .text(let text, _): // Plain text content
                return text
            case .image(_, let mimeType, _): // Image placeholder
                return "[image: \(mimeType)]"
            case .resource(let contents, _): // Embedded resource content
                switch contents {
                case .text(let uri, let mimeType, let text): // Text resource
                    return "[resource \(uri) (\(mimeType ?? "unknown"))]\n\(text)"
                case .blob(let uri, let mimeType, _): // Binary resource
                    return "[resource blob \(uri) (\(mimeType ?? "unknown"))]"
                }
            }
        }
        .joined(separator: "\n") // Join multiple items with newlines
    }
}

public enum MCPResourceContentFormatter { // Helpers for resource read results
    public static func text(from contents: [MCPResourceContents]) -> String { // Format resource contents for display
        contents.map { item in // Map each content item to a string
            switch item {
            case .text(let uri, let mimeType, let text): // Text body with metadata
                return "[\(uri) (\(mimeType ?? "text/plain"))]\n\(text)"
            case .blob(let uri, let mimeType, _): // Opaque blob reference
                return "[\(uri) blob (\(mimeType ?? "application/octet-stream"))]"
            }
        }
        .joined(separator: "\n\n") // Separate multiple contents with blank line
    }
}
