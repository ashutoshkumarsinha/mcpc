import Foundation
import MCPC
import MCPClient
import Observation

public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
}

public enum MCPTab: String, CaseIterable, Identifiable {
    case tools
    case resources
    case prompts

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tools: return "Tools"
        case .resources: return "Resources"
        case .prompts: return "Prompts"
        }
    }
}

@MainActor
@Observable
public final class MCPAppModel {
    public var configURL: URL
    public var config: AppConfig?
    public var selectedServerName: String?
    public var connectionState: ConnectionState = .disconnected
    public var connectedServerTitle: String?
    public var selectedTab: MCPTab = .tools

    public var tools: [MCPTool] = []
    public var resources: [MCPResource] = []
    public var prompts: [MCPPrompt] = []

    public var selectedToolName: String?
    public var toolArgumentsJSON: String = "{}"
    public var selectedResourceURI: String?
    public var selectedPromptName: String?
    public var promptArgumentsJSON: String = "{}"

    public var output: String = ""
    public var statusMessage: String?
    public var errorMessage: String?
    public var isBusy = false
    public var isImportCursorSheetPresented = false
    public var mcpJSONWatchStatus: String?

    private var session: MCPClientSession?
    private let mcpJSONWatcher = MCPJSONFileWatcher()
    private var isApplyingMCPJSONSync = false

    public init(loadDefaultConfiguration: Bool = true) {
        configURL = MCPAppModel.defaultConfigURL()
        if loadDefaultConfiguration {
            loadConfig()
        }
    }

    public static func defaultConfigURL() -> URL {
        MCPCUserDirectory.configURL()
    }

    public func importCursorServers(
        json: String,
        conflictPolicy: MergeConflictPolicy
    ) throws -> String {
        let base = config ?? AppConfig(
            app: AppSettings(),
            client: ClientSettings(),
            servers: []
        )

        let result = try CursorMCPSync.sync(
            json: json,
            into: base,
            managedServerNames: base.client.mcpJSONSyncedServers,
            onConflict: conflictPolicy
        )

        try AppConfigWriter.save(result.config, to: configURL)
        loadConfig(performInitialMCPSync: false)
        restartMCPJSONHotReloadIfNeeded(performInitialSync: false)

        var parts = ["Added \(result.added.count) server(s) to \(configURL.lastPathComponent)."]
        if !result.updated.isEmpty {
            parts.append("Updated \(result.updated.count).")
        }
        if !result.preview.warnings.isEmpty {
            parts.append("\(result.preview.warnings.count) warning(s).")
        }
        return parts.joined(separator: " ")
    }

    public func setMCPJSONHotReload(_ enabled: Bool) {
        guard var current = config else { return }
        current.client.mcpJSONHotReload = enabled
        do {
            try AppConfigWriter.save(current, to: configURL)
            loadConfig(performInitialMCPSync: enabled)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func loadConfig(from url: URL? = nil, performInitialMCPSync: Bool = true) {
        if let url {
            configURL = url
        }

        do {
            let loaded = try AppConfigLoader.load(from: configURL)
            config = loaded
            MCPCLogging.update(with: loaded.logging)
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

        restartMCPJSONHotReloadIfNeeded(performInitialSync: performInitialMCPSync)
    }

    public func restartMCPJSONHotReloadIfNeeded(performInitialSync: Bool) {
        mcpJSONWatcher.stop()

        guard let config, config.client.mcpJSONHotReload else {
            mcpJSONWatchStatus = nil
            return
        }

        let urls = CursorMCPPaths.resolvedWatchURLs(
            configuredPaths: config.client.mcpJSONWatchPaths,
            configURL: configURL
        )
        let labels = urls.map { url in
            if url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) {
                return "~" + url.path.dropFirst(FileManager.default.homeDirectoryForCurrentUser.path.count)
            }
            return url.lastPathComponent == "mcp.json"
                ? url.deletingLastPathComponent().lastPathComponent + "/mcp.json"
                : url.lastPathComponent
        }
        mcpJSONWatchStatus = labels.joined(separator: ", ")

        mcpJSONWatcher.setWatchURLs(urls) { [weak self] changedURL in
            Task { @MainActor in
                self?.applyMCPJSONFile(at: changedURL)
            }
        }

        if performInitialSync {
            Task { @MainActor in
                for url in urls where FileManager.default.fileExists(atPath: url.path) {
                    await self.applyMCPJSONFileSync(at: url)
                }
            }
        }
    }

    public func applyMCPJSONFile(at url: URL) {
        Task { @MainActor in
            await applyMCPJSONFileSync(at: url)
        }
    }

    private func applyMCPJSONFileSync(at url: URL) async {
        guard !isApplyingMCPJSONSync else { return }
        guard config?.client.mcpJSONHotReload == true else { return }
        guard let json = try? String(contentsOf: url, encoding: .utf8) else { return }
        guard let current = config else { return }

        isApplyingMCPJSONSync = true
        defer { isApplyingMCPJSONSync = false }

        do {
                let connectedName = selectedServerName
                let previousConnectedConfig = connectedName.flatMap { name in
                    current.servers.first(where: { $0.name == name })
                }

                let result = try CursorMCPSync.sync(
                    json: json,
                    into: current,
                    managedServerNames: current.client.mcpJSONSyncedServers,
                    onConflict: .replace
                )

                if result.added.isEmpty && result.updated.isEmpty && result.removed.isEmpty {
                    return
                }

                try AppConfigWriter.save(result.config, to: configURL)
                loadConfig(performInitialMCPSync: false)

                var parts: [String] = []
                if !result.added.isEmpty {
                    parts.append("added \(result.added.joined(separator: ", "))")
                }
                if !result.updated.isEmpty {
                    parts.append("updated \(result.updated.joined(separator: ", "))")
                }
                if !result.removed.isEmpty {
                    parts.append("removed \(result.removed.joined(separator: ", "))")
                }
                statusMessage = "Reloaded \(url.lastPathComponent): \(parts.joined(separator: "; "))"
                errorMessage = nil

                if let connectedName,
                   let previousConnectedConfig,
                   let nextConnectedConfig = config?.servers.first(where: { $0.name == connectedName }),
                   previousConnectedConfig != nextConnectedConfig,
                   connectionState == .connected {
                    await shutdown()
                    statusMessage? += " — reconnect to apply changes to \(connectedName)."
                }
        } catch {
            errorMessage = "mcp.json reload failed: \(error.localizedDescription)"
        }
    }

    public func connect() {
        guard connectionState != .connecting else { return }
        guard let serverName = selectedServerName, !serverName.isEmpty else {
            errorMessage = "Select a server to connect."
            return
        }

        Task {
            await shutdown()
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

    public func disconnect() {
        Task {
            await shutdown()
            statusMessage = "Disconnected"
        }
    }

    public func shutdown() async {
        await disconnectIfNeeded()
        connectionState = .disconnected
        connectedServerTitle = nil
        tools = []
        resources = []
        prompts = []
    }

    public func stopMCPJSONWatching() {
        mcpJSONWatcher.stop()
        mcpJSONWatchStatus = nil
    }

    public func refreshCatalog() async throws {
        guard let session else { return }
        tools = try await session.listTools()
        resources = try await session.listResources()
        prompts = try await session.listPrompts()
    }

    public func ping() {
        runOperation("Ping") {
            guard let session = self.session else { throw MCPGUIError.notConnected }
            let ok = try await session.ping()
            return ok ? "pong" : "no response"
        }
    }

    public func callSelectedTool() {
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

    public func readSelectedResource() {
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

    public func runSelectedPrompt() {
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

    public func selectTool(_ tool: MCPTool) {
        selectedToolName = tool.name
        toolArgumentsJSON = JSONArgumentsParser.template(for: tool.inputSchema)
    }

    public func selectPrompt(_ prompt: MCPPrompt) {
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

public enum MCPGUIError: LocalizedError {
    case notConnected
    case toolError(String)
    case invalidJSON(String)

    public var errorDescription: String? {
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

public enum JSONArgumentsParser {
    public static func decodeObject(_ json: String) throws -> [String: AnyCodableValue] {
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

    public static func decodeStringMap(_ json: String) throws -> [String: String] {
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

    public static func template(for schema: AnyCodableValue?) -> String {
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

    public static func template(for arguments: [MCPPromptArgument]?) -> String {
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

public enum MCPContentFormatter {
    public static func text(_ content: MCPContent) -> String {
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
