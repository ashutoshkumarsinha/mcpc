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

        if case .listServers = options.command {
            let config = try AppConfigLoader.load(from: options.configURL)
            if config.servers.isEmpty {
                print("No servers configured.")
                return
            }
            for server in config.servers {
                let endpoint: String
                switch server.transport {
                case .stdio:
                    var parts: [String] = []
                    if let command = server.command {
                        parts.append(command)
                    }
                    parts.append(contentsOf: server.args)
                    endpoint = parts.joined(separator: " ")
                case .httpSSE, .websocket:
                    endpoint = server.url ?? ""
                }
                let marker = server.name == config.client.defaultServer ? " (default)" : ""
                print("- \(server.name)\(marker): \(server.transport.rawValue) → \(endpoint)")
            }
            return
        }

        let session = try await MCPClientSession.connect(
            configURL: options.configURL,
            serverName: options.serverName
        )
        defer {
            Task {
                try? await session.disconnect()
            }
        }

        if let info = await session.serverInfo {
            print("Connected to \(info.serverInfo.name) v\(info.serverInfo.version)")
        }

        switch options.command {
        case .listServers:
            break

        case .ping:
            let ok = try await session.ping()
            print(ok ? "pong" : "no response")

        case .listTools:
            let tools = try await session.listTools()
            if tools.isEmpty {
                print("No tools registered.")
                return
            }
            for tool in tools {
                let description = tool.description ?? ""
                print("- \(tool.name)\(description.isEmpty ? "" : ": \(description)")")
            }

        case .listResources:
            let resources = try await session.listResources()
            if resources.isEmpty {
                print("No resources registered.")
                return
            }
            for resource in resources {
                print("- \(resource.name) (\(resource.uri))")
            }

        case .listPrompts:
            let prompts = try await session.listPrompts()
            if prompts.isEmpty {
                print("No prompts registered.")
                return
            }
            for prompt in prompts {
                print("- \(prompt.name)")
            }

        case .callTool(let name, let arguments):
            let result = try await session.callTool(name: name, arguments: arguments)
            let text = MCPToolContentFormatter.text(from: result)
            if result.isError == true {
                fputs(text.isEmpty ? "tool returned an error\n" : "\(text)\n", stderr)
                exit(2)
            }
            print(text)

        case .readResource(let uri):
            let contents = try await session.readResource(uri: uri)
            print(MCPResourceContentFormatter.text(from: contents))

        case .getPrompt(let name, let arguments):
            let result = try await session.getPrompt(name: name, arguments: arguments)
            for message in result.messages {
                let body = promptMessageText(message.content)
                print("\(message.role): \(body)")
            }
        }
    }
}

private func promptMessageText(_ content: MCPContent) -> String {
    switch content {
    case .text(let text, _):
        return text
    case .image(_, let mimeType, _):
        return "[image: \(mimeType)]"
    case .resource(let contents, _):
        switch contents {
        case .text(_, _, let text):
            return text
        case .blob:
            return "[resource blob]"
        }
    }
}

private enum CLICommand {
    case listServers
    case ping
    case listTools
    case listResources
    case listPrompts
    case callTool(name: String, arguments: [String: AnyCodableValue])
    case readResource(uri: String)
    case getPrompt(name: String, arguments: [String: String])
}

private struct CLIOptions {
    let configURL: URL
    let serverName: String?
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
            return "Missing command. Run mcpc --help for usage."
        case .invalidJSON(let value):
            return "Invalid JSON for --args: \(value)"
        }
    }
}

private func parseArguments(_ arguments: [String]) throws -> CLIOptions {
    var configPath: String?
    var serverName: String?
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
            printUsage()
            exit(0)
        default:
            throw CLIError.unknownOption(arg)
        }
    }

    guard let command else {
        throw CLIError.missingCommand
    }

    let configURL = AppConfigLoader.defaultConfigURL(explicitPath: configPath)
    return CLIOptions(configURL: configURL, serverName: serverName, command: command)
}

private func parseToolArguments(
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
            throw CLIError.missingValue(option)
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
            throw CLIError.invalidJSON(argsJSON)
        }
    }

    return toolArguments
}

private func printUsage() {
    let text = """
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
