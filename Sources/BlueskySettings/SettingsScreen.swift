import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

public struct SettingsScreen: View {
    @State private var viewModel: SettingsViewModel
    private let network: any NetworkClient
    private let onModerationTap: (() -> Void)?
    private let onSignOut: () -> Void

    public init(
        preferences: any PreferencesStore,
        accountStore: any AccountStore,
        network: any NetworkClient,
        onModerationTap: (() -> Void)? = nil,
        onSignOut: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: SettingsViewModel(preferences: preferences, accountStore: accountStore))
        self.network = network
        self.onModerationTap = onModerationTap
        self.onSignOut = onSignOut
    }

    public var body: some View {
        List {
            Section("Account") {
                NavigationLink {
                    AccountSettingsScreen(accountStore: viewModel)
                } label: {
                    Label("Account", systemImage: "person.circle")
                }

                NavigationLink {
                    FindContactsScreen(network: network, accountStore: viewModel.accountStore)
                } label: {
                    Label("Find Friends", systemImage: "person.2")
                }

                NavigationLink {
                    AppPasswordsScreen(network: network)
                } label: {
                    Label("App Passwords", systemImage: "key")
                }

                Button(role: .destructive) {
                    onSignOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section("Appearance") {
                NavigationLink {
                    AppearanceSettingsScreen(viewModel: viewModel)
                } label: {
                    Label("Appearance", systemImage: "paintpalette")
                }
            }

            Section("Preferences") {
                NavigationLink {
                    LanguageSettingsScreen(viewModel: viewModel)
                } label: {
                    Label("Languages", systemImage: "globe")
                }

                NavigationLink {
                    ContentSettingsScreen(viewModel: viewModel)
                } label: {
                    Label("Content & Media", systemImage: "photo.on.rectangle")
                }

                NavigationLink {
                    AccessibilitySettingsScreen(viewModel: viewModel)
                } label: {
                    Label("Accessibility", systemImage: "accessibility")
                }
            }

            Section("Notifications") {
                NavigationLink {
                    NotificationSettingsScreen(viewModel: viewModel)
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
            }

            Section("Privacy") {
                NavigationLink {
                    PrivacySettingsScreen(viewModel: viewModel)
                } label: {
                    Label("Privacy & Security", systemImage: "lock.shield")
                }

                if let onMod = onModerationTap {
                    Button {
                        onMod()
                    } label: {
                        Label("Moderation", systemImage: "shield")
                    }
                }
            }

            Section {
                NavigationLink {
                    AboutScreen()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { viewModel.load() }
    }
}

// MARK: - AccountSettingsScreen protocol adapter (avoids circular dep)

private struct AccountSettingsScreen: View {
    let accountStore: SettingsViewModel

    var body: some View {
        Form {
            Section("App Preferences") {
                Text("Account settings like email and password changes require signing in via bsky.app or your PDS directly.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
        .navigationTitle("Account")
    }
}

// MARK: - Preview helpers

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

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

// MARK: - Previews

#Preview("SettingsScreen — Light") {
    NavigationStack {
        SettingsScreen(
            preferences: PreviewPreferences(),
            accountStore: PreviewNoOpAccountStore(),
            network: PreviewNoOpNetwork(),
            onSignOut: {}
        )
    }
    .preferredColorScheme(.light)
}

#Preview("SettingsScreen — Dark") {
    NavigationStack {
        SettingsScreen(
            preferences: PreviewPreferences(),
            accountStore: PreviewNoOpAccountStore(),
            network: PreviewNoOpNetwork(),
            onSignOut: {}
        )
    }
    .preferredColorScheme(.dark)
}
