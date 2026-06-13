import Foundation
import MCPC      // config, CLI parser, logging, session types.
import MCPClient   // MCP protocol types (MCPContent, formatters).

// @main = this struct's static main() is the program entry point.
@main
struct MCPClientCLI {
    // async = can await network/subprocess work without blocking threads.
    static func main() async {
        do {
            try await run()
        } catch let error as MCPCLIError {
            // User ran `mcpc --help` — print usage and exit successfully.
            if case .helpRequested = error {
                print(MCPCLI.usageText)
                return
            }
            fputs("error: \(error)\n", stderr)
            exit(1) // non-zero exit tells shell/scripts the command failed
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        // Parse argv into command, server name, config path, tool args, etc.
        let options = try MCPCLI.parseArguments(CommandLine.arguments)
        MCPCLogging.bootstrap(with: .default)
        // Load config.toml from path resolved by MCPCLI (see AppConfigLoader).
        let config = try AppConfigLoader.load(from: options.configURL)
        MCPCLogging.update(with: config.logging)

        // list-servers is special: no MCP connection needed.
        if case .listServers = options.command {
            if config.servers.isEmpty {
                print("No servers configured.")
                return
            }
            for server in config.servers {
                let endpoint: String
                switch server.transport {
                case .stdio:
                    // Show command + args as the human-readable endpoint.
                    var parts: [String] = []
                    if let command = server.command {
                        parts.append(command)
                    }
                    parts.append(contentsOf: server.args)
                    endpoint = parts.joined(separator: " ")
                case .sse, .streamableHTTP, .websocket:
                    endpoint = server.url ?? ""
                }
                let marker = server.name == config.client.defaultServer ? " (default)" : ""
                print("- \(server.name)\(marker): \(server.transport.configKey) → \(endpoint)")
            }
            return
        }

        // Open connection to one server from config.
        let session = try await MCPClientSession(
            config: config,
            serverName: try config.resolvedServerName(options.serverName)
        )

        if let info = await session.serverInfo {
            print("Connected to \(info.serverInfo.name) v\(info.serverInfo.version)")
        }

        do {
            switch options.command {
            case .listServers:
                break // handled above

            case .ping:
                let ok = try await session.ping()
                print(ok ? "pong" : "no response")

            case .listTools:
                let tools = try await session.listTools()
                if tools.isEmpty {
                    print("No tools registered.")
                } else {
                    for tool in tools {
                        let description = tool.description ?? ""
                        print("- \(tool.name)\(description.isEmpty ? "" : ": \(description)")")
                    }
                }

            case .listResources:
                let resources = try await session.listResources()
                if resources.isEmpty {
                    print("No resources registered.")
                } else {
                    for resource in resources {
                        print("- \(resource.name) (\(resource.uri))")
                    }
                }

            case .listPrompts:
                let prompts = try await session.listPrompts()
                if prompts.isEmpty {
                    print("No prompts registered.")
                } else {
                    for prompt in prompts {
                        print("- \(prompt.name)")
                    }
                }

            case .callTool(let name, let arguments):
                let result = try await session.callTool(name: name, arguments: arguments)
                let text = MCPToolContentFormatter.text(from: result)
                if result.isError == true {
                    try await session.disconnect()
                    fputs(text.isEmpty ? "tool returned an error\n" : "\(text)\n", stderr)
                    exit(2) // distinct exit code for tool-level errors
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
        } catch {
            try? await session.disconnect() // best-effort cleanup before rethrowing
            throw error
        }

        try await session.disconnect()
    }
}

// Turn MCP prompt message content into printable text for the terminal.
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
