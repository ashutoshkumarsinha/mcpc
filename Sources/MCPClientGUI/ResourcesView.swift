import MCPClient // MCP resource types from the client library
import MCPClientGUICore // Shared app model and helpers
import SwiftUI // Apple's declarative UI framework

struct ResourcesView: View { // `struct` + `View` = a SwiftUI screen component
    @Bindable var model: MCPAppModel // `@Bindable` lets child views read/write observable model state

    var body: some View { // `body` is required by View; describes the UI tree
        HSplitView { // Horizontal split: list on the left, detail on the right
            List(model.resources, id: \.uri, selection: $model.selectedResourceURI) { resource in // List bound to resources; `$` = two-way binding
                VStack(alignment: .leading, spacing: 4) { // Vertical stack, left-aligned, 4pt gap
                    Text(resource.name) // Show the resource display name
                        .font(.headline) // Larger, bold-ish font
                    Text(resource.uri) // Show the resource URI below the name
                        .font(.caption) // Smaller caption font
                        .foregroundStyle(.secondary) // Muted secondary color
                        .lineLimit(2) // Wrap/truncate after two lines
                }
                .tag(resource.uri) // Tag rows so List selection matches URI strings
            }
            .frame(minWidth: 240, idealWidth: 300) // Size the list column

            VStack(alignment: .leading, spacing: 12) { // Detail panel on the right
                if let uri = model.selectedResourceURI { // `if let` unwraps optional selected URI
                    Text(uri) // Show the selected URI as a title
                        .font(.title3.bold()) // Title-sized bold text
                        .textSelection(.enabled) // Allow copying the URI

                    if let resource = model.resources.first(where: { $0.uri == uri }), // Find matching resource in the list
                       let description = resource.description, !description.isEmpty { // Also require a non-empty description
                        Text(description) // Show the resource description
                            .foregroundStyle(.secondary) // Muted text color
                    }

                    Button("Read Resource") { // Button triggers a read on the server
                        model.readSelectedResource() // Call into the app model
                    }
                    .disabled(model.connectionState != .connected || model.isBusy) // Disable when offline or busy
                    .keyboardShortcut(.return, modifiers: [.command, .shift]) // Cmd+Shift+Return shortcut
                } else { // No resource selected yet
                    ContentUnavailableView( // Placeholder when nothing is selected
                        "Select a Resource",
                        systemImage: "doc.text",
                        description: Text("Connect to a server, then choose a resource URI.")
                    )
                }

                Spacer() // Push content to the top of the detail column
            }
            .padding(16) // 16pt padding around the detail panel
        }
    }
}
