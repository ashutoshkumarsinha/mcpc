import Foundation // Data, JSONDecoder, command-line parsing helpers
import MCPClient // AnyCodableValue and MCP types used by CLI commands

public enum MCPCLICommand: Sendable { // Discriminated union of CLI subcommands; `Sendable` for concurrency safety
    case listServers // Print configured server names
    case ping // Health-check the connected server
    case listTools // List MCP tools
    case listResources // List MCP resources
    case listPrompts // List MCP prompts
    case callTool(name: String, arguments: [String: AnyCodableValue]) // Invoke a tool with JSON-capable args
    case readResource(uri: String) // Read a resource by URI
    case getPrompt(name: String, arguments: [String: String]) // Fetch a prompt template result
}

public struct MCPCLIOptions: Sendable { // Parsed CLI invocation options
    public let configURL: URL // Path to config.toml
    public let serverName: String? // Optional server override
    public let command: MCPCLICommand // Subcommand to execute

    public init(configURL: URL, serverName: String?, command: MCPCLICommand) {
        self.configURL = configURL // Store config file URL
        self.serverName = serverName // Store optional server name
        self.command = command // Store resolved subcommand
    }
}

public enum MCPCLIError: Error, CustomStringConvertible, Equatable { // CLI parsing/usage errors
    case missingValue(String) // Flag expected a value but argv ended
    case unknownOption(String) // Unrecognized argv token
    case missingCommand // No subcommand provided
    case invalidJSON(String) // --args JSON could not be decoded
    case helpRequested // User asked for help via -h/--help

    public var description: String { // Human-readable error string
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

public enum MCPCLI { // Argument parser and helpers for the mcpc binary
    public static func parseArguments(_ arguments: [String]) throws -> MCPCLIOptions { // Parse process argv (arguments[0] is program name)
        var configPath: String? // Optional --config path
        var serverName: String? // Optional --server name
        var command: MCPCLICommand? // Resolved subcommand, if any
        var index = 1 // Start after argv[0]

        func nextValue(for flag: String) throws -> String { // Local helper to read the next argv token
            guard index < arguments.count else { // `guard` ensures a value exists
                throw MCPCLIError.missingValue(flag)
            }
            defer { index += 1 } // `defer` runs on exit: advance index after returning value
            return arguments[index] // Return next token as the flag's value
        }

        while index < arguments.count { // Walk remaining argv tokens
            let arg = arguments[index] // Current token
            index += 1 // Consume token

            switch arg { // Dispatch on known flags/commands
            case "--config", "-c":
                configPath = try nextValue(for: arg) // Read config path after flag
            case "--server", "-s":
                serverName = try nextValue(for: arg) // Read server name after flag
            case "list-servers":
                command = .listServers // Set subcommand
            case "ping":
                command = .ping
            case "list-tools":
                command = .listTools
            case "list-resources":
                command = .listResources
            case "list-prompts":
                command = .listPrompts
            case "call-tool":
                let toolName = try nextValue(for: "call-tool <name>") // Tool name is next argv token
                command = .callTool(
                    name: toolName,
                    arguments: try parseToolArguments(arguments: arguments, index: &index) // `inout` lets helper consume more argv
                )
            case "read-resource":
                command = .readResource(uri: try nextValue(for: "read-resource <uri>"))
            case "get-prompt":
                let promptName = try nextValue(for: "get-prompt <name>") // Prompt name token
                var promptArguments: [String: String] = [:] // Collect --key value pairs
                while index < arguments.count { // Consume trailing --option value pairs
                    let option = arguments[index]
                    if !option.hasPrefix("--") { // Stop when next token is not an option
                        break
                    }
                    index += 1 // Consume option name
                    let key = String(option.dropFirst(2)) // Strip "--" prefix
                    promptArguments[key] = try nextValue(for: option) // Read option value
                }
                command = .getPrompt(name: promptName, arguments: promptArguments)
            case "--help", "-h":
                throw MCPCLIError.helpRequested // Signal caller to print usage
            default:
                throw MCPCLIError.unknownOption(arg) // Any other token is invalid
            }
        }

        guard let command else { // Require a subcommand after parsing flags
            throw MCPCLIError.missingCommand
        }

        let configURL = AppConfigLoader.defaultConfigURL(explicitPath: configPath) // Resolve config file location
        return MCPCLIOptions(configURL: configURL, serverName: serverName, command: command) // Bundle parsed options
    }

    public static func parseToolArguments( // Parse call-tool trailing --key value and optional --args JSON
        arguments: [String],
        index: inout Int // Current argv index updated in place
    ) throws -> [String: AnyCodableValue] {
        var toolArguments: [String: AnyCodableValue] = [:] // Accumulated tool arguments

        while index < arguments.count { // Read --key value pairs until non-option token
            let option = arguments[index]
            if !option.hasPrefix("--") {
                break
            }
            index += 1 // Consume option
            let key = String(option.dropFirst(2)) // Option name without "--"
            guard index < arguments.count else { // Each option needs a value
                throw MCPCLIError.missingValue(option)
            }
            let value = arguments[index] // Raw string value
            index += 1 // Consume value
            toolArguments[key] = .string(value) // Store as AnyCodableValue string
        }

        if let argsJSON = toolArguments["args"]?.stringValue { // Special --args '{"k":"v"}' merges JSON object
            _ = toolArguments.removeValue(forKey: "args") // Remove synthetic args key
            let data = Data(argsJSON.utf8) // UTF-8 JSON payload
            if let decoded = try? JSONDecoder().decode([String: AnyCodableValue].self, from: data) { // Decode JSON object
                for (key, value) in decoded { // Merge decoded keys into toolArguments
                    toolArguments[key] = value
                }
            } else {
                throw MCPCLIError.invalidJSON(argsJSON) // Bad JSON in --args
            }
        }

        return toolArguments // Final argument map for tools/call
    }

    // Multi-line help text printed by the CLI
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

private extension AnyCodableValue { // File-private helper extension
    var stringValue: String? { // Extract String case if present
        if case .string(let value) = self { // Pattern match enum associated value
            return value
        }
        return nil // Non-string values return nil
    }
}
