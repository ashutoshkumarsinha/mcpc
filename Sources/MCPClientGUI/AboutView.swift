// Import SwiftUI — Apple's declarative UI framework for macOS/iOS.
import SwiftUI

// struct conforming to View = a piece of UI that SwiftUI can draw on screen.
struct AboutView: View {
    // @Environment reads system-provided values; dismiss closes the current sheet.
    @Environment(\.dismiss) private var dismiss

    // body is required by View; it describes what appears in the About window.
    var body: some View {
        // VStack = vertical stack; children are laid out top to bottom with 16pt spacing.
        VStack(spacing: 16) {
            // SF Symbol icon for the app (network nodes graphic).
            Image(systemName: "network")
                .font(.system(size: 48))           // large icon size
                .foregroundStyle(.tint)            // use accent color
                .symbolRenderingMode(.hierarchical) // multi-tone symbol style

            // App name from shared metadata.
            Text(AppMetadata.displayName)
                .font(.title2.weight(.semibold))   // prominent heading font

            // Version read from ~/.mcpc/config.toml when available.
            Text("Version \(AppMetadata.version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)         // muted gray text

            // Developer credit line.
            Text(AppMetadata.developerCredit)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // OK button dismisses the sheet.
            Button("OK") {
                dismiss() // call the environment dismiss action
            }
            .keyboardShortcut(.defaultAction) // Return key triggers OK
            .padding(.top, 4)                 // small gap above button
        }
        .padding(28)        // inner margin around all content
        .frame(width: 300)  // fixed dialog width
    }
}
