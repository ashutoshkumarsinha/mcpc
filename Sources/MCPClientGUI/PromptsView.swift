import MCPClient // MCP prompt types
import MCPClientGUICore // Shared observable app model
import SwiftUI // Declarative UI framework

struct PromptsView: View { // SwiftUI view for browsing and running MCP prompts
    @Bindable var model: MCPAppModel // Two-way binding to the shared app state

    var body: some View { // Defines the view hierarchy
        HSplitView { // Left list + right detail layout
            List(model.prompts, id: \.name, selection: $model.selectedPromptName) { prompt in // List prompts by name with selection binding
                VStack(alignment: .leading, spacing: 4) { // Stack name and description vertically
                    Text(prompt.name) // Prompt template name
                        .font(.headline) // Emphasize the name
                    if let description = prompt.description, !description.isEmpty { // Optional description line
                        Text(description) // Show prompt description when present
                            .font(.caption) // Smaller secondary text
                            .foregroundStyle(.secondary) // Muted color
                            .lineLimit(3) // Limit to three lines
                    }
                }
                .tag(prompt.name) // Row tag for List selection
            }
            .frame(minWidth: 240, idealWidth: 280) // List column width
            .onChange(of: model.selectedPromptName) { _, name in // React when user picks a different prompt
                guard let name, // `guard` exits early unless we have a name
                      let prompt = model.prompts.first(where: { $0.name == name }) else { return } // Find the prompt object
                model.selectPrompt(prompt) // Fill argument JSON template for that prompt
            }

            VStack(alignment: .leading, spacing: 12) { // Right-hand detail column
                if let name = model.selectedPromptName { // Show editor when a prompt is selected
                    Text(name) // Selected prompt title
                        .font(.title3.bold()) // Bold title style

                    Text("Arguments (JSON)") // Label above the JSON editor
                        .font(.headline) // Section heading font

                    TextEditor(text: $model.promptArgumentsJSON) // Editable JSON arguments (`$` = binding)
                        .font(.system(.body, design: .monospaced)) // Monospace font for JSON
                        .border(.quaternary) // Light border around the editor

                    Button("Get Prompt") { // Run the selected prompt on the server
                        model.runSelectedPrompt() // Delegate to app model
                    }
                    .disabled(model.connectionState != .connected || model.isBusy) // Require connection and idle state
                    .keyboardShortcut(.return, modifiers: [.command, .shift]) // Keyboard shortcut
                } else { // Nothing selected
                    ContentUnavailableView( // Empty-state placeholder
                        "Select a Prompt",
                        systemImage: "text.bubble",
                        description: Text("Connect to a server, then choose a prompt template.")
                    )
                }
            }
            .padding(16) // Padding around detail content
        }
    }
}
