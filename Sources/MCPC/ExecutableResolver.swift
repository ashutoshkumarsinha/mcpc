import Foundation

// Finds the full filesystem path for a command name (e.g. "uv" → "/Users/.../.local/bin/uv").
enum ExecutableResolver {
    /// Resolves a command name to an absolute executable path using the current `PATH`.
    static func resolve(_ command: String, environment: [String: String]? = nil) -> String {
        // If the config already gave a path (contains "/"), use it as-is.
        if command.contains("/") {
            return command
        }

        // Use passed-in env or the current process environment (has PATH, HOME, etc.).
        let env = environment ?? ProcessInfo.processInfo.environment
        // PATH is colon-separated list of directories to search for executables.
        let pathValue = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        // Walk each directory in PATH.
        for directory in pathValue.split(separator: ":", omittingEmptySubsequences: true) {
            // Build candidate path: e.g. "/usr/local/bin" + "/" + "uv".
            let candidate = "\(directory)/\(command)"
            // Check if that file exists and is marked executable.
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate // found it
            }
        }

        // Nothing found — return original name; Process may still fail at spawn time.
        return command
    }
}
