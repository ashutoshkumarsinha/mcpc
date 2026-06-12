import Foundation
import MCPC
import MCPClient
import Observation

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
}

enum MCPTab: String, CaseIterable, Identifiable {
    case tools
    case resources
    case prompts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tools: return "Tools"
        case .resources: return "Resources"
        case .prompts: return "Prompts"
        }
    }
}

@MainActor
@Observable
final class MCPAppModel {
    var configURL: URL
    var config: AppConfig?
    var selectedServerName: String?
    var connectionState: ConnectionState = .disconnected
    var connectedServerTitle: String?
    var selectedTab: MCPTab = .tools

    var tools: [MCPTool] = []
    var resources: [MCPResource] = []
    var prompts: [MCPPrompt] = []

    var selectedToolName: String?
    var toolArgumentsJSON: String = "{}"
    var selectedResourceURI: String?
    var selectedPromptName: String?
    var promptArgumentsJSON: String = "{}"

    var output: String = ""
    var statusMessage: String?
    var errorMessage: String?
    var isBusy = false

    private var session: MCPClientSession?

    init() {
        configURL = MCPAppModel.defaultConfigURL()
        loadConfig()
    }

    static func defaultConfigURL() -> URL {
        AppConfigLoader.defaultConfigURL()
    }

    func loadConfig(from url: URL? = nil) {
        if let url {
            configURL = url
        }

        do {
            let loaded = try AppConfigLoader.load(from: configURL)
            config = loaded
            errorMessage = nil
            statusMessage = "Loaded \(loaded.servers.count) server(s) from \(configURL.lastPathComponent)"

            if selectedServerName == nil || !loaded.servers.contains(where: { $0.name == selectedServerName }) {
                selectedServerName = loaded.client.defaultServer.isEmpty
                    ? loaded.servers.first?.name
                    : loaded.client.defaultServer
            }
        } catch {
            config = nil
            errorMessage = String(describing: error)
        }
    }

    func connect() {
        guard connectionState != .connecting else { return }
        guard let serverName = selectedServerName, !serverName.isEmpty else {
            errorMessage = "Select a server to connect."
            return
        }

        Task {
            await disconnectIfNeeded()
            connectionState = .connecting
            isBusy = true
            errorMessage = nil
            statusMessage = "Connecting to \(serverName)…"

            do {
                let newSession = try await MCPClientSession.connect(
                    configURL: configURL,
                    serverName: serverName
                )
                session = newSession
                connectionState = .connected

                if let info = await newSession.serverInfo {
                    connectedServerTitle = "\(info.serverInfo.name) v\(info.serverInfo.version)"
                    statusMessage = "Connected to \(connectedServerTitle ?? serverName)"
                } else {
                    connectedServerTitle = serverName
                    statusMessage = "Connected to \(serverName)"
                }

                try await refreshCatalog()
            } catch {
                session = nil
                connectionState = .disconnected
                connectedServerTitle = nil
                errorMessage = String(describing: error)
                statusMessage = nil
            }

            isBusy = false
        }
    }

    func disconnect() {
        Task {
            await disconnectIfNeeded()
            connectionState = .disconnected
            connectedServerTitle = nil
            tools = []
            resources = []
            prompts = []
            statusMessage = "Disconnected"
        }
    }

    func refreshCatalog() async throws {
        guard let session else { return }
        tools = try await session.listTools()
        resources = try await session.listResources()
        prompts = try await session.listPrompts()
    }

    func ping() {
        runOperation("Ping") {
            guard let session = self.session else { throw MCPGUIError.notConnected }
            let ok = try await session.ping()
            return ok ? "pong" : "no response"
        }
    }

    func callSelectedTool() {
        guard let name = selectedToolName else {
            errorMessage = "Select a tool first."
            return
        }

        runOperation("Tool \(name)") {
            guard let session = self.session else { throw MCPGUIError.notConnected }
            let arguments = try JSONArgumentsParser.decodeObject(self.toolArgumentsJSON)
            let result = try await session.callTool(name: name, arguments: arguments)
            if result.isError == true {
                throw MCPGUIError.toolError(MCPToolContentFormatter.text(from: result))
            }
            return MCPToolContentFormatter.text(from: result)
        }
    }

    func readSelectedResource() {
        guard let uri = selectedResourceURI else {
            errorMessage = "Select a resource first."
            return
        }

        runOperation("Resource \(uri)") {
            guard let session = self.session else { throw MCPGUIError.notConnected }
            let contents = try await session.readResource(uri: uri)
            return MCPResourceContentFormatter.text(from: contents)
        }
    }

    func runSelectedPrompt() {
        guard let name = selectedPromptName else {
            errorMessage = "Select a prompt first."
            return
        }

        runOperation("Prompt \(name)") {
            guard let session = self.session else { throw MCPGUIError.notConnected }
            let decoded = try JSONArgumentsParser.decodeStringMap(self.promptArgumentsJSON)
            let result = try await session.getPrompt(name: name, arguments: decoded)
            return result.messages.map { message in
                let body = MCPContentFormatter.text(message.content)
                return "\(message.role): \(body)"
            }
            .joined(separator: "\n\n")
        }
    }

    func selectTool(_ tool: MCPTool) {
        selectedToolName = tool.name
        toolArgumentsJSON = JSONArgumentsParser.template(for: tool.inputSchema)
    }

    func selectPrompt(_ prompt: MCPPrompt) {
        selectedPromptName = prompt.name
        promptArgumentsJSON = JSONArgumentsParser.template(for: prompt.arguments)
    }

    private func runOperation(_ title: String, _ work: @escaping () async throws -> String) {
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "Running \(title)…"

            do {
                let result = try await work()
                output = result
                statusMessage = "Finished \(title)"
            } catch {
                errorMessage = String(describing: error)
                statusMessage = nil
            }

            isBusy = false
        }
    }

    private func disconnectIfNeeded() async {
        if let session {
            try? await session.disconnect()
        }
        session = nil
    }
}

enum MCPGUIError: LocalizedError {
    case notConnected
    case toolError(String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to a server."
        case .toolError(let message):
            return message
        case .invalidJSON(let message):
            return message
        }
    }
}

enum JSONArgumentsParser {
    static func decodeObject(_ json: String) throws -> [String: AnyCodableValue] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = trimmed.isEmpty ? "{}" : trimmed
        guard let data = payload.data(using: .utf8) else {
            throw MCPGUIError.invalidJSON("Arguments are not valid UTF-8.")
        }
        do {
            return try JSONDecoder().decode([String: AnyCodableValue].self, from: data)
        } catch {
            throw MCPGUIError.invalidJSON("Invalid JSON: \(error.localizedDescription)")
        }
    }

    static func decodeStringMap(_ json: String) throws -> [String: String] {
        let object = try decodeObject(json)
        var result: [String: String] = [:]
        for (key, value) in object {
            switch value {
            case .string(let string):
                result[key] = string
            case .integer(let int):
                result[key] = String(int)
            case .number(let number):
                result[key] = String(number)
            case .bool(let bool):
                result[key] = bool ? "true" : "false"
            default:
                let data = try JSONEncoder().encode(value)
                result[key] = String(data: data, encoding: .utf8) ?? ""
            }
        }
        return result
    }

    static func template(for schema: AnyCodableValue?) -> String {
        guard let schema, case .object(let root) = schema,
              case .object(let props) = root["properties"] else {
            return "{}"
        }

        var template: [String: AnyCodableValue] = [:]
        for key in props.keys.sorted() {
            template[key] = defaultValue(for: props[key])
        }
        return prettyJSON(template) ?? "{}"
    }

    static func template(for arguments: [MCPPromptArgument]?) -> String {
        guard let arguments, !arguments.isEmpty else { return "{}" }
        var template: [String: String] = [:]
        for argument in arguments {
            template[argument.name] = ""
        }
        if let data = try? JSONEncoder().encode(template),
           let text = String(data: data, encoding: .utf8) {
            return prettyFormatJSON(text) ?? "{}"
        }
        return "{}"
    }

    private static func defaultValue(for schema: AnyCodableValue?) -> AnyCodableValue {
        guard let schema else { return .string("") }
        if case .object(let fields) = schema, let type = fields["type"] {
            switch type {
            case .string("string"):
                return .string("")
            case .string("integer"), .string("number"):
                return .integer(0)
            case .string("boolean"):
                return .bool(false)
            case .string("array"):
                return .array([])
            case .string("object"):
                return .object([:])
            default:
                break
            }
        }
        return .string("")
    }

    private static func prettyJSON(_ object: [String: AnyCodableValue]) -> String? {
        guard let data = try? JSONEncoder().encode(object) else { return nil }
        return prettyFormatJSON(String(decoding: data, as: UTF8.self))
    }

    private static func prettyFormatJSON(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            return json
        }
        return text
    }
}

enum MCPContentFormatter {
    static func text(_ content: MCPContent) -> String {
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
}
