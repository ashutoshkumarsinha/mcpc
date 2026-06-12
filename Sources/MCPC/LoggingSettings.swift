import Foundation
import Logging

public enum LogLevelName: String, Sendable, Codable, CaseIterable {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case critical
    case none

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

public enum LogDestination: String, Sendable, Codable, CaseIterable {
    case stderr
    case stdout
    case none
}

public struct LoggingSettings: Sendable {
    public var level: LogLevelName
    public var destination: LogDestination
    public var components: [String: LogLevelName]

    public init(
        level: LogLevelName = .info,
        destination: LogDestination = .stderr,
        components: [String: LogLevelName] = [:]
    ) {
        self.level = level
        self.destination = destination
        self.components = components
    }

    public static let `default` = LoggingSettings(
        level: .info,
        destination: .stderr,
        components: ["MCPClient": .warning]
    )

    public func effectiveLevel(for label: String) -> Logger.Level? {
        if let exact = components[label]?.loggerLevel {
            return exact
        }

        let prefixMatches = components
            .filter { label.hasPrefix($0.key) }
            .sorted { $0.key.count > $1.key.count }

        if let first = prefixMatches.first?.value.loggerLevel {
            return first
        }

        return level.loggerLevel
    }
}

extension LoggingSettings: Decodable {
    enum CodingKeys: String, CodingKey {
        case level
        case destination
        case components
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decodeIfPresent(LogLevelName.self, forKey: .level) ?? .info
        destination = try container.decodeIfPresent(LogDestination.self, forKey: .destination) ?? .stderr
        components = try container.decodeIfPresent([String: LogLevelName].self, forKey: .components) ?? [:]
    }
}
