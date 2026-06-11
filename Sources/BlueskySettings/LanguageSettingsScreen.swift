import SwiftUI
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "LanguageSettings"
)

// MARK: - LanguageSettingsScreen

/// Settings → Languages.
///
/// Mirrors `Bluesky-ReactNative/src/screens/Settings/LanguageSettings.tsx`.
/// Three sections render in the same order as RN:
///
/// 1. **App language** — single-select picker for the UI's display language.
///    Stored locally via `UserDefaultsPreferencesStore` under
///    `settings.appLanguage`; option list comes from `AppLanguages.all`,
///    matching RN's `APP_LANGUAGES`. Apple platforms apply this via
///    `Bundle.preferredLocalizations` at next launch — see Gotchas.
/// 2. **Primary post language** — single-select picker. Stored server-side
///    via `app.bsky.actor.defs#postLanguagesPref` (one-element array). The
///    composer's `selectedLanguage` defaults from this value.
/// 3. **Content languages** — multi-select with checkboxes. Stored
///    server-side via `app.bsky.actor.defs#contentLanguagesPref`. Empty
///    selection means "all languages will be shown".
public struct LanguageSettingsScreen: View {

    private let preferences: any PreferencesStore
    private let network: any NetworkClient
    @State private var model: LanguageSettingsViewModel

    public init(preferences: any PreferencesStore, network: any NetworkClient) {
        self.preferences = preferences
        self.network = network
        _model = State(initialValue: LanguageSettingsViewModel(
            preferences: preferences,
            network: network
        ))
    }

    /// Convenience initializer for the existing `SettingsViewModel` call site.
    /// Delegates to the canonical init by pulling `PreferencesStore` off the
    /// view model.
    init(viewModel: SettingsViewModel, network: any NetworkClient) {
        self.preferences = viewModel.preferences
        self.network = network
        _model = State(initialValue: LanguageSettingsViewModel(
            preferences: viewModel.preferences,
            network: network
        ))
    }

    public var body: some View {
        Form {
            // MARK: App language
            Section {
                Picker(
                    selection: Binding(
                        get: { model.appLanguage },
                        set: { newValue in model.setAppLanguage(newValue) }
                    ),
                    label: Text("Language")
                ) {
                    ForEach(AppLanguages.all) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("App language")
            } footer: {
                Text("Select which language to use for the app's user interface.")
            }

            // MARK: Primary post language
            Section {
                Picker(
                    selection: Binding(
                        get: { model.primaryPostLanguage },
                        set: { newValue in
                            Task { await model.setPrimaryPostLanguage(newValue) }
                        }
                    ),
                    label: Text("Language")
                ) {
                    ForEach(model.sortedContentLanguages) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Primary language")
            } footer: {
                Text("Select your preferred language for translations in your feed.")
            }

            // MARK: Content languages (multi-select)
            Section {
                if model.contentLanguages.isEmpty {
                    Text("All languages will be shown in your feeds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.contentLanguageOptions) { lang in
                    Button {
                        Task { await model.toggleContentLanguage(lang.code) }
                    } label: {
                        HStack {
                            Text(lang.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if model.contentLanguages.contains(lang.code) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(lang.name)
                    .accessibilityAddTraits(
                        model.contentLanguages.contains(lang.code) ? [.isSelected] : []
                    )
                }
            } header: {
                Text("Content languages")
            } footer: {
                Text("Select which languages you want your subscribed feeds to include. If none are selected, all languages will be shown.")
            }
        }
        .navigationTitle("Languages")
        .task { await model.load() }
        .alert(
            "Could not save",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            },
            message: {
                if let msg = model.errorMessage { Text(msg) }
            }
        )
    }
}

// MARK: - View model

@MainActor
@Observable
final class LanguageSettingsViewModel {

    /// BCP-47 code for the app's display language. Stored locally via
    /// `PreferencesStore`; defaults to `"en"` when not yet set.
    var appLanguage: String = "en"

    /// BCP-47 code for the user's primary post language. Mirrors RN's
    /// `langPrefs.primaryLanguage`; persisted server-side via
    /// `postLanguagesPref` (as a one-element array). Defaults to `"en"`.
    var primaryPostLanguage: String = "en"

    /// BCP-47 codes for the user's selected content languages. Empty array
    /// means "all languages". Persisted server-side via
    /// `contentLanguagesPref`.
    var contentLanguages: [String] = []

    var isLoading = false
    var errorMessage: String?

    private let preferences: any PreferencesStore
    private let network: any NetworkClient

    /// `UserDefaultsPreferencesStore` key for the app-language picker. Read
    /// at startup by the host app to apply `Bundle.preferredLocalizations`.
    static let appLanguageKey = "settings.appLanguage"
    /// Optional local mirror of the primary post language so the composer
    /// can read it without making a network call. Refreshed on every save
    /// and on every `load()`.
    static let primaryPostLanguageKey = "settings.primaryPostLanguage"

    init(preferences: any PreferencesStore, network: any NetworkClient) {
        self.preferences = preferences
        self.network = network
        // Seed app language from local prefs immediately so the picker shows
        // the correct row before `load()` runs.
        do {
            if let stored = try preferences.get(String.self, for: Self.appLanguageKey) {
                self.appLanguage = AppLanguages.sanitize(stored)
            }
        } catch {
            logger.warning("Could not read appLanguage from preferences: \(error.localizedDescription, privacy: .public)")
        }
        do {
            if let stored = try preferences.get(String.self, for: Self.primaryPostLanguageKey) {
                self.primaryPostLanguage = stored
            }
        } catch {
            logger.warning("Could not read primaryPostLanguage from preferences: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pulls the latest server-backed prefs (`getPreferences`) and refreshes
    /// `primaryPostLanguage` + `contentLanguages`. Quietly retains the
    /// existing values if the request fails so the picker stays usable
    /// offline.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            if let primary = resp.postLanguages.first, !primary.isEmpty {
                self.primaryPostLanguage = primary
                saveLocal(primary, key: Self.primaryPostLanguageKey)
            }
            self.contentLanguages = resp.contentLanguages
        } catch {
            logger.debug("getPreferences refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: App language (local only)

    func setAppLanguage(_ code: String) {
        let sanitized = AppLanguages.sanitize(code)
        guard sanitized != appLanguage else { return }
        appLanguage = sanitized
        saveLocal(sanitized, key: Self.appLanguageKey)
    }

    // MARK: Primary post language (server)

    func setPrimaryPostLanguage(_ code: String) async {
        guard !code.isEmpty, code != primaryPostLanguage else { return }
        let previous = primaryPostLanguage
        primaryPostLanguage = code
        saveLocal(code, key: Self.primaryPostLanguageKey)
        do {
            // Read-modify-write (#0201): merge into the full preferences array.
            try await PreferencesWriter.shared.update(network: network, .postLanguages([code]))
        } catch {
            logger.error("putPreferences(postLanguages) failed: \(error.localizedDescription, privacy: .public)")
            primaryPostLanguage = previous
            saveLocal(previous, key: Self.primaryPostLanguageKey)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Content languages (server, multi-select)

    func toggleContentLanguage(_ code: String) async {
        let previous = contentLanguages
        if let index = contentLanguages.firstIndex(of: code) {
            contentLanguages.remove(at: index)
        } else {
            contentLanguages.append(code)
        }
        let next = contentLanguages
        do {
            // Read-modify-write (#0201): merge into the full preferences array.
            try await PreferencesWriter.shared.update(network: network, .contentLanguages(next))
        } catch {
            logger.error("putPreferences(contentLanguages) failed: \(error.localizedDescription, privacy: .public)")
            contentLanguages = previous
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Derived

    /// All `ContentLanguages.all` sorted alphabetically by display name.
    /// Used to populate the Primary post language picker. Mirrors RN's
    /// `DEDUPED_LANGUAGES.sort((a,b) => a.label.localeCompare(...))`.
    var sortedContentLanguages: [Language] {
        ContentLanguages.all.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// The list of content-language rows shown in the multi-select section.
    /// RN shows the user's selected codes plus their primary post language
    /// plus a "Recently used" set; we collapse that to selected codes ∪
    /// primary post language so the user can always toggle their primary
    /// off, mirroring the RN behavior.
    var contentLanguageOptions: [Language] {
        var seen = Set<String>()
        var ordered: [Language] = []
        for code in (contentLanguages + [primaryPostLanguage]) {
            guard !code.isEmpty, seen.insert(code).inserted else { continue }
            if let lang = ContentLanguages.byCode[code] {
                ordered.append(lang)
            } else {
                ordered.append(Language(code: code, name: code.uppercased()))
            }
        }
        return ordered
    }

    // MARK: - Local persistence

    private func saveLocal<T: Codable & Sendable>(_ value: T, key: String) {
        do {
            try preferences.set(value, for: key)
        } catch {
            logger.error("Failed to save preference \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
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

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

// MARK: - Previews

#Preview("LanguageSettingsScreen — Light") {
    NavigationStack {
        LanguageSettingsScreen(
            preferences: PreviewPreferences(),
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("LanguageSettingsScreen — Dark") {
    NavigationStack {
        LanguageSettingsScreen(
            preferences: PreviewPreferences(),
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.dark)
}
