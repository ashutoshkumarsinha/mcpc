import Foundation

/// Builds a subprocess environment compatible with the Python MCP stdio client.
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

        // Unbuffered Python stdout/stderr over pipes.
        env["PYTHONUNBUFFERED"] = "1"

        for (key, value) in overrides {
            env[key] = value
        }

        return env
    }
}
