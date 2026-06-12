import Foundation

public enum MergeConflictPolicy: String, Sendable, CaseIterable {
    case skip
    case replace

    public var label: String {
        switch self {
        case .skip: "Skip existing"
        case .replace: "Replace existing"
        }
    }
}

public struct CursorMCPImportPreview: Sendable {
    public let servers: [ServerConfig]
    public let warnings: [String]

    public init(servers: [ServerConfig], warnings: [String]) {
        self.servers = servers
        self.warnings = warnings
    }
}

public enum CursorMCPImportError: Error, LocalizedError {
    case invalidJSON(String)
    case missingServersRoot
    case noServersFound
    case invalidServer(name: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let reason):
            return "Invalid JSON: \(reason)"
        case .missingServersRoot:
            return "JSON must contain an \"mcpServers\" object (Cursor / Claude Desktop format)."
        case .noServersFound:
            return "No servers found under \"mcpServers\"."
        case .invalidServer(let name, let reason):
            return "Invalid server \"\(name)\": \(reason)"
        }
    }
}

public enum CursorMCPConfigImporter {
    public static func parse(json: String) throws -> CursorMCPImportPreview {
        let data = Data(json.utf8)
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CursorMCPImportError.invalidJSON("Root value must be a JSON object.")
            }
            root = object
        } catch let error as CursorMCPImportError {
            throw error
        } catch {
            throw CursorMCPImportError.invalidJSON(error.localizedDescription)
        }

        guard let mcpServers = root["mcpServers"] as? [String: Any] else {
            throw CursorMCPImportError.missingServersRoot
        }
        guard !mcpServers.isEmpty else {
            throw CursorMCPImportError.noServersFound
        }

        var servers: [ServerConfig] = []
        var warnings: [String] = []

        for (name, value) in mcpServers.sorted(by: { $0.key < $1.key }) {
            guard let entry = value as? [String: Any] else {
                warnings.append("Skipped \"\(name)\": entry is not an object.")
                continue
            }
            do {
                servers.append(try convertServer(name: name, entry: entry))
            } catch let error as CursorMCPImportError {
                throw error
            } catch {
                throw CursorMCPImportError.invalidServer(name: name, reason: error.localizedDescription)
            }
        }

        if servers.isEmpty {
            throw CursorMCPImportError.noServersFound
        }

        return CursorMCPImportPreview(servers: servers, warnings: warnings)
    }

    public static func merge(
        imported: [ServerConfig],
        into config: AppConfig,
        onConflict: MergeConflictPolicy
    ) -> AppConfig {
        var merged = config
        var byName = Dictionary(uniqueKeysWithValues: merged.servers.map { ($0.name, $0) })

        for server in imported {
            switch onConflict {
            case .skip where byName[server.name] != nil:
                continue
            case .replace, .skip:
                byName[server.name] = server
            }
        }

        merged.servers = byName.values.sorted { $0.name < $1.name }
        return merged
    }

    private static func convertServer(name: String, entry: [String: Any]) throws -> ServerConfig {
        let type = stringValue(entry["type"])?.lowercased()
        let command = stringValue(entry["command"])
        let url = stringValue(entry["url"])

        if let command, !command.isEmpty {
            var args = stringArray(entry["args"]) ?? []
            if let cwd = stringValue(entry["cwd"]), !cwd.isEmpty {
                args = rewriteRelativeArgs(args, workingDirectory: cwd)
            }

            return ServerConfig(
                name: name,
                transport: .stdio,
                command: command,
                args: args,
                env: stringMap(entry["env"]),
                workingDirectory: stringValue(entry["cwd"])
            )
        }

        if let url, !url.isEmpty {
            let transport = inferRemoteTransport(type: type, url: url)
            return ServerConfig(
                name: name,
                transport: transport,
                url: url,
                headers: stringMap(entry["headers"]),
                trustSelfSignedCertificates: false
            )
        }

        throw CursorMCPImportError.invalidServer(
            name: name,
            reason: "Entry must include \"command\" (stdio) or \"url\" (remote)."
        )
    }

    private static func inferRemoteTransport(type: String?, url: String) -> ServerTransport {
        if let type, let transport = ServerTransport.parse(type) {
            if transport != .stdio {
                return transport
            }
        }

        let lowered = url.lowercased()
        if lowered.hasPrefix("ws://") || lowered.hasPrefix("wss://") {
            return .websocket
        }
        if lowered.contains("/mcp") {
            return .streamableHTTP
        }
        if lowered.contains("/sse") {
            return .sse
        }
        return .sse
    }

    private static func rewriteRelativeArgs(_ args: [String], workingDirectory: String) -> [String] {
        args.map { arg in
            guard arg.hasPrefix("./") || arg.hasPrefix("../") else { return arg }
            return URL(fileURLWithPath: workingDirectory, isDirectory: true)
                .appendingPathComponent(arg)
                .standardizedFileURL
                .path
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return nil
        }
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        guard let array = value as? [Any] else { return nil }
        return array.compactMap { stringValue($0) }
    }

    private static func stringMap(_ value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, raw) in dictionary {
            if let string = stringValue(raw) {
                result[key] = string
            }
        }
        return result
    }
}
