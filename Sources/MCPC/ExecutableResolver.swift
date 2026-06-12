import Foundation

enum ExecutableResolver {
    /// Resolves a command name to an absolute executable path using the current `PATH`.
    static func resolve(_ command: String, environment: [String: String]? = nil) -> String {
        if command.contains("/") {
            return command
        }

        let env = environment ?? ProcessInfo.processInfo.environment
        let pathValue = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in pathValue.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = "\(directory)/\(command)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return command
    }
}
