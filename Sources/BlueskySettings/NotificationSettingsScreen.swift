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

struct NotificationSettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Likes", isOn: $viewModel.notifyLikes)
                Toggle("Reposts", isOn: $viewModel.notifyReposts)
                Toggle("Follows", isOn: $viewModel.notifyFollows)
                Toggle("Mentions", isOn: $viewModel.notifyMentions)
                Toggle("Replies", isOn: $viewModel.notifyReplies)
                Toggle("Quotes", isOn: $viewModel.notifyQuotes)
            } header: {
                Text("Push Notifications")
            } footer: {
                Text("System notification permissions must be granted in iOS Settings.")
            }
        }
        .navigationTitle("Notifications")
        .onChange(of: viewModel.notifyLikes) { _, _ in viewModel.save() }
        .onChange(of: viewModel.notifyReposts) { _, _ in viewModel.save() }
        .onChange(of: viewModel.notifyFollows) { _, _ in viewModel.save() }
        .onChange(of: viewModel.notifyMentions) { _, _ in viewModel.save() }
        .onChange(of: viewModel.notifyReplies) { _, _ in viewModel.save() }
        .onChange(of: viewModel.notifyQuotes) { _, _ in viewModel.save() }
    }
}

// MARK: - Previews

#Preview("NotificationSettingsScreen — Light") {
    NavigationStack {
        NotificationSettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.light)
}

#Preview("NotificationSettingsScreen — Dark") {
    NavigationStack {
        NotificationSettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.dark)
}
