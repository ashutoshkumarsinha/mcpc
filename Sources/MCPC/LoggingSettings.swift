import Foundation
// swift-log = Apple's logging API; we wrap it in MCPCLogging.
import Logging

// String-backed enum: config values like "info", "debug" map to these cases.
public enum LogLevelName: String, Sendable, Codable, CaseIterable {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case critical
    case none // means "do not log this component"

    // Convert our config name to swift-log's Logger.Level (or nil to suppress).
    public var loggerLevel: Logger.Level? {
        switch self {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .warning: .warning
        case .error: .error
        case .critical: .critical
        case .none: nil
        }
    }
}

// Where MCPC writes its own diagnostic messages (not the MCP server's output).
public enum LogDestination: String, Sendable, Codable, CaseIterable {
    case stderr  // terminal error stream (default for CLI)
    case stdout  // standard output
    case none    // discard all MCPC logs
    case file    // append to a file (production GUI default)
}

// Values from [logging] and [logging.components] in config.toml.
public struct LoggingSettings: Sendable {
    public var level: LogLevelName
    public var destination: LogDestination
    /// Log file name or path when `destination` is `file`. Relative paths resolve under `~/.mcpc`.
    public var logFile: String?
    // Per-logger overrides, e.g. MCPClient = "warning".
    public var components: [String: LogLevelName]

    public init(
        level: LogLevelName = .info,
        destination: LogDestination = .stderr,
        logFile: String? = nil,
        components: [String: LogLevelName] = [:]
    ) {
        self.level = level
        self.destination = destination
        self.logFile = logFile
        self.components = components
    }

    // Turn config into a concrete file URL for append logging.
    public func resolvedLogFileURL(fileManager: FileManager = .default) -> URL? {
        // Only meaningful when destination is file.
        guard destination == .file else { return nil }
        // Trim spaces; optional because log_file may be omitted in TOML.
        let path = logFile?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Use configured name or fall back to mcpc.log.
        let resolvedPath = (path?.isEmpty == false) ? path! : MCPCUserDirectory.defaultLogFileName
        // Absolute path like /tmp/foo.log — use as-is.
        if resolvedPath.hasPrefix("/") {
            return URL(fileURLWithPath: resolvedPath).standardizedFileURL
        }
        // Home-relative path like ~/Desktop/log.txt.
        if resolvedPath.hasPrefix("~/") {
            let relative = String(resolvedPath.dropFirst(2)) // strip "~/"
            return fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(relative)
                .standardizedFileURL
        }
        // Relative name like "mcpc.log" → ~/.mcpc/mcpc.log.
        return MCPCUserDirectory.url(fileManager: fileManager)
            .appendingPathComponent(resolvedPath)
            .standardizedFileURL
    }

    // Used before config.toml is loaded.
    public static let `default` = LoggingSettings(
        level: .info,
        destination: .stderr,
        components: ["MCPClient": .warning] // quiet third-party library by default
    )

    // Decide minimum level for a logger label like "mcpc.session" or "MCPClient.foo".
    public func effectiveLevel(for label: String) -> Logger.Level? {
        // Exact match in [logging.components] wins first.
        if let exact = components[label]?.loggerLevel {
            return exact
        }

        // Prefix match: "mcpc.transport.stdio" matches key "mcpc.transport".
        let prefixMatches = components
            .filter { label.hasPrefix($0.key) }
            .sorted { $0.key.count > $1.key.count } // longest prefix first

        if let first = prefixMatches.first?.value.loggerLevel {
            return first
        }

        // Fall back to global [logging].level.
        return level.loggerLevel
    }
}

// Decode [logging] table from TOML via TOMLDecoder.
extension LoggingSettings: Decodable {
    enum CodingKeys: String, CodingKey {
        case level
        case destination
        case logFile = "log_file" // TOML key uses snake_case
        case components
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decodeIfPresent(LogLevelName.self, forKey: .level) ?? .info
        destination = try container.decodeIfPresent(LogDestination.self, forKey: .destination) ?? .stderr
        logFile = try container.decodeIfPresent(String.self, forKey: .logFile)
        components = try container.decodeIfPresent([String: LogLevelName].self, forKey: .components) ?? [:]
    }
}
