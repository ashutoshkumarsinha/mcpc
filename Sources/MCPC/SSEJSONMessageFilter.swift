import Foundation
import MCPClient

enum SSEJSONMessageFilter {
    static func isJSONRPCMessage(_ data: Data) -> Bool {
        guard let first = data.first, first == UInt8(ascii: "{") else {
            return false
        }
        return (try? JSONDecoder().decode([String: AnyCodableValue].self, from: data)) != nil
    }
}
