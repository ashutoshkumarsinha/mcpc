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
                "transport": .string(server.transport.rawValue),
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
                logStderr: client.logServerStderr
            )

        case .httpSSE:
            guard let urlString = server.url, let url = URL(string: urlString) else {
                throw AppConfigError.invalidServer(
                    name: server.name,
                    reason: "http_sse transport requires a valid 'url'"
                )
            }

            return HTTPSSETransport(
                url: url,
                headers: server.headers,
                connectionTimeout: TimeInterval(server.connectionTimeoutSeconds),
                maxReconnectAttempts: server.maxReconnectAttempts,
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
