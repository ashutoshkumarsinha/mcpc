import MCPClient
import MCPClientGUICore
import SwiftUI

struct ResourcesView: View {
    @Bindable var model: MCPAppModel

    var body: some View {
        HSplitView {
            List(model.resources, id: \.uri, selection: $model.selectedResourceURI) { resource in
                VStack(alignment: .leading, spacing: 4) {
                    Text(resource.name)
                        .font(.headline)
                    Text(resource.uri)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .tag(resource.uri)
            }
            .frame(minWidth: 240, idealWidth: 300)

            VStack(alignment: .leading, spacing: 12) {
                if let uri = model.selectedResourceURI {
                    Text(uri)
                        .font(.title3.bold())
                        .textSelection(.enabled)

                    if let resource = model.resources.first(where: { $0.uri == uri }),
                       let description = resource.description, !description.isEmpty {
                        Text(description)
                            .foregroundStyle(.secondary)
                    }

                    Button("Read Resource") {
                        model.readSelectedResource()
                    }
                    .disabled(model.connectionState != .connected || model.isBusy)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                } else {
                    ContentUnavailableView(
                        "Select a Resource",
                        systemImage: "doc.text",
                        description: Text("Connect to a server, then choose a resource URI.")
                    )
                }

                Spacer()
            }
            .padding(16)
        }
    }
}
