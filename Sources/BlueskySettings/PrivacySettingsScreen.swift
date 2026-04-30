import SwiftUI
import BlueskyCore
import BlueskyKit

private final class PreviewPreferences: PreferencesStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    nonisolated func set<T: Codable & Sendable>(_ value: T, for key: String) throws {
        store[key] = try JSONEncoder().encode(value)
    }
    nonisolated func get<T: Codable & Sendable>(_ type: T.Type, for key: String) throws -> T? {
        guard let data = store[key] else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }
    nonisolated func remove(for key: String) { store.removeValue(forKey: key) }
}

private final class PreviewNoOpAccountStore: AccountStore, @unchecked Sendable {
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { [] }
    nonisolated func load(did: DID) async throws -> StoredAccount? { nil }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { nil }
}

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

// MARK: - Previews

#Preview("PrivacySettingsScreen — Light") {
    NavigationStack {
        PrivacySettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.light)
}

#Preview("PrivacySettingsScreen — Dark") {
    NavigationStack {
        PrivacySettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.dark)
}
