import Foundation

/// Builds a minimal subprocess environment for stdio MCP servers.
enum ProcessEnvironment {
    private static let inheritedKeys = [
        "HOME",
        "LOGNAME",
        "PATH",
        "SHELL",
        "TERM",
        "USER",
        "TMPDIR",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "XPC_SERVICE_NAME",
    ]

    static func mcpSubprocess(overrides: [String: String] = [:]) -> [String: String] {
        let parent = ProcessInfo.processInfo.environment
        var env: [String: String] = [:]

        for key in inheritedKeys {
            if let value = parent[key] {
                env[key] = value
            }
        }

        for (key, value) in overrides {
            env[key] = value
        }

        return env
    }
}
