import Foundation

public enum AppConfigWriter {
    public static func write(_ config: AppConfig) -> String {
        var lines: [String] = []
        lines.append("# MCPC — macOS MCP client configuration")
        lines.append("")
        lines.append("[app]")
        lines.append("name = \(tomlString(config.app.name))")
        lines.append("version = \(tomlString(config.app.version))")
        lines.append("")
        lines.append("[client]")
        lines.append("default_server = \(tomlString(config.client.defaultServer))")
        lines.append("protocol_version = \(tomlString(config.client.protocolVersion))")
        lines.append("request_timeout_seconds = \(config.client.requestTimeoutSeconds)")
        lines.append("log_server_stderr = \(config.client.logServerStderr ? "true" : "false")")
        lines.append("mcp_json_hot_reload = \(config.client.mcpJSONHotReload ? "true" : "false")")
        if !config.client.mcpJSONWatchPaths.isEmpty {
            lines.append("mcp_json_watch_paths = \(tomlArray(config.client.mcpJSONWatchPaths))")
        }
        if !config.client.mcpJSONSyncedServers.isEmpty {
            lines.append("mcp_json_synced_servers = \(tomlArray(config.client.mcpJSONSyncedServers))")
        }
        lines.append("")
        lines.append("[logging]")
        lines.append("level = \(tomlString(config.logging.level.rawValue))")
        lines.append("destination = \(tomlString(config.logging.destination.rawValue))")
        if let logFile = config.logging.logFile, !logFile.isEmpty {
            lines.append("log_file = \(tomlString(logFile))")
        }
        if !config.logging.components.isEmpty {
            lines.append("")
            lines.append("[logging.components]")
            for key in config.logging.components.keys.sorted() {
                lines.append("\(key) = \(tomlString(config.logging.components[key]!.rawValue))")
            }
        }
        lines.append("")
        lines.append("# --- MCP servers -----------------------------------------------------------")
        lines.append("# transport: \"stdio\" | \"sse\" | \"streamable_http\" | \"websocket\"")
        lines.append("")

        for server in config.servers.sorted(by: { $0.name < $1.name }) {
            lines.append("[[servers]]")
            lines.append("name = \(tomlString(server.name))")
            lines.append("transport = \(tomlString(server.transport.configKey))")

            switch server.transport {
            case .stdio:
                if let command = server.command {
                    lines.append("command = \(tomlString(command))")
                }
                if !server.args.isEmpty {
                    lines.append("args = \(tomlArray(server.args))")
                }
                if let workingDirectory = server.workingDirectory, !workingDirectory.isEmpty {
                    lines.append("working_directory = \(tomlString(workingDirectory))")
                }
                if !server.env.isEmpty {
                    lines.append("env = \(tomlInlineTable(server.env))")
                }
            case .sse:
                if let url = server.url {
                    lines.append("url = \(tomlString(url))")
                }
                lines.append(
                    "trust_self_signed_certificates = \(server.trustSelfSignedCertificates ? "true" : "false")"
                )
                lines.append("connection_timeout_seconds = \(server.connectionTimeoutSeconds)")
                lines.append("max_reconnect_attempts = \(server.maxReconnectAttempts)")
                lines.append("reconnect_base_delay_seconds = \(server.reconnectBaseDelaySeconds)")
            case .streamableHTTP, .websocket:
                if let url = server.url {
                    lines.append("url = \(tomlString(url))")
                }
                lines.append(
                    "trust_self_signed_certificates = \(server.trustSelfSignedCertificates ? "true" : "false")"
                )
                if server.transport == .streamableHTTP {
                    lines.append("connection_timeout_seconds = \(server.connectionTimeoutSeconds)")
                }
                if !server.headers.isEmpty {
                    lines.append("")
                    lines.append("[servers.\(server.name).headers]")
                    for key in server.headers.keys.sorted() {
                        lines.append("\(key) = \(tomlString(server.headers[key]!))")
                    }
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    public static func save(_ config: AppConfig, to url: URL) throws {
        let contents = write(config)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AppConfigError.writeFailed(url, error.localizedDescription)
        }
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func tomlArray(_ values: [String]) -> String {
        "[\(values.map(tomlString).joined(separator: ", "))]"
    }

    private static func tomlInlineTable(_ values: [String: String]) -> String {
        let pairs = values.keys.sorted().map { key in
            "\(key) = \(tomlString(values[key]!))"
        }
        return "{\(pairs.joined(separator: ", "))}"
    }
}
