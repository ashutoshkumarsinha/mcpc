import AppKit
import MCPC
import MCPClientGUICore
import SwiftUI

@main
struct MCPClientGUIApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = MCPAppModel()
    @State private var isAboutPresented = false

    init() {
        MCPCLogging.bootstrap(with: .default)
        if let config = try? AppConfigLoader.load(from: AppConfigLoader.defaultConfigURL()) {
            MCPCLogging.update(with: config.logging)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 600)
                .sheet(isPresented: $isAboutPresented) {
                    AboutView()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        Task { await model.shutdown() }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.stopMCPJSONWatching()
                    Task { await model.shutdown() }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppMetadata.displayName)") {
                    isAboutPresented = true
                }
            }
        }
    }
}
