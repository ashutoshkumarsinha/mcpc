import Foundation
import Logging
import MCPClient

public enum TransportFactory {
    private static let log = MCPCLogging.logger("transport")

    public static func makeTransport(
        for server: ServerConfig,
        client: ClientSettings
    ) throws -> any MCPTransport {
        log.debug(
            "Creating transport",
            metadata: [
                "server": .string(server.name),
                "transport": .string(server.transport.configKey),
            ]
        )
        switch server.transport {
        case .stdio:
            guard let command = server.command else {
                throw AppConfigError.invalidServer(
                    name: server.name,
                    reason: "stdio transport requires 'command'"
                )
            }

            let environment = ProcessEnvironment.mcpSubprocess(overrides: server.env)

            return SubprocessStdioTransport(
                command: ExecutableResolver.resolve(command, environment: environment),
                arguments: server.args,
                environment: environment,
                workingDirectory: server.workingDirectory,
                logStderr: client.logServerStderr
            )

        case .sse:
            guard let urlString = server.url, let url = URL(string: urlString) else {
                throw AppConfigError.invalidServer(
                    name: server.name,
                    reason: "sse transport requires a valid 'url' (SSE GET endpoint)"
                )
            }

            log.info(
                "Configuring SSE transport",
                metadata: [
                    "server": .string(server.name),
                    "url": .string(url.absoluteString),
                    "max_reconnect_attempts": .stringConvertible(server.maxReconnectAttempts),
                ]
            )

            return SSETransportAdapter(
                url: url,
                headers: server.headers,
                connectionTimeout: TimeInterval(server.connectionTimeoutSeconds),
                maxReconnectAttempts: server.maxReconnectAttempts,
                reconnectBaseDelay: server.reconnectBaseDelaySeconds,
                trustSelfSignedCertificates: server.trustSelfSignedCertificates
            )

        case .streamableHTTP:
            guard let urlString = server.url, let url = URL(string: urlString) else {
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

            return StreamableHTTPTransport(
                url: url,
                headers: server.headers,
                connectionTimeout: TimeInterval(server.connectionTimeoutSeconds),
                trustSelfSignedCertificates: server.trustSelfSignedCertificates
            )

        case .websocket:
            guard let urlString = server.url, let url = URL(string: urlString) else {
                throw AppConfigError.invalidServer(
                    name: server.name,
                    reason: "websocket transport requires a valid 'url'"
                )
            }

            return WebSocketTransport(
                url: url,
                headers: server.headers,
                trustSelfSignedCertificates: server.trustSelfSignedCertificates
            )
        }
    }
}
