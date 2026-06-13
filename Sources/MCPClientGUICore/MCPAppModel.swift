import Foundation // FileManager, URL, JSONEncoder/Decoder
import MCPC // AppConfig, sync/import, session, formatters
import MCPClient // MCP protocol types (tools, resources, prompts)
import Observation // `@Observable` macro for Swift observation

public enum ConnectionState: Equatable { // GUI connection lifecycle state
    case disconnected // Not connected
    case connecting // Connect in progress
    case connected // Active MCP session
}

public enum MCPTab: String, CaseIterable, Identifiable { // Main tab identifiers; `Identifiable` for SwiftUI lists
    case tools
    case resources
    case prompts

    public var id: String { rawValue } // `id` required by Identifiable; uses enum raw string

    public var title: String { // Human-readable tab title
        switch self {
        case .tools: return "Tools"
        case .resources: return "Resources"
        case .prompts: return "Prompts"
        }
    }
}

@MainActor // All UI mutations must happen on main actor
@Observable // `@Observable` generates observation tracking for SwiftUI `@Bindable`
public final class MCPAppModel { // Central observable state for GUI and shared logic
    public var configURL: URL // Active config.toml path
    public var config: AppConfig? // Loaded config; nil when load failed
    public var selectedServerName: String? // Sidebar-selected server
    public var connectionState: ConnectionState = .disconnected // Current connection state
    public var connectedServerTitle: String? // Remote server name/version when connected
    public var selectedTab: MCPTab = .tools // Active main tab

    public var tools: [MCPTool] = [] // Cached tools/list from server
    public var resources: [MCPResource] = [] // Cached resources/list
    public var prompts: [MCPPrompt] = [] // Cached prompts/list

    public var selectedToolName: String? // Selected tool in Tools tab
    public var toolArgumentsJSON: String = "{}" // Editable JSON args for selected tool
    public var selectedResourceURI: String? // Selected resource URI
    public var selectedPromptName: String? // Selected prompt name
    public var promptArgumentsJSON: String = "{}" // Editable JSON args for selected prompt

    public var output: String = "" // Latest operation output text
    public var statusMessage: String? // Non-error status line for UI
    public var errorMessage: String? // Latest error message for UI
    public var isBusy = false // True while an async GUI operation runs
    public var isImportCursorSheetPresented = false // Controls import sheet presentation
    public var mcpJSONWatchStatus: String? // Human-readable hot-reload watch summary

    private var session: MCPClientSession? // Active MCP session actor instance
    private let mcpJSONWatcher = MCPJSONFileWatcher() // Filesystem watcher for mcp.json hot reload
    private var isApplyingMCPJSONSync = false // Reentrancy guard for hot-reload apply

    public init(loadDefaultConfiguration: Bool = true) { // Create model; optionally load config immediately
        configURL = MCPAppModel.defaultConfigURL() // Resolve default config path
        if loadDefaultConfiguration {
            loadConfig() // Load config on startup
        }
    }

    public static func defaultConfigURL() -> URL { // Default config location helper
        MCPCUserDirectory.configURL()
    }

    public func importCursorServers( // Import Cursor JSON into config.toml (used by sheet)
        json: String,
        conflictPolicy: MergeConflictPolicy
    ) throws -> String {
        let base = config ?? AppConfig( // Use loaded config or empty scaffold when none loaded
            app: AppSettings(),
            client: ClientSettings(),
            servers: []
        )

        let result = try CursorMCPSync.sync( // Parse + merge + compute added/updated/removed
            json: json,
            into: base,
            managedServerNames: base.client.mcpJSONSyncedServers,
            onConflict: conflictPolicy
        )

        try AppConfigWriter.save(result.config, to: configURL) // Persist merged config to disk
        loadConfig(performInitialMCPSync: false) // Reload in-memory config without immediate re-sync loop
        restartMCPJSONHotReloadIfNeeded(performInitialSync: false) // Refresh watcher with new settings

        var parts = ["Added \(result.added.count) server(s) to \(configURL.lastPathComponent)."] // Success message pieces
        if !result.updated.isEmpty {
            parts.append("Updated \(result.updated.count).")
        }
        if !result.preview.warnings.isEmpty {
            parts.append("\(result.preview.warnings.count) warning(s).")
        }
        return parts.joined(separator: " ") // Single status string for UI
    }

    public func setMCPJSONHotReload(_ enabled: Bool) { // Toggle hot reload and persist to config
        guard var current = config else { return } // Need loaded config to mutate
        current.client.mcpJSONHotReload = enabled // Update flag
        do {
            try AppConfigWriter.save(current, to: configURL) // Write config.toml
            loadConfig(performInitialMCPSync: enabled) // Reload; optionally sync immediately when enabling
        } catch {
            errorMessage = String(describing: error) // Surface write/load failure
        }
    }

    public func loadConfig(from url: URL? = nil, performInitialMCPSync: Bool = true) { // Load or reload config.toml
        if let url {
            configURL = url // Switch active config path when provided
        }

        do {
            let loaded = try AppConfigLoader.load(from: configURL) // Parse and validate config file
            config = loaded // Store loaded config
            MCPCLogging.update(with: loaded.logging) // Apply logging settings globally
            errorMessage = nil // Clear prior load error
            statusMessage = "Loaded \(loaded.servers.count) server(s) from \(configURL.lastPathComponent)"

            if selectedServerName == nil || !loaded.servers.contains(where: { $0.name == selectedServerName }) { // Fix stale selection
                selectedServerName = loaded.client.defaultServer.isEmpty
                    ? loaded.servers.first?.name // First server when no default
                    : loaded.client.defaultServer // Otherwise default_server
            }
        } catch {
            config = nil // Clear config on failure
            errorMessage = String(describing: error)
        }

        restartMCPJSONHotReloadIfNeeded(performInitialSync: performInitialMCPSync) // Start/stop watcher based on new config
    }

    public func restartMCPJSONHotReloadIfNeeded(performInitialSync: Bool) { // Configure filesystem watching for mcp.json
        mcpJSONWatcher.stop() // Always stop previous watches first

        guard let config, config.client.mcpJSONHotReload else { // Hot reload disabled or no config
            mcpJSONWatchStatus = nil
            return
        }

        let urls = CursorMCPPaths.resolvedWatchURLs( // Expand configured/default watch paths
            configuredPaths: config.client.mcpJSONWatchPaths,
            configURL: configURL
        )
        let labels = urls.map { url in // Build short human-readable labels for UI
            if url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) {
                return "~" + url.path.dropFirst(FileManager.default.homeDirectoryForCurrentUser.path.count)
            }
            return url.lastPathComponent == "mcp.json"
                ? url.deletingLastPathComponent().lastPathComponent + "/mcp.json"
                : url.lastPathComponent
        }
        mcpJSONWatchStatus = labels.joined(separator: ", ") // Show watched paths in sidebar

        mcpJSONWatcher.setWatchURLs(urls) { [weak self] changedURL in // Register debounced file change callback
            Task { @MainActor in // Hop back to main actor for UI/model updates
                self?.applyMCPJSONFile(at: changedURL)
            }
        }

        if performInitialSync { // Optionally sync existing files once at startup/enable
            Task { @MainActor in
                for url in urls where FileManager.default.fileExists(atPath: url.path) { // Only existing files
                    await self.applyMCPJSONFileSync(at: url)
                }
            }
        }
    }

    public func applyMCPJSONFile(at url: URL) { // Public entry when watcher fires
        Task { @MainActor in
            await applyMCPJSONFileSync(at: url) // Run sync work on main actor
        }
    }

    private func applyMCPJSONFileSync(at url: URL) async { // Merge changed mcp.json into config.toml
        guard !isApplyingMCPJSONSync else { return } // Prevent nested/overlapping sync
        guard config?.client.mcpJSONHotReload == true else { return } // Feature must still be enabled
        guard let json = try? String(contentsOf: url, encoding: .utf8) else { return } // Read file; ignore read failures
        guard let current = config else { return } // Need in-memory config snapshot

        isApplyingMCPJSONSync = true // Enter critical section
        defer { isApplyingMCPJSONSync = false } // Always clear flag on exit

        do {
                let connectedName = selectedServerName // Remember currently selected server name
                let previousConnectedConfig = connectedName.flatMap { name in // Snapshot connected server's config before merge
                    current.servers.first(where: { $0.name == name })
                }

                let result = try CursorMCPSync.sync( // Hot reload always uses .replace policy
                    json: json,
                    into: current,
                    managedServerNames: current.client.mcpJSONSyncedServers,
                    onConflict: .replace
                )

                if result.added.isEmpty && result.updated.isEmpty && result.removed.isEmpty { // No effective changes
                    return
                }

                try AppConfigWriter.save(result.config, to: configURL) // Persist merged config
                loadConfig(performInitialMCPSync: false) // Reload without triggering another initial sync pass

                var parts: [String] = [] // Build human-readable change summary
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
                   previousConnectedConfig != nextConnectedConfig, // Connected server's config changed
                   connectionState == .connected {
                    await shutdown() // Drop stale live connection using old settings
                    statusMessage? += " — reconnect to apply changes to \(connectedName)." // Hint user to reconnect
                }
        } catch {
            errorMessage = "mcp.json reload failed: \(error.localizedDescription)"
        }
    }

    public func connect() { // Start MCP connection to selected server
        guard connectionState != .connecting else { return } // Ignore double-connect
        guard let serverName = selectedServerName, !serverName.isEmpty else { // Require selected server
            errorMessage = "Select a server to connect."
            return
        }

        Task { // Run async connect flow off the synchronous button handler
            await shutdown() // Ensure previous session is closed
            connectionState = .connecting
            isBusy = true
            errorMessage = nil
            statusMessage = "Connecting to \(serverName)…"

            do {
                let newSession = try await MCPClientSession.connect( // Load config + initialize MCP session
                    configURL: configURL,
                    serverName: serverName
                )
                session = newSession // Store live session
                connectionState = .connected

                if let info = await newSession.serverInfo { // Use remote initialize metadata when available
                    connectedServerTitle = "\(info.serverInfo.name) v\(info.serverInfo.version)"
                    statusMessage = "Connected to \(connectedServerTitle ?? serverName)"
                } else {
                    connectedServerTitle = serverName
                    statusMessage = "Connected to \(serverName)"
                }

                try await refreshCatalog() // Populate tools/resources/prompts lists
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

    public func disconnect() { // User-requested disconnect
        Task {
            await shutdown()
            statusMessage = "Disconnected"
        }
    }

    public func shutdown() async { // Full local teardown of connection + cached catalog
        await disconnectIfNeeded() // Close underlying MCP session
        connectionState = .disconnected
        connectedServerTitle = nil
        tools = []
        resources = []
        prompts = []
    }

    public func stopMCPJSONWatching() { // Stop hot-reload watcher (e.g. on app exit)
        mcpJSONWatcher.stop()
        mcpJSONWatchStatus = nil
    }

    public func refreshCatalog() async throws { // Refresh tools/resources/prompts from server
        guard let session else { return } // No-op when not connected
        tools = try await session.listTools()
        resources = try await session.listResources()
        prompts = try await session.listPrompts()
    }

    public func ping() { // Ping RPC wrapped in generic operation runner
        runOperation("Ping") {
            guard let session = self.session else { throw MCPGUIError.notConnected }
            let ok = try await session.ping()
            return ok ? "pong" : "no response"
        }
    }

    public func callSelectedTool() { // Invoke currently selected tool with JSON args
        guard let name = selectedToolName else {
            errorMessage = "Select a tool first."
            return
        }

        runOperation("Tool \(name)") {
            guard let session = self.session else { throw MCPGUIError.notConnected }
            let arguments = try JSONArgumentsParser.decodeObject(self.toolArgumentsJSON) // Parse JSON editor text
            let result = try await session.callTool(name: name, arguments: arguments)
            if result.isError == true { // MCP tool result flagged as error
                throw MCPGUIError.toolError(MCPToolContentFormatter.text(from: result))
            }
            return MCPToolContentFormatter.text(from: result) // Format success output
        }
    }

    public func readSelectedResource() { // Read currently selected resource URI
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

    public func runSelectedPrompt() { // Run currently selected prompt with JSON args
        guard let name = selectedPromptName else {
            errorMessage = "Select a prompt first."
            return
        }

        runOperation("Prompt \(name)") {
            guard let session = self.session else { throw MCPGUIError.notConnected }
            let decoded = try JSONArgumentsParser.decodeStringMap(self.promptArgumentsJSON) // Prompt args are [String:String]
            let result = try await session.getPrompt(name: name, arguments: decoded)
            return result.messages.map { message in // Format each returned prompt message
                let body = MCPContentFormatter.text(message.content)
                return "\(message.role): \(body)"
            }
            .joined(separator: "\n\n")
        }
    }

    public func selectTool(_ tool: MCPTool) { // Update selection and argument template for a tool
        selectedToolName = tool.name
        toolArgumentsJSON = JSONArgumentsParser.template(for: tool.inputSchema) // Pre-fill JSON from input schema
    }

    public func selectPrompt(_ prompt: MCPPrompt) { // Update selection and argument template for a prompt
        selectedPromptName = prompt.name
        promptArgumentsJSON = JSONArgumentsParser.template(for: prompt.arguments)
    }

    private func runOperation(_ title: String, _ work: @escaping () async throws -> String) { // Shared async operation wrapper for GUI actions
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "Running \(title)…"

            do {
                let result = try await work() // Run caller-provided async work closure
                output = result // Show result in output panel
                statusMessage = "Finished \(title)"
            } catch {
                errorMessage = String(describing: error)
                statusMessage = nil
            }

            isBusy = false
        }
    }

    private func disconnectIfNeeded() async { // Close session if one exists
        if let session {
            try? await session.disconnect() // Best-effort disconnect
        }
        session = nil
    }
}

public enum MCPGUIError: LocalizedError { // GUI-specific errors with localized descriptions
    case notConnected
    case toolError(String)
    case invalidJSON(String)

    public var errorDescription: String? { // `LocalizedError` message for SwiftUI alerts/status
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

public enum JSONArgumentsParser { // Helpers for JSON argument editing in the GUI/CLI
    public static func decodeObject(_ json: String) throws -> [String: AnyCodableValue] { // Parse JSON object for tool args
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines) // Ignore surrounding whitespace
        let payload = trimmed.isEmpty ? "{}" : trimmed // Empty editor => empty object
        guard let data = payload.data(using: .utf8) else {
            throw MCPGUIError.invalidJSON("Arguments are not valid UTF-8.")
        }
        do {
            return try JSONDecoder().decode([String: AnyCodableValue].self, from: data) // Decode typed dictionary
        } catch {
            throw MCPGUIError.invalidJSON("Invalid JSON: \(error.localizedDescription)")
        }
    }

    public static func decodeStringMap(_ json: String) throws -> [String: String] { // Parse JSON object into string map for prompts
        let object = try decodeObject(json) // Reuse object decoder
        var result: [String: String] = [:]
        for (key, value) in object { // Coerce each AnyCodableValue to String
            switch value {
            case .string(let string):
                result[key] = string
            case .integer(let int):
                result[key] = String(int)
            case .number(let number):
                result[key] = String(number)
            case .bool(let bool):
                result[key] = bool ? "true" : "false"
            default: // Arrays/objects encoded as JSON text
                let data = try JSONEncoder().encode(value)
                result[key] = String(data: data, encoding: .utf8) ?? ""
            }
        }
        return result
    }

    public static func template(for schema: AnyCodableValue?) -> String { // Build default JSON args from tool input JSON Schema
        guard let schema, case .object(let root) = schema, // Root must be JSON object
              case .object(let props) = root["properties"] else { // Must contain properties object
            return "{}"
        }

        var template: [String: AnyCodableValue] = [:]
        for key in props.keys.sorted() { // Stable key order in generated JSON
            template[key] = defaultValue(for: props[key]) // Default per property schema
        }
        return prettyJSON(template) ?? "{}"
    }

    public static func template(for arguments: [MCPPromptArgument]?) -> String { // Build empty-string template for prompt arguments
        guard let arguments, !arguments.isEmpty else { return "{}" }
        var template: [String: String] = [:]
        for argument in arguments {
            template[argument.name] = "" // Empty string placeholder per argument name
        }
        if let data = try? JSONEncoder().encode(template),
           let text = String(data: data, encoding: .utf8) {
            return prettyFormatJSON(text) ?? "{}"
        }
        return "{}"
    }

    private static func defaultValue(for schema: AnyCodableValue?) -> AnyCodableValue { // Pick placeholder value from JSON Schema type field
        guard let schema else { return .string("") }
        if case .object(let fields) = schema, let type = fields["type"] { // Read "type" field when schema is object
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
        return .string("") // Fallback placeholder
    }

    private static func prettyJSON(_ object: [String: AnyCodableValue]) -> String? { // Encode object then pretty-print
        guard let data = try? JSONEncoder().encode(object) else { return nil }
        return prettyFormatJSON(String(decoding: data, as: UTF8.self))
    }

    private static func prettyFormatJSON(_ json: String) -> String? { // Pretty-print arbitrary JSON string
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            return json // Return original when pretty-print fails
        }
        return text
    }
}

public enum MCPContentFormatter { // Format MCP message content for display
    public static func text(_ content: MCPContent) -> String { // Convert one MCPContent union to text
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
