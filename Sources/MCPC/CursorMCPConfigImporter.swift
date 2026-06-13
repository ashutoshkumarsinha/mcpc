import Foundation // JSON parsing, dictionaries, URL helpers

public enum MergeConflictPolicy: String, Sendable, CaseIterable { // Import conflict behavior; `CaseIterable` enables ForEach in UI
    case skip // Keep existing server when names collide
    case replace // Overwrite existing server with imported one

    public var label: String { // Human-readable label for pickers
        switch self {
        case .skip: "Skip existing" // UI string for skip policy
        case .replace: "Replace existing" // UI string for replace policy
        }
    }
}

public struct CursorMCPImportPreview: Sendable { // Parsed-but-not-yet-merged import preview
    public let servers: [ServerConfig] // Servers extracted from JSON
    public let warnings: [String] // Non-fatal parse warnings

    public init(servers: [ServerConfig], warnings: [String]) {
        self.servers = servers // Store parsed servers
        self.warnings = warnings // Store warning messages
    }
}

public enum CursorMCPImportError: Error, LocalizedError { // Typed import failures; `LocalizedError` supplies user-facing text
    case invalidJSON(String) // JSON syntax/shape problems
    case missingServersRoot // Top-level mcpServers key missing
    case noServersFound // mcpServers empty or all entries skipped
    case invalidServer(name: String, reason: String) // One server entry invalid

    public var errorDescription: String? { // `LocalizedError` message for UI/alerts
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

public enum CursorMCPConfigImporter { // Parse and merge Cursor-style mcp.json
    public static func parse(json: String) throws -> CursorMCPImportPreview { // JSON string -> preview struct
        let data = Data(json.utf8) // Convert Swift String to UTF-8 Data for JSONSerialization
        let root: [String: Any] // Untyped JSON object dictionary
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { // Root must be object
                throw CursorMCPImportError.invalidJSON("Root value must be a JSON object.")
            }
            root = object // Save parsed root dictionary
        } catch let error as CursorMCPImportError { // Re-throw our own errors unchanged
            throw error
        } catch { // Wrap other Foundation JSON errors
            throw CursorMCPImportError.invalidJSON(error.localizedDescription)
        }

        guard let mcpServers = root["mcpServers"] as? [String: Any] else { // Cursor format uses mcpServers object
            throw CursorMCPImportError.missingServersRoot
        }
        guard !mcpServers.isEmpty else { // Require at least one entry key
            throw CursorMCPImportError.noServersFound
        }

        var servers: [ServerConfig] = [] // Successfully converted servers
        var warnings: [String] = [] // Skipped/soft issues

        for (name, value) in mcpServers.sorted(by: { $0.key < $1.key }) { // Stable sorted iteration by server name
            guard let entry = value as? [String: Any] else { // Each server must be a JSON object
                warnings.append("Skipped \"\(name)\": entry is not an object.") // Record warning and continue
                continue
            }
            do {
                servers.append(try convertServer(name: name, entry: entry)) // Convert one Cursor entry
            } catch let error as CursorMCPImportError { // Fatal per-server errors propagate
                throw error
            } catch { // Wrap unexpected conversion errors
                throw CursorMCPImportError.invalidServer(name: name, reason: error.localizedDescription)
            }
        }

        if servers.isEmpty { // All entries skipped or invalid
            throw CursorMCPImportError.noServersFound
        }

        return CursorMCPImportPreview(servers: servers, warnings: warnings) // Return preview for UI/merge
    }

    public static func merge( // Simple one-shot merge without sync tracking
        imported: [ServerConfig],
        into config: AppConfig,
        onConflict: MergeConflictPolicy
    ) -> AppConfig {
        var merged = config // Copy config to mutate
        var byName = Dictionary(uniqueKeysWithValues: merged.servers.map { ($0.name, $0) }) // Index existing servers

        for server in imported { // Apply imported servers
            switch onConflict {
            case .skip where byName[server.name] != nil: // Skip duplicates when policy says so
                continue
            case .replace, .skip: // Replace always writes; skip only when absent
                byName[server.name] = server
            }
        }

        merged.servers = byName.values.sorted { $0.name < $1.name } // Sorted output list
        return merged
    }

    private static func convertServer(name: String, entry: [String: Any]) throws -> ServerConfig { // Map Cursor JSON entry -> ServerConfig
        let type = stringValue(entry["type"])?.lowercased() // Optional explicit transport type
        let command = stringValue(entry["command"]) // Optional stdio command
        let url = stringValue(entry["url"]) // Optional remote URL

        if let command, !command.isEmpty { // stdio-style entry when command present
            var args = stringArray(entry["args"]) ?? [] // CLI args array, default empty
            if let cwd = stringValue(entry["cwd"]), !cwd.isEmpty { // Working directory may rewrite relative args
                args = rewriteRelativeArgs(args, workingDirectory: cwd)
            }

            return ServerConfig( // Build stdio ServerConfig
                name: name,
                transport: .stdio,
                command: command,
                args: args,
                env: stringMap(entry["env"]),
                workingDirectory: stringValue(entry["cwd"])
            )
        }

        if let url, !url.isEmpty { // Remote entry when url present
            let transport = inferRemoteTransport(type: type, url: url) // Guess transport from type/url
            return ServerConfig(
                name: name,
                transport: transport,
                url: url,
                headers: stringMap(entry["headers"]),
                trustSelfSignedCertificates: false // Cursor JSON has no TLS override field here
            )
        }

        throw CursorMCPImportError.invalidServer( // Neither command nor url => invalid
            name: name,
            reason: "Entry must include \"command\" (stdio) or \"url\" (remote)."
        )
    }

    private static func inferRemoteTransport(type: String?, url: String) -> ServerTransport { // Heuristic transport detection
        if let type, let transport = ServerTransport.parse(type) { // Honor explicit type when recognized
            if transport != .stdio { // Ignore stdio type on URL entries
                return transport
            }
        }

        let lowered = url.lowercased() // Case-insensitive URL inspection
        if lowered.hasPrefix("ws://") || lowered.hasPrefix("wss://") { // WebSocket schemes
            return .websocket
        }
        if lowered.contains("/mcp") { // Common streamable HTTP path segment
            return .streamableHTTP
        }
        if lowered.contains("/sse") { // Explicit SSE path hint
            return .sse
        }
        return .sse // Default remote transport fallback
    }

    private static func rewriteRelativeArgs(_ args: [String], workingDirectory: String) -> [String] { // Resolve ./ and ../ args against cwd
        args.map { arg in // Transform each argument string
            guard arg.hasPrefix("./") || arg.hasPrefix("../") else { return arg } // Leave absolute/non-relative args alone
            return URL(fileURLWithPath: workingDirectory, isDirectory: true)
                .appendingPathComponent(arg)
                .standardizedFileURL
                .path // Return absolute filesystem path string
        }
    }

    private static func stringValue(_ value: Any?) -> String? { // Coerce JSON values to String when possible
        switch value {
        case let string as String:
            return string
        case let number as NSNumber: // JSON numbers may arrive as NSNumber
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return nil // Unsupported JSON types become nil
        }
    }

    private static func stringArray(_ value: Any?) -> [String]? { // Parse JSON array of strings
        guard let array = value as? [Any] else { return nil } // Must be JSON array
        return array.compactMap { stringValue($0) } // Drop elements that cannot coerce to String
    }

    private static func stringMap(_ value: Any?) -> [String: String] { // Parse JSON object of string values
        guard let dictionary = value as? [String: Any] else { return [:] } // Missing/invalid -> empty map
        var result: [String: String] = [:] // Output string dictionary
        for (key, raw) in dictionary { // Walk key/value pairs
            if let string = stringValue(raw) { // Keep only coercible string values
                result[key] = string
            }
        }
        return result
    }
}
