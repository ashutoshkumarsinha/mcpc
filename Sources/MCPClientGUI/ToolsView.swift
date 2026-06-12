import MCPClient
import MCPClientGUICore
import SwiftUI

struct ToolsView: View {
    @Bindable var model: MCPAppModel

    var body: some View {
        HSplitView {
            List(model.tools, id: \.name, selection: $model.selectedToolName) { tool in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.name)
                        .font(.headline)
                    if let description = tool.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .tag(tool.name)
            }
            .frame(minWidth: 240, idealWidth: 280)
            .onChange(of: model.selectedToolName) { _, name in
                guard let name,
                      let tool = model.tools.first(where: { $0.name == name }) else { return }
                model.selectTool(tool)
            }

            VStack(alignment: .leading, spacing: 12) {
                if let name = model.selectedToolName {
                    Text(name)
                        .font(.title3.bold())

                    Text("Arguments (JSON)")
                        .font(.headline)

                    TextEditor(text: $model.toolArgumentsJSON)
                        .font(.system(.body, design: .monospaced))
                        .border(.quaternary)

                    HStack {
                        Button("Run Tool") {
                            model.callSelectedTool()
                        }
                        .disabled(model.connectionState != .connected || model.isBusy)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])

                        Spacer()
                    }
                } else {
                    ContentUnavailableView(
                        "Select a Tool",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Connect to a server, then choose a tool from the list.")
                    )
                }
            }
            .padding(16)
        }
    }
}
