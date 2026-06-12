import AppKit
import MCPC
import MCPClientGUICore
import SwiftUI
import UniformTypeIdentifiers

struct ImportCursorServersSheet: View {
    @Bindable var model: MCPAppModel
    @Environment(\.dismiss) private var dismiss

    @State private var jsonText = ImportCursorServersSheet.placeholderJSON
    @State private var conflictPolicy: MergeConflictPolicy = .skip
    @State private var preview: CursorMCPImportPreview?
    @State private var parseError: String?
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Cursor MCP Servers")
                .font(.title2.bold())

            Text("Paste Cursor-style JSON (`mcpServers` from `.cursor/mcp.json` or Cursor settings) and add the servers to \(model.configURL.lastPathComponent).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Load JSON file…") { loadJSONFile() }
                Button("Load ~/.cursor/mcp.json") { loadCursorGlobalConfig() }
                Spacer()
                Button("Preview") { refreshPreview() }
                    .keyboardShortcut(.return, modifiers: .command)
            }

            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            Picker("If server name already exists", selection: $conflictPolicy) {
                ForEach(MergeConflictPolicy.allCases, id: \.self) { policy in
                    Text(policy.label).tag(policy)
                }
            }

            if let parseError {
                Text(parseError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let preview {
                GroupBox("Servers to import (\(preview.servers.count))") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(preview.servers, id: \.name) { server in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name).font(.headline)
                                    Text(importSummary(for: server))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !preview.warnings.isEmpty {
                                Divider()
                                ForEach(preview.warnings, id: \.self) { warning in
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(isImporting ? "Importing…" : "Add to config.toml") {
                    performImport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isImporting || jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 640, height: 620)
        .onAppear { refreshPreview() }
        .onChange(of: jsonText) { _, _ in
            preview = nil
            parseError = nil
        }
    }

    private func refreshPreview() {
        do {
            preview = try CursorMCPConfigImporter.parse(json: jsonText)
            parseError = nil
        } catch {
            preview = nil
            parseError = error.localizedDescription
        }
    }

    private func performImport() {
        isImporting = true
        defer { isImporting = false }

        do {
            let message = try model.importCursorServers(
                json: jsonText,
                conflictPolicy: conflictPolicy
            )
            model.statusMessage = message
            dismiss()
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func loadJSONFile() {
        let panel = NSOpenPanel()
        panel.title = "Select MCP JSON"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            jsonText = (try? String(contentsOf: url, encoding: .utf8)) ?? jsonText
            refreshPreview()
        }
    }

    private func loadCursorGlobalConfig() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/mcp.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            parseError = "No file at ~/.cursor/mcp.json"
            return
        }
        jsonText = (try? String(contentsOf: url, encoding: .utf8)) ?? jsonText
        refreshPreview()
    }

    private func importSummary(for server: ServerConfig) -> String {
        switch server.transport {
        case .stdio:
            var parts: [String] = []
            if let command = server.command {
                parts.append(command)
            }
            parts.append(contentsOf: server.args)
            if let cwd = server.workingDirectory {
                return "stdio · cwd \(cwd) · \(parts.joined(separator: " "))"
            }
            return "stdio · \(parts.joined(separator: " "))"
        case .sse, .streamableHTTP, .websocket:
            return "\(server.transport.configKey) · \(server.url ?? "")"
        }
    }

    private static let placeholderJSON = """
    {
      "mcpServers": {
        "example": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/project"]
        }
      }
    }
    """
}
