import Foundation

/// Per-user data directory for production GUI deployments (`~/.mcpc`).
public enum MCPCUserDirectory {
    public static let directoryName = ".mcpc"
    public static let configFileName = "config.toml"
    public static let defaultLogFileName = "mcpc.log"

    public static func url(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(directoryName, isDirectory: true)
            .standardizedFileURL
    }

    public static func configURL(fileManager: FileManager = .default) -> URL {
        url(fileManager: fileManager).appendingPathComponent(configFileName)
    }

    public static func defaultLogURL(fileManager: FileManager = .default) -> URL {
        url(fileManager: fileManager).appendingPathComponent(defaultLogFileName)
    }

    /// Creates `~/.mcpc` if needed.
    @discardableResult
    public static func ensureExists(fileManager: FileManager = .default) throws -> URL {
        let directory = url(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Ensures `~/.mcpc` exists and seeds `config.toml` on first launch.
    @discardableResult
    public static func prepareForFirstLaunch(fileManager: FileManager = .default) throws -> URL {
        let directory = try ensureExists(fileManager: fileManager)
        let config = configURL(fileManager: fileManager)

        if !fileManager.fileExists(atPath: config.path) {
            try defaultConfigTemplate().write(to: config, atomically: true, encoding: .utf8)
        }

        let logFile = defaultLogURL(fileManager: fileManager)
        if !fileManager.fileExists(atPath: logFile.path) {
            fileManager.createFile(atPath: logFile.path, contents: nil)
        }

        return directory
    }

    public static func defaultConfigTemplate() -> String {
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
        ].joined(separator: "\n")
    }
}
