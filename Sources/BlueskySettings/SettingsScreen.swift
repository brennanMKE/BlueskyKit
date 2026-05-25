import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

/// RN parity: `HELP_DESK_URL` from `Bluesky-ReactNative/src/lib/constants.ts`.
/// The Help row in the Settings hub opens this URL in the system browser.
///
/// Public so other entry points (e.g. the iOS sidebar drawer's footer Help
/// pill button — #0150) can share the same constant rather than redeclaring
/// it. Wrapping the URL in a `BlueskyHelpURLs` enum keeps the namespace
/// tidy and leaves room for the legal-link URLs the drawer also needs.
public enum BlueskyHelpURLs {
    /// `HELP_DESK_URL` — the Zendesk help-desk landing page.
    public static let helpDesk = URL(string: "https://blueskyweb.zendesk.com/hc/en-us")!
    /// Terms of Service — RN's `ExtraLinks` in `Drawer.tsx` links to this URL.
    public static let termsOfService = URL(string: "https://bsky.social/about/support/tos")!
    /// Privacy Policy — RN's `ExtraLinks` in `Drawer.tsx` links to this URL.
    public static let privacyPolicy = URL(string: "https://bsky.social/about/support/privacy-policy")!
}

/// Backwards-compatible alias preserved so the rest of `SettingsScreen` still
/// compiles unchanged. Remove once every call site has migrated to the
/// `BlueskyHelpURLs` namespace.
private let helpDeskURL = BlueskyHelpURLs.helpDesk

public struct SettingsScreen: View {
    @State private var viewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL
    private let network: any NetworkClient
    private let cache: (any CacheStore)?
    private let currentAccount: Account?
    private let onModerationTap: (() -> Void)?
    private let onSignOut: () -> Void
    /// Called when the user successfully deactivates their account from the
    /// Account settings hub. The host should sign the user out so the
    /// RootView gate routes them to `DeactivatedView` on next sign-in
    /// (mirrors RN's `logoutCurrentAccount('Deactivated')`). Defaults to
    /// `onSignOut` for callers that don't need a distinct hook.
    private let onAccountDeactivated: () -> Void

    public init(
        preferences: any PreferencesStore,
        accountStore: any AccountStore,
        network: any NetworkClient,
        cache: (any CacheStore)? = nil,
        currentAccount: Account? = nil,
        onModerationTap: (() -> Void)? = nil,
        onSignOut: @escaping () -> Void,
        onAccountDeactivated: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: SettingsViewModel(preferences: preferences, accountStore: accountStore))
        self.network = network
        self.cache = cache
        self.currentAccount = currentAccount
        self.onModerationTap = onModerationTap
        self.onSignOut = onSignOut
        self.onAccountDeactivated = onAccountDeactivated ?? onSignOut
    }

    public var body: some View {
        List {
            Section("Account") {
                NavigationLink {
                    AccountSettingsScreen(
                        network: network,
                        account: currentAccount,
                        onDeactivated: onAccountDeactivated
                    )
                } label: {
                    Label("Account", systemImage: "person.circle")
                }
                .accessibilityIdentifier("settings-account-row")

                NavigationLink {
                    FindContactsScreen(network: network, accountStore: viewModel.accountStore)
                } label: {
                    Label("Find Friends", systemImage: "person.2")
                }
                .accessibilityIdentifier("settings-find-friends-row")

                NavigationLink {
                    AppPasswordsScreen(network: network)
                } label: {
                    Label("App Passwords", systemImage: "key")
                }
                .accessibilityIdentifier("settings-app-passwords-row")

                Button(role: .destructive) {
                    onSignOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier("settings-sign-out-button")
            }

            Section("Appearance") {
                NavigationLink {
                    AppearanceSettingsScreen(viewModel: viewModel)
                } label: {
                    Label("Appearance", systemImage: "paintpalette")
                }
                .accessibilityIdentifier("settings-appearance-row")
            }

            Section("Preferences") {
                NavigationLink {
                    LanguageSettingsScreen(viewModel: viewModel, network: network)
                } label: {
                    Label("Languages", systemImage: "globe")
                }
                .accessibilityIdentifier("settings-languages-row")

                NavigationLink {
                    ContentSettingsScreen(viewModel: viewModel, network: network)
                } label: {
                    Label("Content & Media", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("settings-content-row")

                NavigationLink {
                    AccessibilitySettingsScreen(viewModel: viewModel)
                } label: {
                    Label("Accessibility", systemImage: "accessibility")
                }
                .accessibilityIdentifier("settings-accessibility-row")
            }

            Section("Notifications") {
                NavigationLink {
                    NotificationSettingsScreen(viewModel: viewModel)
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
                .accessibilityIdentifier("settings-notifications-row")
            }

            Section("Privacy") {
                NavigationLink {
                    PrivacySettingsScreen(
                        network: network,
                        accountStore: viewModel.accountStore,
                        currentAccount: currentAccount
                    )
                } label: {
                    Label("Privacy & Security", systemImage: "lock.shield")
                }
                .accessibilityIdentifier("settings-privacy-row")

                if let onMod = onModerationTap {
                    Button {
                        onMod()
                    } label: {
                        Label("Moderation", systemImage: "shield")
                    }
                    .accessibilityIdentifier("settings-moderation-row")
                }
            }

            Section {
                Button {
                    openURL(helpDeskURL)
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .accessibilityHint(Text("Opens helpdesk in browser"))
                .accessibilityIdentifier("settings-help-row")

                NavigationLink {
                    AboutScreen(cache: cache, currentAccount: currentAccount)
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                .accessibilityIdentifier("settings-about-row")
            }
        }
        // UI-test coupling surface (#0183): `children: .contain` exposes the
        // List as one queryable element carrying `settings-screen` while
        // keeping each row individually addressable by its own identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-screen")
        .navigationTitle("Settings")
        .onAppear { viewModel.load() }
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
