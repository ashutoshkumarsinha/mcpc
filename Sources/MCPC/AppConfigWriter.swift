import Foundation // String, URL, file writing

public enum AppConfigWriter { // Namespace for serializing AppConfig back to TOML text
    public static func write(_ config: AppConfig) -> String { // Turn an in-memory config into TOML string
        var lines: [String] = [] // Accumulate output lines
        lines.append("# MCPC — macOS MCP client configuration") // File header comment
        lines.append("") // Blank line separator
        lines.append("[app]") // TOML table for application metadata
        lines.append("name = \(tomlString(config.app.name))") // Quoted app name
        lines.append("version = \(tomlString(config.app.version))") // Quoted version string
        lines.append("") // Blank line
        lines.append("[client]") // Client-wide settings table
        lines.append("default_server = \(tomlString(config.client.defaultServer))") // Default [[servers]] name
        lines.append("protocol_version = \(tomlString(config.client.protocolVersion))") // MCP protocol version
        lines.append("request_timeout_seconds = \(config.client.requestTimeoutSeconds)") // Numeric timeout
        lines.append("log_server_stderr = \(config.client.logServerStderr ? "true" : "false")") // Boolean as TOML literal
        lines.append("mcp_json_hot_reload = \(config.client.mcpJSONHotReload ? "true" : "false")") // Hot reload toggle
        if !config.client.mcpJSONWatchPaths.isEmpty { // Only emit watch paths when configured
            lines.append("mcp_json_watch_paths = \(tomlArray(config.client.mcpJSONWatchPaths))") // TOML string array
        }
        if !config.client.mcpJSONSyncedServers.isEmpty { // Only emit synced server names when non-empty
            lines.append("mcp_json_synced_servers = \(tomlArray(config.client.mcpJSONSyncedServers))") // Managed import names
        }
        lines.append("") // Blank line
        lines.append("[logging]") // Logging settings table
        lines.append("level = \(tomlString(config.logging.level.rawValue))") // Global log level
        lines.append("destination = \(tomlString(config.logging.destination.rawValue))") // Where logs go
        if let logFile = config.logging.logFile, !logFile.isEmpty { // Optional log file path
            lines.append("log_file = \(tomlString(logFile))") // Quoted path when set
        }
        if !config.logging.components.isEmpty { // Per-component log overrides
            lines.append("") // Blank line before sub-table
            lines.append("[logging.components]") // Nested components table
            for key in config.logging.components.keys.sorted() { // Stable key order in output
                lines.append("\(key) = \(tomlString(config.logging.components[key]!.rawValue))") // `!` force-unwraps known key
            }
        }
        lines.append("") // Blank line
        lines.append("# --- MCP servers -----------------------------------------------------------") // Section comment
        lines.append("# transport: \"stdio\" | \"sse\" | \"streamable_http\" | \"websocket\"") // Document valid transport values
        lines.append("") // Blank line before server array

        for server in config.servers.sorted(by: { $0.name < $1.name }) { // Emit servers in sorted name order
            lines.append("[[servers]]") // TOML array-of-tables entry
            lines.append("name = \(tomlString(server.name))") // Server identifier
            lines.append("transport = \(tomlString(server.transport.configKey))") // Transport kind string

            switch server.transport { // Write transport-specific fields
            case .stdio: // Subprocess transport
                if let command = server.command { // Optional in struct but required for stdio in practice
                    lines.append("command = \(tomlString(command))") // Executable command
                }
                if !server.args.isEmpty { // CLI args array when present
                    lines.append("args = \(tomlArray(server.args))") // TOML array of quoted strings
                }
                if let workingDirectory = server.workingDirectory, !workingDirectory.isEmpty { // Optional cwd
                    lines.append("working_directory = \(tomlString(workingDirectory))") // Quoted directory path
                }
                if !server.env.isEmpty { // Environment overrides
                    lines.append("env = \(tomlInlineTable(server.env))") // Inline TOML table { key = "value", ... }
                }
            case .sse: // SSE-specific numeric/bool fields
                if let url = server.url { // Remote endpoint URL
                    lines.append("url = \(tomlString(url))") // Quoted URL string
                }
                lines.append(
                    "trust_self_signed_certificates = \(server.trustSelfSignedCertificates ? "true" : "false")" // TLS override
                )
                lines.append("connection_timeout_seconds = \(server.connectionTimeoutSeconds)") // Connect timeout
                lines.append("max_reconnect_attempts = \(server.maxReconnectAttempts)") // Reconnect retry count
                lines.append("reconnect_base_delay_seconds = \(server.reconnectBaseDelaySeconds)") // Backoff base delay
            case .streamableHTTP, .websocket: // URL-based transports sharing some fields
                if let url = server.url { // Endpoint URL
                    lines.append("url = \(tomlString(url))") // Quoted URL
                }
                lines.append(
                    "trust_self_signed_certificates = \(server.trustSelfSignedCertificates ? "true" : "false")" // TLS setting
                )
                if server.transport == .streamableHTTP { // Timeout only applies to streamable HTTP here
                    lines.append("connection_timeout_seconds = \(server.connectionTimeoutSeconds)") // Connect timeout
                }
                if !server.headers.isEmpty { // HTTP headers as a nested table
                    lines.append("") // Blank line before nested table
                    lines.append("[servers.\(server.name).headers]") // TOML sub-table keyed by server name
                    for key in server.headers.keys.sorted() { // Stable header key order
                        lines.append("\(key) = \(tomlString(server.headers[key]!))") // Quoted header value
                    }
                }
            }
            lines.append("") // Blank line between server entries
        }

        return lines.joined(separator: "\n") // Join all lines into one TOML document string
    }

    public static func save(_ config: AppConfig, to url: URL) throws { // Persist config to disk
        let contents = write(config) // Serialize to TOML text first
        do { // `do/catch` handles write errors locally
            try contents.write(to: url, atomically: true, encoding: .utf8) // Atomic write avoids partial files
        } catch { // Map Foundation errors to app-specific error
            throw AppConfigError.writeFailed(url, error.localizedDescription) // Re-throw as AppConfigError
        }
    }

    private static func tomlString(_ value: String) -> String { // Escape and quote a TOML string value
        let escaped = value // Start from raw string
            .replacingOccurrences(of: "\\", with: "\\\\") // Escape backslashes
            .replacingOccurrences(of: "\"", with: "\\\"") // Escape double quotes
            .replacingOccurrences(of: "\t", with: "\\t") // Escape tabs
            .replacingOccurrences(of: "\n", with: "\\n") // Escape newlines
        return "\"\(escaped)\"" // Wrap in double quotes for TOML
    }

    private static func tomlArray(_ values: [String]) -> String { // Format [String] as TOML array
        "[\(values.map(tomlString).joined(separator: ", "))]" // Map each element through tomlString
    }

    private static func tomlInlineTable(_ values: [String: String]) -> String { // Format dictionary as inline table
        let pairs = values.keys.sorted().map { key in // Sorted keys for stable output
            "\(key) = \(tomlString(values[key]!))" // key = "value" pair
        }
        return "{\(pairs.joined(separator: ", "))}" // Wrap pairs in { ... }
    }
}
