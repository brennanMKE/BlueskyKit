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

struct AppearanceSettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $viewModel.themeVariant) {
                    Text("Light").tag(BlueskyTheme.Variant.light)
                    Text("Dark").tag(BlueskyTheme.Variant.dark)
                    Text("Dim").tag(BlueskyTheme.Variant.dim)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: viewModel.themeVariant) { _, new in
                    viewModel.setTheme(new)
                }
            }

            Section("Font Size") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("A").font(.caption)
                        Slider(value: $viewModel.fontSize, in: 12...24, step: 1)
                        Text("A").font(.title3)
                    }
                    Text("Preview size: \(Int(viewModel.fontSize))pt")
                        .font(.system(size: viewModel.fontSize))
                        .foregroundStyle(.secondary)
                }
                .onChange(of: viewModel.fontSize) { _, _ in viewModel.save() }
            }
        }
        .navigationTitle("Appearance")
    }
}

// MARK: - Previews

#Preview("AppearanceSettingsScreen — Light") {
    NavigationStack {
        AppearanceSettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.light)
}

#Preview("AppearanceSettingsScreen — Dark") {
    NavigationStack {
        AppearanceSettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.dark)
}
