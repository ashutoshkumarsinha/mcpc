import Foundation // Core types (URL, TimeInterval, etc.)
import Logging // Structured logging API
import MCPClient // MCP transport protocols and concrete transports

public enum TransportFactory { // `enum` with no cases = namespace for static factory methods
    private static let log = MCPCLogging.logger("transport") // Logger scoped to the transport component

    public static func makeTransport( // Build the right MCPTransport for a server config
        for server: ServerConfig, // Server entry from config.toml
        client: ClientSettings // Global client settings (timeouts, stderr logging, etc.)
    ) throws -> any MCPTransport { // `throws` on invalid config; `any` = existential protocol type
        log.debug( // Log at debug level while creating a transport
            "Creating transport",
            metadata: [
                "server": .string(server.name), // Server name in log metadata
                "transport": .string(server.transport.configKey), // Transport kind string
            ]
        )
        switch server.transport { // Branch on stdio / sse / streamable HTTP / websocket
        case .stdio: // Local subprocess over stdin/stdout
            guard let command = server.command else { // `guard` requires a command for stdio
                throw AppConfigError.invalidServer( // Fail fast with a descriptive config error
                    name: server.name,
                    reason: "stdio transport requires 'command'"
                )
            }

            let environment = ProcessEnvironment.mcpSubprocess(overrides: server.env) // Merge MCP env vars

            return SubprocessStdioTransport( // Spawn a child process and speak JSON-RPC over pipes
                command: ExecutableResolver.resolve(command, environment: environment), // Resolve executable path
                arguments: server.args, // CLI arguments for the server process
                environment: environment, // Environment dictionary passed to the child
                workingDirectory: server.workingDirectory, // Optional cwd for the subprocess
                logStderr: client.logServerStderr // Whether to forward server stderr to our stderr
            )

        case .sse: // HTTP + Server-Sent Events transport
            guard let urlString = server.url, let url = URL(string: urlString) else { // Need a valid URL
                throw AppConfigError.invalidServer(
                    name: server.name,
                    reason: "sse transport requires a valid 'url' (SSE GET endpoint)"
                )
            }

            log.info( // Info-level log for remote SSE setup
                "Configuring SSE transport",
                metadata: [
                    "server": .string(server.name),
                    "url": .string(url.absoluteString),
                    "max_reconnect_attempts": .stringConvertible(server.maxReconnectAttempts),
                ]
            )

            return SSETransportAdapter( // Wrapped SSE transport that filters non-JSON POST acks
                url: url,
                headers: server.headers,
                connectionTimeout: TimeInterval(server.connectionTimeoutSeconds),
                maxReconnectAttempts: server.maxReconnectAttempts,
                reconnectBaseDelay: server.reconnectBaseDelaySeconds,
                trustSelfSignedCertificates: server.trustSelfSignedCertificates
            )

        case .streamableHTTP: // MCP streamable HTTP (single /mcp endpoint)
            guard let urlString = server.url, let url = URL(string: urlString) else { // Validate URL
                throw AppConfigError.invalidServer(
                    name: server.name,
                    reason: "streamable_http transport requires a valid 'url' (MCP POST endpoint)"
                )
            }

            log.info(
                "Configuring Streamable HTTP transport",
                metadata: [
                    "server": .string(server.name),
                    "url": .string(url.absoluteString),
                ]
            )

            return StreamableHTTPTransport( // Use the library's streamable HTTP implementation
                url: url,
                headers: server.headers,
                connectionTimeout: TimeInterval(server.connectionTimeoutSeconds),
                trustSelfSignedCertificates: server.trustSelfSignedCertificates
            )

        case .websocket: // WebSocket transport
            guard let urlString = server.url, let url = URL(string: urlString) else { // Need ws/wss URL
                throw AppConfigError.invalidServer(
                    name: server.name,
                    reason: "websocket transport requires a valid 'url'"
                )
            }

            return WebSocketTransport( // Library WebSocket client
                url: url,
                headers: server.headers,
                trustSelfSignedCertificates: server.trustSelfSignedCertificates
            )
        }
    }
}
