import Foundation
import MCPC
import MCPClient

@main
struct MCPClientCLI {
    static func main() async {
        do {
            try await run()
        } catch let error as MCPCLIError {
            if case .helpRequested = error {
                print(MCPCLI.usageText)
                return
            }
            fputs("error: \(error)\n", stderr)
            exit(1)
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let options = try MCPCLI.parseArguments(CommandLine.arguments)
        MCPCLogging.bootstrap(with: .default)
        let config = try AppConfigLoader.load(from: options.configURL)
        MCPCLogging.update(with: config.logging)

        if case .listServers = options.command {
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
                case .sse, .streamableHTTP, .websocket:
                    endpoint = server.url ?? ""
                }
                let marker = server.name == config.client.defaultServer ? " (default)" : ""
                print("- \(server.name)\(marker): \(server.transport.configKey) → \(endpoint)")
            }
            return
        }

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
                break

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
        } catch {
            try? await session.disconnect()
            throw error
        }

        try await session.disconnect()
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
