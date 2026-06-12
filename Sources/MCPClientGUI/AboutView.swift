import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text(AppMetadata.displayName)
                .font(.title2.weight(.semibold))

            Text("Version \(AppMetadata.version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(AppMetadata.developerCredit)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("OK") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 300)
    }
}
