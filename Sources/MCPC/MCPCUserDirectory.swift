import Foundation

/// Per-user data directory for production GUI deployments (`~/.mcpc`).
// public = other modules (GUI, tests) can use this type.
// enum with only static members = namespace, not something you instantiate.
public enum MCPCUserDirectory {
    // Folder name under the user's home directory.
    public static let directoryName = ".mcpc"
    // Config file name inside that folder.
    public static let configFileName = "config.toml"
    // Default log file name when [logging].destination = "file".
    public static let defaultLogFileName = "mcpc.log"

    // Full URL to ~/.mcpc/ (trailing slash implied by isDirectory: true).
    public static func url(fileManager: FileManager = .default) -> URL {
        // homeDirectoryForCurrentUser ≈ /Users/yourname on macOS.
        fileManager.homeDirectoryForCurrentUser
            // Append ".mcpc" as a directory component.
            .appendingPathComponent(directoryName, isDirectory: true)
            // Resolve ".." and symlinks to a canonical path.
            .standardizedFileURL
    }

    // Full URL to ~/.mcpc/config.toml.
    public static func configURL(fileManager: FileManager = .default) -> URL {
        url(fileManager: fileManager).appendingPathComponent(configFileName)
    }

    // Full URL to ~/.mcpc/mcpc.log.
    public static func defaultLogURL(fileManager: FileManager = .default) -> URL {
        url(fileManager: fileManager).appendingPathComponent(defaultLogFileName)
    }

    /// Creates `~/.mcpc` if needed.
    // @discardableResult = caller may ignore the returned URL without a warning.
    @discardableResult
    public static func ensureExists(fileManager: FileManager = .default) throws -> URL {
        let directory = url(fileManager: fileManager)
        // withIntermediateDirectories: true creates parent paths if missing.
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Ensures `~/.mcpc` exists and seeds `config.toml` on first launch.
    @discardableResult
    public static func prepareForFirstLaunch(fileManager: FileManager = .default) throws -> URL {
        // Step 1: make sure the folder exists.
        let directory = try ensureExists(fileManager: fileManager)
        let config = configURL(fileManager: fileManager)

        // Step 2: write starter config only if user does not already have one.
        if !fileManager.fileExists(atPath: config.path) {
            // atomically: true writes to a temp file then renames (safer on crash).
            try defaultConfigTemplate().write(to: config, atomically: true, encoding: .utf8)
        }

        // Step 3: touch empty log file so tail -f works immediately.
        let logFile = defaultLogURL(fileManager: fileManager)
        if !fileManager.fileExists(atPath: logFile.path) {
            fileManager.createFile(atPath: logFile.path, contents: nil)
        }

        return directory
    }

    // Text written to a brand-new config.toml on first launch.
    public static func defaultConfigTemplate() -> String {
        // Array of lines joined with newlines — avoids accidental indentation in TOML.
        [
            "# MCP Client — user configuration (~/.mcpc/config.toml)",
            "",
            "[app]",
            "name = \"MCP Client\"",
            "version = \"1.0.0\"",
            "",
            "[client]",
            "default_server = \"\"",
            "protocol_version = \"2024-11-05\"",
            "request_timeout_seconds = 120",
            "log_server_stderr = false",
            "mcp_json_hot_reload = true",
            "",
            "[logging]",
            "level = \"info\"",
            "destination = \"file\"",
            "log_file = \"\(defaultLogFileName)\"",
            "",
            "[logging.components]",
            "MCPClient = \"warning\"",
            "",
            "# --- MCP servers -----------------------------------------------------------",
            "# transport: \"stdio\" | \"sse\" | \"streamable_http\" | \"websocket\"",
            "#",
            "# [[servers]]",
            "# name = \"my-server\"",
            "# transport = \"stdio\"",
            "# command = \"/path/to/mcp-server\"",
            "# args = []",
        ].joined(separator: "\n") // single string with one line per array element
    }
}
