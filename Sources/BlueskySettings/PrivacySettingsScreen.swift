import SwiftUI
import BlueskyCore
import BlueskyKit

struct PrivacySettingsScreen: View {
    var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Text("Activity privacy and interaction restrictions are managed via your Bluesky profile settings.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } header: {
                Text("Activity Privacy")
            }

            Section {
                Text("App passwords allow third-party apps to access your account without sharing your main password. Manage them at bsky.app/settings/app-passwords.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } header: {
                Text("App Passwords")
            }
        }
        .navigationTitle("Privacy & Security")
    }
}
