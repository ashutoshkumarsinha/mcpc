import AppKit
import MCPC
import SwiftUI

struct ContentView: View {
    @Bindable var model: MCPAppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            VStack(spacing: 0) {
                ConnectionBar(model: model)
                Divider()
                TabView(selection: $model.selectedTab) {
                    ToolsView(model: model)
                        .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                        .tag(MCPTab.tools)

                    ResourcesView(model: model)
                        .tabItem { Label("Resources", systemImage: "doc.text") }
                        .tag(MCPTab.resources)

                    PromptsView(model: model)
                        .tabItem { Label("Prompts", systemImage: "text.bubble") }
                        .tag(MCPTab.prompts)
                }
                Divider()
                OutputPanel(model: model)
            }
        }
        .navigationTitle("MCPC")
    }
}

struct ConnectionBar: View {
    @Bindable var model: MCPAppModel

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(model.connectedServerTitle ?? "Not connected")
                    .font(.headline)
                if let status = model.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if model.connectionState == .connected {
                Button("Ping") { model.ping() }
                    .disabled(model.isBusy)
            }

            if model.connectionState == .connected {
                Button("Disconnect", role: .destructive) { model.disconnect() }
                    .disabled(model.isBusy)
            } else {
                Button(model.connectionState == .connecting ? "Connecting…" : "Connect") {
                    model.connect()
                }
                .disabled(model.connectionState == .connecting || model.isBusy || model.selectedServerName == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        let color: Color = switch model.connectionState {
        case .disconnected: .secondary
        case .connecting: .orange
        case .connected: .green
        }

        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .accessibilityLabel(connectionAccessibilityLabel)
    }

    private var connectionAccessibilityLabel: String {
        switch model.connectionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        }
    }
}

struct SidebarView: View {
    @Bindable var model: MCPAppModel

    var body: some View {
        List(selection: $model.selectedServerName) {
            Section("Config") {
                LabeledContent("File") {
                    Text(model.configURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("Choose config.toml…") {
                    pickConfigFile()
                }
                .buttonStyle(.link)
            }

            Section("Servers") {
                if let servers = model.config?.servers, !servers.isEmpty {
                    ForEach(servers, id: \.name) { server in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(server.name)
                                if server.name == model.config?.client.defaultServer {
                                    Text("default")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(endpointLabel(for: server))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(server.name as String?)
                    }
                } else {
                    Text("No servers in config")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 240)
        .navigationTitle("Servers")
    }

    private func endpointLabel(for server: ServerConfig) -> String {
        switch server.transport {
        case .stdio:
            var parts: [String] = []
            if let command = server.command {
                parts.append(command)
            }
            parts.append(contentsOf: server.args)
            return parts.joined(separator: " ")
        case .httpSSE, .websocket:
            return server.url ?? ""
        }
    }

    private func pickConfigFile() {
        let panel = NSOpenPanel()
        panel.title = "Select config.toml"
        panel.allowedContentTypes = [.data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            model.loadConfig(from: url)
        }
    }
}

struct OutputPanel: View {
    @Bindable var model: MCPAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    model.output = ""
                    model.errorMessage = nil
                }
                .disabled(model.output.isEmpty && model.errorMessage == nil)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            ScrollView {
                Text(model.output.isEmpty ? "Results appear here." : model.output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(minHeight: 140, maxHeight: 220)
        .background(.background.secondary)
    }
}
