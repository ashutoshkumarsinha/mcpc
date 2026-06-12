import SwiftUI

@main
struct MCPClientGUIApp: App {
    @State private var model = MCPAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
