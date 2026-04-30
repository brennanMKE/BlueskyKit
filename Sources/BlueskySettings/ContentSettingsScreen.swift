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

struct ContentSettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Autoplay Videos", isOn: $viewModel.autoplayVideo)
                Toggle("Load External Embeds", isOn: $viewModel.externalEmbeds)
            } header: {
                Text("Media")
            } footer: {
                Text("External embeds include link cards and media from third-party sites. Disabling reduces data usage and improves privacy.")
            }
        }
        .navigationTitle("Content & Media")
        .onChange(of: viewModel.autoplayVideo) { _, _ in viewModel.save() }
        .onChange(of: viewModel.externalEmbeds) { _, _ in viewModel.save() }
    }
}

// MARK: - Previews

#Preview("ContentSettingsScreen — Light") {
    NavigationStack {
        ContentSettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.light)
}

#Preview("ContentSettingsScreen — Dark") {
    NavigationStack {
        ContentSettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.dark)
}
