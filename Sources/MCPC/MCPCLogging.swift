import Foundation
import Logging
import os // OSAllocatedUnfairLock for fast thread-safe locks.

// Central place to configure swift-log for the whole app.
public enum MCPCLogging {
    // Holds current LoggingSettings; shared by all log handlers.
    private static let configuration = LoggingConfiguration()
    // Ensures LoggingSystem.bootstrap runs only once per process.
    private static let bootstrapLock = OSAllocatedUnfairLock(initialState: false)

    // Call at process start (CLI or GUI init) before any log line is emitted.
    public static func bootstrap(with settings: LoggingSettings) {
        configuration.update(settings)
        bootstrapLock.withLock { bootstrapped in
            guard !bootstrapped else { return } // already installed
            // Register our handler factory for all Logger instances.
            LoggingSystem.bootstrap { label in
                ConfigurableLogHandler(label: label, configuration: configuration)
            }
            bootstrapped = true
        }
    }

    // Call after loading config.toml to apply [logging] without re-bootstrapping.
    public static func update(with settings: LoggingSettings) {
        configuration.update(settings)
    }

    // Convenience: MCPCLogging.logger("session") → label "mcpc.session".
    public static func logger(_ component: String) -> Logging.Logger {
        Logging.Logger(label: "mcpc.\(component)")
    }
}

// Thread-safe holder for LoggingSettings (handlers read it on every log line).
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

// Custom swift-log handler: formats lines and writes to stderr/stdout/file.
struct ConfigurableLogHandler: LogHandler {
    let label: String
    let configuration: LoggingConfiguration
    var metadata: Logging.Logger.Metadata = [:] // key=value pairs attached to log calls

    // swift-log reads this to filter messages; we compute from config each time.
    var logLevel: Logging.Logger.Level {
        get { configuration.settings().effectiveLevel(for: label) ?? .critical }
        set {} // required by protocol; we ignore writes
    }

    // Protocol requirement for per-logger metadata dictionary.
    subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }

    // Called by Logger when someone writes log.info("...", metadata: [...]).
    func log(event: LogEvent) {
        let settings = configuration.settings()
        guard settings.destination != .none else { return } // logging disabled
        // Drop messages below the effective level for this label.
        guard let threshold = settings.effectiveLevel(for: label), event.level >= threshold else { return }

        // Merge handler metadata with event metadata.
        var combined = self.metadata
        if let eventMetadata = event.metadata {
            combined.merge(eventMetadata) { _, new in new }
        }

        // Build one line: timestamp level label: message key=value ...
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

    // One lock for all file writes so concurrent log lines do not interleave badly.
    private static let fileLogLock = OSAllocatedUnfairLock()

    private func writeToLogFile(_ data: Data, url: URL?) {
        guard let url else { return }
        Self.fileLogLock.withLock {
            let fileManager = FileManager.default
            let directory = url.deletingLastPathComponent()
            // Ensure ~/.mcpc (or custom log dir) exists.
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            if !fileManager.fileExists(atPath: url.path) {
                fileManager.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() } // always close file when leaving scope
            do {
                try handle.seekToEnd()           // append mode
                try handle.write(contentsOf: data)
            } catch {
                // silent: best-effort file logging
            }
        }
    }
}
