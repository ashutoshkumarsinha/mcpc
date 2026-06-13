import Foundation // Bring in Apple's core types (URL, Data, TimeInterval, etc.)
import MCPClient // Import the MCP client library (transports, protocols, etc.)

/// Wraps ``HTTPSSETransport`` to tolerate MCP servers that acknowledge POSTs with
/// a non-JSON body (e.g. FastMCP returns `202 Accepted` with body `Accepted`) while
/// delivering the actual JSON-RPC response on the SSE `message` stream.
actor SSETransportAdapter: MCPTransport { // `actor` = thread-safe type; conforms to MCPTransport protocol
    private let inner: HTTPSSETransport // Store the real SSE transport we delegate to

    init( // Initializer: builds the inner transport from connection settings
        url: URL, // Server endpoint URL
        headers: [String: String] = [:], // Optional HTTP headers (default empty dictionary)
        connectionTimeout: TimeInterval = 30.0, // Seconds to wait when connecting
        maxReconnectAttempts: Int = 3, // How many times to retry after disconnect
        reconnectBaseDelay: TimeInterval = 1.0, // Base delay between reconnect tries
        trustSelfSignedCertificates: Bool = false // Whether to accept self-signed TLS certs
    ) {
        self.inner = HTTPSSETransport( // Create the underlying HTTPS+SSE transport
            url: url,
            headers: headers,
            connectionTimeout: connectionTimeout,
            maxReconnectAttempts: maxReconnectAttempts,
            reconnectBaseDelay: reconnectBaseDelay,
            trustSelfSignedCertificates: trustSelfSignedCertificates
        )
    }

    func connect() async throws { // `async` = suspendable; `throws` = can fail with an error
        try await inner.connect() // `try await` calls the inner connect and propagates errors
    }

    func disconnect() async throws { // Tear down the SSE connection
        try await inner.disconnect() // Delegate disconnect to the inner transport
    }

    func send(_ data: Data) async throws { // Send raw bytes to the server
        try await inner.send(data) // Forward the data through the inner transport
    }

    func receive() async throws -> Data { // Receive the next JSON-RPC message as Data
        while true { // Loop until we get a message we care about
            let data = try await inner.receive() // Read one chunk/event from the SSE stream
            if SSEJSONMessageFilter.isJSONRPCMessage(data) { // Skip non-JSON-RPC noise (e.g. "Accepted")
                return data // Return the first valid JSON-RPC payload
            }
        }
    }
}
