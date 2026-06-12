import Foundation
import MCPClient

/// Wraps ``HTTPSSETransport`` to tolerate MCP servers that acknowledge POSTs with
/// a non-JSON body (e.g. FastMCP returns `202 Accepted` with body `Accepted`) while
/// delivering the actual JSON-RPC response on the SSE `message` stream.
actor SSETransportAdapter: MCPTransport {
    private let inner: HTTPSSETransport

    init(
        url: URL,
        headers: [String: String] = [:],
        connectionTimeout: TimeInterval = 30.0,
        maxReconnectAttempts: Int = 3,
        reconnectBaseDelay: TimeInterval = 1.0,
        trustSelfSignedCertificates: Bool = false
    ) {
        self.inner = HTTPSSETransport(
            url: url,
            headers: headers,
            connectionTimeout: connectionTimeout,
            maxReconnectAttempts: maxReconnectAttempts,
            reconnectBaseDelay: reconnectBaseDelay,
            trustSelfSignedCertificates: trustSelfSignedCertificates
        )
    }

    func connect() async throws {
        try await inner.connect()
    }

    func disconnect() async throws {
        try await inner.disconnect()
    }

    func send(_ data: Data) async throws {
        try await inner.send(data)
    }

    func receive() async throws -> Data {
        while true {
            let data = try await inner.receive()
            if SSEJSONMessageFilter.isJSONRPCMessage(data) {
                return data
            }
        }
    }
}
