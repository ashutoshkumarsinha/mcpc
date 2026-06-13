import MCPClient // MCP tool types
import MCPClientGUICore // Shared app model
import SwiftUI // UI framework

struct ToolsView: View { // SwiftUI view for listing and calling MCP tools
    @Bindable var model: MCPAppModel // Observable model with two-way bindings

    var body: some View { // View content builder
        HSplitView { // Split list and detail panes
            List(model.tools, id: \.name, selection: $model.selectedToolName) { tool in // Tool list with selection
                VStack(alignment: .leading, spacing: 4) { // Name + description stack
                    Text(tool.name) // Tool name
                        .font(.headline) // Prominent font
                    if let description = tool.description, !description.isEmpty { // Optional tool description
                        Text(description) // Show description text
                            .font(.caption) // Small font
                            .foregroundStyle(.secondary) // Muted color
                            .lineLimit(3) // Cap at three lines
                    }
                }
                .tag(tool.name) // Selection tag matches tool name
            }
            .frame(minWidth: 240, idealWidth: 280) // List width constraints
            .onChange(of: model.selectedToolName) { _, name in // When selection changes, update argument template
                guard let name, // Require a selected name
                      let tool = model.tools.first(where: { $0.name == name }) else { return } // Look up tool record
                model.selectTool(tool) // Populate JSON args from tool input schema
            }

            VStack(alignment: .leading, spacing: 12) { // Detail column
                if let name = model.selectedToolName { // Show tool UI when one is selected
                    Text(name) // Tool title
                        .font(.title3.bold()) // Bold title

                    Text("Arguments (JSON)") // Label for JSON editor
                        .font(.headline) // Heading style

                    TextEditor(text: $model.toolArgumentsJSON) // Edit tool arguments as JSON
                        .font(.system(.body, design: .monospaced)) // Monospace for JSON
                        .border(.quaternary) // Subtle border

                    HStack { // Horizontal row for the action button
                        Button("Run Tool") { // Invoke the tool on the server
                            model.callSelectedTool() // App model performs the RPC call
                        }
                        .disabled(model.connectionState != .connected || model.isBusy) // Disable if not ready
                        .keyboardShortcut(.return, modifiers: [.command, .shift]) // Shortcut to run

                        Spacer() // Push button to the leading edge
                    }
                } else { // No tool selected
                    ContentUnavailableView( // Placeholder instructions
                        "Select a Tool",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Connect to a server, then choose a tool from the list.")
                    )
                }
            }
            .padding(16) // Inner padding
        }
    }
}
