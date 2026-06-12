import Foundation
import Logging
import os

public enum MCPCLogging {
    private static let configuration = LoggingConfiguration()
    private static let bootstrapLock = OSAllocatedUnfairLock(initialState: false)

    public static func bootstrap(with settings: LoggingSettings) {
        configuration.update(settings)
        bootstrapLock.withLock { bootstrapped in
            guard !bootstrapped else { return }
            LoggingSystem.bootstrap { label in
                ConfigurableLogHandler(label: label, configuration: configuration)
            }
            bootstrapped = true
        }
    }

    public static func update(with settings: LoggingSettings) {
        configuration.update(settings)
    }

    public static func logger(_ component: String) -> Logging.Logger {
        Logging.Logger(label: "mcpc.\(component)")
    }
}

final class LoggingConfiguration: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: LoggingSettings.default)

    func update(_ settings: LoggingSettings) {
        lock.withLock { state in
            state = settings
        }
    }

    func settings() -> LoggingSettings {
        lock.withLock { $0 }
    }
}

struct ConfigurableLogHandler: LogHandler {
    let label: String
    let configuration: LoggingConfiguration
    var metadata: Logging.Logger.Metadata = [:]

    var logLevel: Logging.Logger.Level {
        get { configuration.settings().effectiveLevel(for: label) ?? .critical }
        set {}
    }

    subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }

    func log(event: LogEvent) {
        let settings = configuration.settings()
        guard settings.destination != .none else { return }
        guard let threshold = settings.effectiveLevel(for: label), event.level >= threshold else { return }

        var combined = self.metadata
        if let eventMetadata = event.metadata {
            combined.merge(eventMetadata) { _, new in new }
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let metadataSuffix = combined.isEmpty
            ? ""
            : " " + combined.map { "\($0)=\($1)" }.sorted().joined(separator: " ")
        let lineText = "\(timestamp) \(event.level) \(label): \(event.message)\(metadataSuffix)\n"

        let data = Data(lineText.utf8)
        switch settings.destination {
        case .stderr:
            FileHandle.standardError.write(data)
        case .stdout:
            FileHandle.standardOutput.write(data)
        case .file:
            writeToLogFile(data, url: settings.resolvedLogFileURL())
        case .none:
            break
        }
    }

    private static let fileLogLock = OSAllocatedUnfairLock()

    private func writeToLogFile(_ data: Data, url: URL?) {
        guard let url else { return }
        Self.fileLogLock.withLock {
            let fileManager = FileManager.default
            let directory = url.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            if !fileManager.fileExists(atPath: url.path) {
                fileManager.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // silent: best-effort file logging
            }
        }
    }
}
