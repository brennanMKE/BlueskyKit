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

struct AccessibilitySettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Reduce Motion", isOn: $viewModel.reduceMotion)
                Toggle("Open Links In-App", isOn: $viewModel.openLinksInApp)
            } header: {
                Text("Display")
            }

            Section {
                Toggle("Require alt text before posting", isOn: $viewModel.altTextRequired)
                Toggle("Display larger alt text badges", isOn: $viewModel.largerAltBadge)
            } header: {
                Text("Alt text")
            } footer: {
                Text("When enabled, you must add alt text to images before posting.")
            }

            #if os(iOS)
            Section {
                Toggle("Disable haptic feedback", isOn: $viewModel.disableHaptics)
            } header: {
                Text("Haptics")
            }
            #endif
        }
        .navigationTitle("Accessibility")
        .onChange(of: viewModel.reduceMotion) { _, _ in viewModel.save() }
        .onChange(of: viewModel.openLinksInApp) { _, _ in viewModel.save() }
        .onChange(of: viewModel.altTextRequired) { _, _ in viewModel.save() }
        .onChange(of: viewModel.largerAltBadge) { _, _ in viewModel.save() }
        .onChange(of: viewModel.disableHaptics) { _, _ in viewModel.save() }
    }
}

// MARK: - Previews

#Preview("AccessibilitySettingsScreen — Light") {
    NavigationStack {
        AccessibilitySettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.light)
}

#Preview("AccessibilitySettingsScreen — Dark") {
    NavigationStack {
        AccessibilitySettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.dark)
}
