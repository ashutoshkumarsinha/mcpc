import Foundation
// MCPClient = Swift package that speaks the MCP protocol over the wire.
import MCPClient

// Helper that decides whether raw bytes from an SSE stream are a JSON-RPC message.
enum SSEJSONMessageFilter {
    // Returns true only if data looks like a JSON object we can decode.
    static func isJSONRPCMessage(_ data: Data) -> Bool {
        // data.first = first byte; JSON-RPC messages start with '{' (ASCII 123).
        guard let first = data.first, first == UInt8(ascii: "{") else {
            return false // e.g. plain text "Accepted" from HTTP 202 responses
        }
        // Try decoding as a generic JSON object; nil means not valid JSON.
        return (try? JSONDecoder().decode([String: AnyCodableValue].self, from: data)) != nil
    }
}
