import AppKit // NSOpenPanel for choosing config.toml
import MCPC // ServerConfig and app metadata types
import MCPClientGUICore // MCPAppModel and shared GUI types
import SwiftUI // Declarative UI framework

struct ContentView: View { // Root view for the MCP client GUI
    @Bindable var model: MCPAppModel // `@Bindable` exposes observable model to child views

    var body: some View { // Main window layout
        NavigationSplitView { // macOS-style sidebar + detail split view
            SidebarView(model: model) // Left sidebar: config + servers
        } detail: { // Right side: connection bar, tabs, output
            VStack(spacing: 0) { // Vertical stack with no extra spacing between major sections
                ConnectionBar(model: model) // Top connection status and buttons
                Divider() // Horizontal rule
                TabView(selection: $model.selectedTab) { // Tabbed tools/resources/prompts (`$` binds selected tab)
                    ToolsView(model: model) // Tools tab content
                        .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") } // Tab label + icon
                        .tag(MCPTab.tools) // Tag identifies this tab in selection binding

                    ResourcesView(model: model) // Resources tab
                        .tabItem { Label("Resources", systemImage: "doc.text") }
                        .tag(MCPTab.resources)

                    PromptsView(model: model) // Prompts tab
                        .tabItem { Label("Prompts", systemImage: "text.bubble") }
                        .tag(MCPTab.prompts)
                }
                Divider() // Separator above output panel
                OutputPanel(model: model) // Bottom output/error area
            }
        }
        .navigationTitle(AppMetadata.displayName) // Window navigation title from app metadata
        .sheet(isPresented: $model.isImportCursorSheetPresented) { // Present modal sheet when flag is true
            ImportCursorServersSheet(model: model) // Cursor JSON import UI
        }
    }
}

struct ConnectionBar: View { // Top bar showing connection state and actions
    @Bindable var model: MCPAppModel // Shared observable model

    var body: some View { // Horizontal connection controls
        HStack(spacing: 12) { // Row with 12pt spacing
            statusIndicator // Colored dot reflecting connection state

            VStack(alignment: .leading, spacing: 2) { // Server title + status message stack
                Text(model.connectedServerTitle ?? "Not connected") // Remote server name or placeholder
                    .font(.headline)
                if let status = model.statusMessage { // Optional status line under title
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer() // Push action buttons to the trailing edge

            if model.connectionState == .connected { // Ping only when connected
                Button("Ping") { model.ping() } // Health-check RPC
                    .disabled(model.isBusy) // Disable during other operations
            }

            if model.connectionState == .connected { // Disconnect when connected
                Button("Disconnect", role: .destructive) { model.disconnect() } // `role: .destructive` styles as dangerous action
                    .disabled(model.isBusy)
            } else { // Connect button when disconnected/connecting
                Button(model.connectionState == .connecting ? "Connecting…" : "Connect") { // Label reflects in-progress state
                    model.connect() // Start connection flow
                }
                .disabled(model.connectionState == .connecting || model.isBusy || model.selectedServerName == nil) // Require idle + selected server
                .keyboardShortcut(.return, modifiers: .command) // Cmd+Return to connect
            }

            if model.isBusy { // Spinner while async work runs
                ProgressView() // Indeterminate progress indicator
                    .controlSize(.small) // Compact size for toolbar
            }
        }
        .padding(.horizontal, 16) // Horizontal padding
        .padding(.vertical, 10) // Vertical padding
        .background(.bar) // Toolbar-like background material
    }

    @ViewBuilder // `@ViewBuilder` allows conditional view branches in a computed property
    private var statusIndicator: some View { // Colored connection status dot
        let color: Color = switch model.connectionState { // `switch` expression assigns Color
        case .disconnected: .secondary // Gray when offline
        case .connecting: .orange // Orange while connecting
        case .connected: .green // Green when connected
        }

        Circle() // Small filled circle
            .fill(color) // Fill with state color
            .frame(width: 10, height: 10) // Fixed dot size
            .accessibilityLabel(connectionAccessibilityLabel) // VoiceOver label
    }

    private var connectionAccessibilityLabel: String { // Text label for accessibility
        switch model.connectionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        }
    }
}

private func configPathLabel(_ url: URL) -> String { // Shorten home directory paths for display
    let home = FileManager.default.homeDirectoryForCurrentUser.path // Current user's home path
    if url.path.hasPrefix(home) { // If config is under home directory
        return "~" + url.path.dropFirst(home.count) // Replace home prefix with ~
    }
    return url.path // Otherwise show full path
}

struct SidebarView: View { // Left sidebar listing config info and servers
    @Bindable var model: MCPAppModel

    var body: some View {
        List(selection: $model.selectedServerName) { // Selectable server list bound to model
            Section("Config") { // First sidebar section
                LabeledContent("File") { // Label/value row for config file path
                    Text(configPathLabel(model.configURL))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1) // Single line
                        .truncationMode(.middle) // Truncate middle of long paths
                }

                Button("Choose config.toml…") { // Open panel to pick another config file
                    pickConfigFile()
                }
                .buttonStyle(.link) // Link-style button appearance

                Button("Import Cursor MCP JSON…") { // Open import sheet
                    model.isImportCursorSheetPresented = true // Toggle sheet presentation flag
                }
                .buttonStyle(.link)

                Toggle( // Two-way toggle for hot reload feature
                    "Hot reload mcp.json",
                    isOn: Binding( // Custom Binding bridges optional config field
                        get: { model.config?.client.mcpJSONHotReload ?? false }, // Read from loaded config
                        set: { model.setMCPJSONHotReload($0) } // Write via model helper (persists to disk)
                    )
                )
                .font(.caption)

                if let watchStatus = model.mcpJSONWatchStatus { // Show watched paths when hot reload active
                    Text("Watching \(watchStatus)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Section("Servers") { // Server list section
                if let servers = model.config?.servers, !servers.isEmpty { // When config has servers
                    ForEach(servers, id: \.name) { server in // One row per server
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(server.name) // Server name
                                if server.name == model.config?.client.defaultServer { // Badge default server
                                    Text("default")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary)
                                        .clipShape(Capsule()) // Pill-shaped badge
                                }
                            }
                            Text(endpointLabel(for: server)) // Command or URL summary
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(server.name as String?) // List selection tag
                    }
                } else { // Empty config/server list
                    Text("No servers in config")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar) // macOS sidebar list style
        .frame(minWidth: 240) // Minimum sidebar width
        .navigationTitle("Servers") // Sidebar navigation title
    }

    private func endpointLabel(for server: ServerConfig) -> String { // Human-readable endpoint summary
        switch server.transport {
        case .stdio:
            var parts: [String] = []
            if let command = server.command {
                parts.append(command)
            }
            parts.append(contentsOf: server.args)
            return parts.joined(separator: " ") // "command arg1 arg2"
        case .sse, .streamableHTTP, .websocket:
            return server.url ?? "" // Remote URL string
        }
    }

    private func pickConfigFile() { // macOS open panel for config.toml
        let panel = NSOpenPanel()
        panel.title = "Select config.toml"
        panel.allowedContentTypes = [.data] // Generic data type (TOML has no dedicated UTType here)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url { // User picked a file
            model.loadConfig(from: url) // Reload app state from new config path
        }
    }
}

struct OutputPanel: View { // Bottom panel for command output and errors
    @Bindable var model: MCPAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output")
                    .font(.headline)
                Spacer()
                Button("Clear") { // Clear output and error state
                    model.output = ""
                    model.errorMessage = nil
                }
                .disabled(model.output.isEmpty && model.errorMessage == nil) // Disable when already empty
            }

            if let error = model.errorMessage { // Show latest error above output
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            ScrollView { // Scrollable monospace output area
                Text(model.output.isEmpty ? "Results appear here." : model.output) // Placeholder or results
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading) // Left-align text in scroll view
                    .textSelection(.enabled) // Allow copying output
            }
        }
        .padding(16)
        .frame(minHeight: 140, maxHeight: 220) // Constrain output panel height
        .background(.background.secondary) // Subtle secondary background
    }
}
