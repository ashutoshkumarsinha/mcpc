import Foundation
import MCPClient

public enum MCPCLICommand: Sendable {
    case listServers
    case ping
    case listTools
    case listResources
    case listPrompts
    case callTool(name: String, arguments: [String: AnyCodableValue])
    case readResource(uri: String)
    case getPrompt(name: String, arguments: [String: String])
}

public struct MCPCLIOptions: Sendable {
    public let configURL: URL
    public let serverName: String?
    public let command: MCPCLICommand

    public init(configURL: URL, serverName: String?, command: MCPCLICommand) {
        self.configURL = configURL
        self.serverName = serverName
        self.command = command
    }
}

public enum MCPCLIError: Error, CustomStringConvertible, Equatable {
    case missingValue(String)
    case unknownOption(String)
    case missingCommand
    case invalidJSON(String)
    case helpRequested

    public var description: String {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .unknownOption(let option):
            return "Unknown option: \(option)"
        case .missingCommand:
            return "Missing command. Run mcpc --help for usage."
        case .invalidJSON(let value):
            return "Invalid JSON for --args: \(value)"
        case .helpRequested:
            return "Help requested"
        }
    }
}

public enum MCPCLI {
    public static func parseArguments(_ arguments: [String]) throws -> MCPCLIOptions {
        var configPath: String?
        var serverName: String?
        var command: MCPCLICommand?
        var index = 1

        func nextValue(for flag: String) throws -> String {
            guard index < arguments.count else {
                throw MCPCLIError.missingValue(flag)
            }
            defer { index += 1 }
            return arguments[index]
        }

        while index < arguments.count {
            let arg = arguments[index]
            index += 1

            switch arg {
            case "--config", "-c":
                configPath = try nextValue(for: arg)
            case "--server", "-s":
                serverName = try nextValue(for: arg)
            case "list-servers":
                command = .listServers
            case "ping":
                command = .ping
            case "list-tools":
                command = .listTools
            case "list-resources":
                command = .listResources
            case "list-prompts":
                command = .listPrompts
            case "call-tool":
                let toolName = try nextValue(for: "call-tool <name>")
                command = .callTool(
                    name: toolName,
                    arguments: try parseToolArguments(arguments: arguments, index: &index)
                )
            case "read-resource":
                command = .readResource(uri: try nextValue(for: "read-resource <uri>"))
            case "get-prompt":
                let promptName = try nextValue(for: "get-prompt <name>")
                var promptArguments: [String: String] = [:]
                while index < arguments.count {
                    let option = arguments[index]
                    if !option.hasPrefix("--") {
                        break
                    }
                    index += 1
                    let key = String(option.dropFirst(2))
                    promptArguments[key] = try nextValue(for: option)
                }
                command = .getPrompt(name: promptName, arguments: promptArguments)
            case "--help", "-h":
                throw MCPCLIError.helpRequested
            default:
                throw MCPCLIError.unknownOption(arg)
            }
        }

        guard let command else {
            throw MCPCLIError.missingCommand
        }

        let configURL = AppConfigLoader.defaultConfigURL(explicitPath: configPath)
        return MCPCLIOptions(configURL: configURL, serverName: serverName, command: command)
    }

    public static func parseToolArguments(
        arguments: [String],
        index: inout Int
    ) throws -> [String: AnyCodableValue] {
        var toolArguments: [String: AnyCodableValue] = [:]

        while index < arguments.count {
            let option = arguments[index]
            if !option.hasPrefix("--") {
                break
            }
            index += 1
            let key = String(option.dropFirst(2))
            guard index < arguments.count else {
                throw MCPCLIError.missingValue(option)
            }
            let value = arguments[index]
            index += 1
            toolArguments[key] = .string(value)
        }

        if let argsJSON = toolArguments["args"]?.stringValue {
            _ = toolArguments.removeValue(forKey: "args")
            let data = Data(argsJSON.utf8)
            if let decoded = try? JSONDecoder().decode([String: AnyCodableValue].self, from: data) {
                for (key, value) in decoded {
                    toolArguments[key] = value
                }
            } else {
                throw MCPCLIError.invalidJSON(argsJSON)
            }
        }

        return toolArguments
    }

    public static let usageText = """
    mcpc — generic macOS MCP client (stdio, HTTP/SSE, WebSocket)

    Configuration:
      Reads config.toml from the current directory (or MCPC_CONFIG / --config).

    Usage:
      mcpc [options] list-servers
      mcpc [options] ping
      mcpc [options] list-tools
      mcpc [options] list-resources
      mcpc [options] list-prompts
      mcpc [options] call-tool <name> [--key value ...]
      mcpc [options] call-tool <name> --args '{"key":"value"}'
      mcpc [options] read-resource <uri>
      mcpc [options] get-prompt <name> [--key value ...]

    Options:
      -c, --config <path>   Config file (default: ./config.toml)
      -s, --server <name>   Server name from [[servers]] (default: client.default_server)
      -h, --help            Show this help

    Example:
      mcpc list-servers
      mcpc list-tools
      mcpc -s my-server call-tool search --query "hello"
    """
}

private extension AnyCodableValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}
