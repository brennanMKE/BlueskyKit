import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

// MARK: - Preview helpers (private to this file)

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

// MARK: - AppearanceSettingsScreen

struct AppearanceSettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel

    /// Source of truth for the four appearance preferences. Injected at the
    /// app root so the same instance drives both the Settings pickers (here)
    /// and `.preferredColorScheme(_:)` / `.blueskyTheme(_:)` on the shell.
    @Environment(AppearanceStore.self) private var appearance

    /// Used to decide whether to show the dark-theme variant picker when color
    /// mode is `.system` (it should show only when the system itself is dark).
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        @Bindable var appearance = appearance

        Form {
            // MARK: Color mode

            Section {
                Picker(selection: $appearance.colorMode) {
                    Text("System").tag(AppearanceColorMode.system)
                    Text("Light").tag(AppearanceColorMode.light)
                    Text("Dark").tag(AppearanceColorMode.dark)
                } label: {
                    Label("Color Mode", systemImage: "iphone")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Color Mode")
            }

            // MARK: Dark theme variant
            //
            // RN parity: visible when color mode is Dark, or when System is on
            // and the host trait collection is dark. Hidden in pure Light mode
            // where the variant has no effect.
            if shouldShowDarkVariant {
                Section {
                    Picker(selection: $appearance.darkVariant) {
                        Text("Dim").tag(DarkThemeVariant.dim)
                        Text("Dark").tag(DarkThemeVariant.dark)
                    } label: {
                        Label("Dark Theme", systemImage: "moon")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Dark Theme")
                }
            }

            // MARK: Font family

            Section {
                Picker(selection: $appearance.fontFamily) {
                    Text("System").tag(AppearanceFontFamily.system)
                    Text("Theme").tag(AppearanceFontFamily.theme)
                } label: {
                    Label("Font", systemImage: "textformat")
                }
                .pickerStyle(.segmented)

                Text("For the best experience, we recommend using the theme font.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Font")
            }

            // MARK: Font size

            Section {
                Picker(selection: $appearance.fontSize) {
                    ForEach(AppearanceFontSize.allCases, id: \.self) { tier in
                        Text(tier.shortLabel).tag(tier)
                    }
                } label: {
                    Label("Font Size", systemImage: "textformat.size")
                }
                .pickerStyle(.segmented)

                // Live preview of the selected body size.
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(.system(size: appearance.fontSize.bodyPointSize))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Font Size")
            }
        }
        .navigationTitle("Appearance")
    }

    /// Visible when the active color scheme is dark — i.e. the user picked
    /// Dark, or picked System and the system itself is dark. This mirrors RN's
    /// `colorMode !== 'light'` guard while honouring the System-resolves-to-Dark
    /// case explicitly.
    private var shouldShowDarkVariant: Bool {
        switch appearance.colorMode {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            return systemColorScheme == .dark
        }
    }
}

// MARK: - Previews

#Preview("AppearanceSettingsScreen — Light") {
    let preferences = PreviewPreferences()
    return NavigationStack {
        AppearanceSettingsScreen(
            viewModel: SettingsViewModel(
                preferences: preferences,
                accountStore: PreviewNoOpAccountStore()
            )
        )
        .environment(AppearanceStore(preferences: preferences))
    }
    .preferredColorScheme(.light)
}

#Preview("AppearanceSettingsScreen — Dark") {
    let preferences = PreviewPreferences()
    return NavigationStack {
        AppearanceSettingsScreen(
            viewModel: SettingsViewModel(
                preferences: preferences,
                accountStore: PreviewNoOpAccountStore()
            )
        )
        .environment(AppearanceStore(preferences: preferences))
    }
    .preferredColorScheme(.dark)
}
