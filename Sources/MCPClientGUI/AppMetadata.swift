import Foundation
import MCPC

enum AppMetadata {
    static let displayName = "MCP Client"
    static let developerCredit = "Developed by AKS"

    static var version: String {
        if let config = try? AppConfigLoader.load(from: MCPCUserDirectory.configURL()) {
            return config.app.version
        }
        return "1.0.0"
    }
}
