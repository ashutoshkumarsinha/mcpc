import AppKit // NSOpenPanel and macOS file dialogs
import MCPC // Cursor import/sync types and AppConfigWriter
import MCPClientGUICore // MCPAppModel
import SwiftUI // Sheet UI
import UniformTypeIdentifiers // UTType.json for open panel filtering

struct ImportCursorServersSheet: View { // Modal sheet for importing Cursor mcp.json servers
    @Bindable var model: MCPAppModel // Shared app state with two-way bindings
    @Environment(\.dismiss) private var dismiss // `@Environment` reads SwiftUI environment; dismiss closes the sheet

    @State private var jsonText = ImportCursorServersSheet.placeholderJSON // `@State` = view-owned mutable state
    @State private var conflictPolicy: MergeConflictPolicy = .skip // Default conflict policy
    @State private var preview: CursorMCPImportPreview? // Parsed preview; optional until Preview runs
    @State private var parseError: String? // Last parse/import error message
    @State private var isImporting = false // True while import is in flight

    var body: some View { // Sheet layout
        VStack(alignment: .leading, spacing: 16) { // Vertical stack, leading alignment
            Text("Import Cursor MCP Servers") // Sheet title
                .font(.title2.bold()) // Large bold title font

            Text("Paste Cursor-style JSON (`mcpServers` from `.cursor/mcp.json` or Cursor settings) and add the servers to \(model.configURL.lastPathComponent).") // Instructions
                .font(.callout) // Slightly smaller explanatory text
                .foregroundStyle(.secondary) // Muted color
                .fixedSize(horizontal: false, vertical: true) // Allow multi-line growth vertically

            HStack { // Row of helper buttons
                Button("Load JSON file…") { loadJSONFile() } // Open file picker
                Button("Load ~/.cursor/mcp.json") { loadCursorGlobalConfig() } // Load default Cursor config
                Spacer() // Push Preview button to trailing side
                Button("Preview") { refreshPreview() } // Parse JSON without saving
                    .keyboardShortcut(.return, modifiers: .command) // Cmd+Return shortcut
            }

            TextEditor(text: $jsonText) // Large editable JSON text area (`$` binding)
                .font(.system(.body, design: .monospaced)) // Monospace for JSON
                .frame(minHeight: 180) // Minimum editor height
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary)) // Border around editor

            Picker("If server name already exists", selection: $conflictPolicy) { // Conflict policy picker
                ForEach(MergeConflictPolicy.allCases, id: \.self) { policy in // `CaseIterable` supplies all policies
                    Text(policy.label).tag(policy) // Label + tag for selection
                }
            }

            if let parseError { // SwiftUI optional binding shorthand for non-nil parseError
                Text(parseError) // Show error in red caption
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled) // Allow copying error text
            }

            if let preview { // Show parsed server list when preview exists
                GroupBox("Servers to import (\(preview.servers.count))") { // Bordered group with count in title
                    ScrollView { // Scroll when many servers
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(preview.servers, id: \.name) { server in // One row per imported server
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name).font(.headline) // Server name
                                    Text(importSummary(for: server)) // Transport/command summary
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading) // Left-align within scroll width
                            }

                            if !preview.warnings.isEmpty { // Show non-fatal warnings
                                Divider() // Visual separator
                                ForEach(preview.warnings, id: \.self) { warning in // Each warning string
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundStyle(.orange) // Warning color
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140) // Cap preview scroll height
                }
            }

            Spacer(minLength: 0) // Flexible space pushes buttons to bottom

            HStack { // Footer action buttons
                Button("Cancel") { dismiss() } // Close sheet without importing
                Spacer()
                Button(isImporting ? "Importing…" : "Add to config.toml") { // Primary action label changes while importing
                    performImport() // Merge into config.toml via model
                }
                .keyboardShortcut(.defaultAction) // Return key triggers default action
                .disabled(isImporting || jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) // Disable when busy or empty
            }
        }
        .padding(24) // Outer padding
        .frame(width: 640, height: 620) // Fixed sheet size
        .onAppear { refreshPreview() } // Parse placeholder/sample JSON when sheet opens
        .onChange(of: jsonText) { _, _ in // Clear stale preview when user edits JSON
            preview = nil
            parseError = nil
        }
    }

    private func refreshPreview() { // Parse JSON into preview without writing config
        do {
            preview = try CursorMCPConfigImporter.parse(json: jsonText) // `try` propagates parse errors
            parseError = nil // Clear previous error on success
        } catch {
            preview = nil // Drop stale preview on failure
            parseError = error.localizedDescription // Show user-facing error
        }
    }

    private func performImport() { // Save imported servers into config.toml
        isImporting = true // Show importing state in button
        defer { isImporting = false } // `defer` resets flag when function exits

        do {
            let message = try model.importCursorServers( // Model parses, merges, saves, reloads
                json: jsonText,
                conflictPolicy: conflictPolicy
            )
            model.statusMessage = message // Surface success in main UI status line
            dismiss() // Close sheet on success
        } catch {
            parseError = error.localizedDescription // Keep sheet open and show error
        }
    }

    private func loadJSONFile() { // macOS open panel for arbitrary JSON file
        let panel = NSOpenPanel() // Standard file open dialog
        panel.title = "Select MCP JSON" // Dialog title
        panel.allowedContentTypes = [.json] // Restrict to JSON UTType
        panel.canChooseFiles = true // Allow picking files
        panel.canChooseDirectories = false // Disallow directories
        panel.allowsMultipleSelection = false // Single selection only

        if panel.runModal() == .OK, let url = panel.url { // User chose a file
            jsonText = (try? String(contentsOf: url, encoding: .utf8)) ?? jsonText // Load UTF-8 text or keep old text
            refreshPreview() // Re-parse loaded JSON
        }
    }

    private func loadCursorGlobalConfig() { // Load ~/.cursor/mcp.json if it exists
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/mcp.json") // Standard Cursor global MCP path
        guard FileManager.default.fileExists(atPath: url.path) else { // `guard` early exit when missing
            parseError = "No file at ~/.cursor/mcp.json"
            return
        }
        jsonText = (try? String(contentsOf: url, encoding: .utf8)) ?? jsonText // Read file contents
        refreshPreview() // Parse loaded config
    }

    private func importSummary(for server: ServerConfig) -> String { // One-line summary for preview list
        switch server.transport {
        case .stdio:
            var parts: [String] = [] // Command + args pieces
            if let command = server.command {
                parts.append(command)
            }
            parts.append(contentsOf: server.args) // Append all CLI args
            if let cwd = server.workingDirectory {
                return "stdio · cwd \(cwd) · \(parts.joined(separator: " "))" // Include cwd when set
            }
            return "stdio · \(parts.joined(separator: " "))" // Command line only
        case .sse, .streamableHTTP, .websocket:
            return "\(server.transport.configKey) · \(server.url ?? "")" // Remote transport + URL
        }
    }

    // Sample JSON shown when sheet opens
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
