// Import Apple's Foundation library (basic types like String, URL, FileManager).
import Foundation
// Import our shared MCPC library (config loading, user directory paths).
import MCPC

// enum = a namespace for related constants; no instances are created.
enum AppMetadata {
    // Name shown in the window title, About dialog, and menu bar.
    static let displayName = "MCP Client"
    // Credit line shown in the About dialog.
    static let developerCredit = "Developed by AKS"

    // computed property: runs code each time someone reads AppMetadata.version.
    static var version: String {
        // try? = attempt to load config; if it fails, return nil instead of crashing.
        if let config = try? AppConfigLoader.load(from: MCPCUserDirectory.configURL()) {
            // Return the version string from the [app] section of config.toml.
            return config.app.version
        }
        // Fallback when config is missing or unreadable.
        return "1.0.0"
    }
}
