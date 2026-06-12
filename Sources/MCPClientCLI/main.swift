import Foundation
import MCPC
import MCPClient

@main
struct MCPClientCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let options = try parseArguments(CommandLine.arguments)

        let client = try await MCPConfiguredClient.connect(
            configURL: options.configURL,
            serverName: options.serverName
        )
        defer {
            Task {
                try? await client.disconnect()
            }
        }

        if let info = await client.serverInfo {
            print("Connected to \(info.serverInfo.name) v\(info.serverInfo.version)")
        }

        switch options.command {
        case .listTools:
            let tools = try await client.listTools()
            if tools.isEmpty {
                print("No tools registered.")
                return
            }
            for tool in tools {
                let description = tool.description ?? ""
                print("- \(tool.name)\(description.isEmpty ? "" : ": \(description)")")
            }

        case .listResources:
            let resources = try await client.listResources()
            if resources.isEmpty {
                print("No resources registered.")
                return
            }
            for resource in resources {
                print("- \(resource.name) (\(resource.uri))")
            }

        case .listPrompts:
            let prompts = try await client.listPrompts()
            if prompts.isEmpty {
                print("No prompts registered.")
                return
            }
            for prompt in prompts {
                print("- \(prompt.name)")
            }

        case .callTool(let name, let arguments):
            let result = try await client.callTool(name: name, arguments: arguments)
            let text = MCPToolContentFormatter.text(from: result)
            if result.isError == true {
                fputs(text.isEmpty ? "tool returned an error\n" : "\(text)\n", stderr)
                exit(2)
            }
            print(text)
        }
    }
}

private enum CLICommand {
    case listTools
    case listResources
    case listPrompts
    case callTool(name: String, arguments: [String: AnyCodableValue])
}

private struct CLIOptions {
    let configURL: URL
    let serverName: String
    let command: CLICommand
}

private enum CLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownOption(String)
    case missingCommand
    case invalidJSON(String)

    var description: String {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .unknownOption(let option):
            return "Unknown option: \(option)"
        case .missingCommand:
            return "Missing command. Use list-tools, list-resources, list-prompts, or call-tool."
        case .invalidJSON(let value):
            return "Invalid JSON for --args: \(value)"
        }
    }
}

private func parseArguments(_ arguments: [String]) throws -> CLIOptions {
    var configPath = "mcp_client_config.json"
    var serverName = "3gpp-researcher-suite"
    var command: CLICommand?
    var index = 1

    func nextValue(for flag: String) throws -> String {
        guard index < arguments.count else {
            throw CLIError.missingValue(flag)
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
        case "list-tools":
            command = .listTools
        case "list-resources":
            command = .listResources
        case "list-prompts":
            command = .listPrompts
        case "call-tool":
            let toolName = try nextValue(for: "call-tool <name>")
            var toolArguments: [String: AnyCodableValue] = [:]

            while index < arguments.count {
                let option = arguments[index]
                if !option.hasPrefix("--") {
                    break
                }
                index += 1
                let key = String(option.dropFirst(2))
                let value = try nextValue(for: option)
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
                    throw CLIError.invalidJSON(argsJSON)
                }
            }

            command = .callTool(name: toolName, arguments: toolArguments)
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw CLIError.unknownOption(arg)
        }
    }

    guard let command else {
        throw CLIError.missingCommand
    }

    let configURL = URL(fileURLWithPath: configPath).standardizedFileURL
    return CLIOptions(configURL: configURL, serverName: serverName, command: command)
}

private func printUsage() {
    let text = """
    mcpc — Swift MCP stdio client for Cursor-style server configs

    Usage:
      mcpc [options] list-tools
      mcpc [options] list-resources
      mcpc [options] list-prompts
      mcpc [options] call-tool <name> [--key value ...]
      mcpc [options] call-tool <name> --args '{"query":"...","release":"Rel-16"}'

    Options:
      -c, --config <path>   MCP config JSON (default: mcp_client_config.json)
      -s, --server <name>   Server key in mcpServers (default: 3gpp-researcher-suite)
      -h, --help            Show this help

    Example:
      mcpc list-tools
      mcpc call-tool research_3gpp_specifications \\
        --query "What triggers RRC resume?" \\
        --release Rel-16 \\
        --specification 38.331
    """
    print(text)
}

private extension AnyCodableValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}
