import Foundation

/// Cursor / Claude Desktop style MCP server configuration.
public struct MCPServersFile: Codable, Sendable {
    public let mcpServers: [String: MCPServerDefinition]

    public init(mcpServers: [String: MCPServerDefinition]) {
        self.mcpServers = mcpServers
    }
}

/// A single stdio MCP server entry (`command` + `args`, optional `env`).
public struct MCPServerDefinition: Codable, Sendable {
    public let command: String
    public let args: [String]
    public let env: [String: String]?

    public init(command: String, args: [String], env: [String: String]? = nil) {
        self.command = command
        self.args = args
        self.env = env
    }
}

public enum MCPServerConfigError: Error, CustomStringConvertible {
    case fileNotFound(URL)
    case decodeFailed(underlying: Error)
    case serverNotFound(name: String, available: [String])

    public var description: String {
        switch self {
        case .fileNotFound(let url):
            return "MCP config not found at \(url.path)"
        case .decodeFailed(let underlying):
            return "Failed to decode MCP config: \(underlying.localizedDescription)"
        case .serverNotFound(let name, let available):
            let names = available.sorted().joined(separator: ", ")
            return "Server '\(name)' not found in config. Available: \(names)"
        }
    }
}

public enum MCPServerConfigLoader {
    public static func load(from url: URL) throws -> MCPServersFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPServerConfigError.fileNotFound(url)
        }

        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(MCPServersFile.self, from: data)
        } catch {
            throw MCPServerConfigError.decodeFailed(underlying: error)
        }
    }

    public static func definition(
        named serverName: String,
        in config: MCPServersFile
    ) throws -> MCPServerDefinition {
        guard let definition = config.mcpServers[serverName] else {
            throw MCPServerConfigError.serverNotFound(
                name: serverName,
                available: Array(config.mcpServers.keys)
            )
        }
        return definition
    }
}
