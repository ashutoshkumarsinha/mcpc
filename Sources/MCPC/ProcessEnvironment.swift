import Foundation

/// Builds a minimal subprocess environment for stdio MCP servers.
enum ProcessEnvironment {
    // Only these variables are copied from the parent process into the child.
    private static let inheritedKeys = [
        "HOME",              // user home directory
        "LOGNAME",           // login name
        "PATH",              // where to find executables
        "SHELL",             // default shell
        "TERM",              // terminal type
        "USER",              // username
        "TMPDIR",            // temp directory
        "LANG",              // locale
        "LC_ALL",            // locale override
        "LC_CTYPE",          // character encoding
        "XPC_SERVICE_NAME",  // macOS service context
    ]

    // Build env dict for spawning an MCP server subprocess.
    static func mcpSubprocess(overrides: [String: String] = [:]) -> [String: String] {
        // Read this app's full environment.
        let parent = ProcessInfo.processInfo.environment
        // Start with an empty dictionary we will fill in.
        var env: [String: String] = [:]

        // Copy only the whitelisted keys (keeps subprocess env small and predictable).
        for key in inheritedKeys {
            if let value = parent[key] {
                env[key] = value
            }
        }

        // Apply per-server overrides from config.toml [[servers]].env (e.g. API keys).
        for (key, value) in overrides {
            env[key] = value
        }

        return env
    }
}
