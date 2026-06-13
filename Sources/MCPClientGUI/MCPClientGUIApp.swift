import AppKit   // macOS app APIs (NSApplication, notifications).
import MCPC     // config, logging, ~/.mcpc setup.
import MCPClientGUICore // MCPAppModel — shared GUI state machine.
import SwiftUI  // declarative UI.

// @main marks this struct as the program entry point (replaces main.swift).
@main
struct MCPClientGUIApp: App {
    // scenePhase tracks app lifecycle: active, inactive, background.
    @Environment(\.scenePhase) private var scenePhase
    // @State owns the app model; SwiftUI recreates views when model publishes changes.
    @State private var model = MCPAppModel()
    // Controls whether the About sheet is visible.
    @State private var isAboutPresented = false

    // init runs once when the app launches, before any window appears.
    init() {
        // Create ~/.mcpc/, seed config.toml and mcpc.log on first run.
        _ = try? MCPCUserDirectory.prepareForFirstLaunch()
        // Path we will try to load for logging settings.
        let configURL = MCPCUserDirectory.configURL()
        // Install swift-log handlers with safe defaults.
        MCPCLogging.bootstrap(with: .default)
        // If config parses, apply [logging] from file (e.g. file destination).
        if let config = try? AppConfigLoader.load(from: configURL) {
            MCPCLogging.update(with: config.logging)
        }
    }

    // body describes the app's scenes (windows) and menu commands.
    var body: some Scene {
        // Primary window group — can open one or more windows.
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 600)
                // Modal About dialog bound to isAboutPresented.
                .sheet(isPresented: $isAboutPresented) {
                    AboutView()
                }
                // When user switches away from app, disconnect MCP cleanly.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        Task { await model.shutdown() }
                    }
                }
                // When user quits from Dock/menu, stop file watcher and disconnect.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.stopMCPJSONWatching()
                    Task { await model.shutdown() }
                }
        }
        // Customize menu bar items.
        .commands {
            // Remove default "New" menu item (not applicable).
            CommandGroup(replacing: .newItem) {}
            // Replace standard "About" with our custom sheet.
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppMetadata.displayName)") {
                    isAboutPresented = true
                }
            }
        }
    }
}
