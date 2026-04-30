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

struct LanguageSettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel

    private struct Language: Hashable {
        let code: String
        let name: String
    }

    private static let languages: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "es", name: "Spanish"),
        Language(code: "fr", name: "French"),
        Language(code: "de", name: "German"),
        Language(code: "ja", name: "Japanese"),
        Language(code: "ko", name: "Korean"),
        Language(code: "pt", name: "Portuguese"),
        Language(code: "it", name: "Italian"),
        Language(code: "zh", name: "Chinese"),
        Language(code: "ar", name: "Arabic"),
        Language(code: "hi", name: "Hindi"),
        Language(code: "ru", name: "Russian"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Array(Self.languages.enumerated()), id: \.offset) { _, lang in
                    languageRow(lang)
                }
            } header: {
                Text("Post Languages")
            } footer: {
                Text("Selected languages will be tagged on posts you create.")
            }
        }
        .navigationTitle("Languages")
        .onChange(of: viewModel.postLanguages) { _, _ in viewModel.save() }
    }

    @ViewBuilder
    private func languageRow(_ lang: Language) -> some View {
        let selected = viewModel.postLanguages.contains(lang.code)
        Button {
            toggleLanguage(lang.code)
        } label: {
            HStack {
                Text(lang.name).foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func toggleLanguage(_ code: String) {
        if viewModel.postLanguages.contains(code) {
            guard viewModel.postLanguages.count > 1 else { return }
            viewModel.postLanguages.removeAll { $0 == code }
        } else {
            viewModel.postLanguages.append(code)
        }
    }
}

// MARK: - Previews

#Preview("LanguageSettingsScreen — Light") {
    NavigationStack {
        LanguageSettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.light)
}

#Preview("LanguageSettingsScreen — Dark") {
    NavigationStack {
        LanguageSettingsScreen(
            viewModel: SettingsViewModel(
                preferences: PreviewPreferences(),
                accountStore: PreviewNoOpAccountStore()
            )
        )
    }
    .preferredColorScheme(.dark)
}
