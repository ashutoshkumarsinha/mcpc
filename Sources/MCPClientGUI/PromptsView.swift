import SwiftUI
import MCPClient

struct PromptsView: View {
    @Bindable var model: MCPAppModel

    var body: some View {
        HSplitView {
            List(model.prompts, id: \.name, selection: $model.selectedPromptName) { prompt in
                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt.name)
                        .font(.headline)
                    if let description = prompt.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .tag(prompt.name)
            }
            .frame(minWidth: 240, idealWidth: 280)
            .onChange(of: model.selectedPromptName) { _, name in
                guard let name,
                      let prompt = model.prompts.first(where: { $0.name == name }) else { return }
                model.selectPrompt(prompt)
            }

            VStack(alignment: .leading, spacing: 12) {
                if let name = model.selectedPromptName {
                    Text(name)
                        .font(.title3.bold())

                    Text("Arguments (JSON)")
                        .font(.headline)

                    TextEditor(text: $model.promptArgumentsJSON)
                        .font(.system(.body, design: .monospaced))
                        .border(.quaternary)

                    Button("Get Prompt") {
                        model.runSelectedPrompt()
                    }
                    .disabled(model.connectionState != .connected || model.isBusy)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                } else {
                    ContentUnavailableView(
                        "Select a Prompt",
                        systemImage: "text.bubble",
                        description: Text("Connect to a server, then choose a prompt template.")
                    )
                }
            }
            .padding(16)
        }
    }
}
