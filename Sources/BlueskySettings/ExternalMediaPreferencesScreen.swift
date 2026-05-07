import SwiftUI
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "ExternalMediaPreferences"
)

// MARK: - ExternalMediaPreferencesScreen

/// Settings → Content & Media → External media.
///
/// Mirrors `Bluesky-ReactNative/src/screens/Settings/ExternalMediaPreferences.tsx`.
/// State persists locally via `PreferencesStore` (RN keeps these in
/// `persisted.Schema.externalEmbeds`, not in AT Proto preferences). Each
/// per-source flag controls whether `PostEmbedView` should inline-render the
/// third-party player or fall back to a plain link card.
///
/// The list order and labels match RN's `externalEmbedLabels`. Tenor is
/// surfaced here even though RN currently filters it out (see the
/// `// TODO: Remove special case when we disable the old integration.`
/// comment in the RN file) — once RN re-enables it the SwiftUI screen is
/// already wired.
public struct ExternalMediaPreferencesScreen: View {

    @State private var model: ExternalMediaPreferencesViewModel

    public init(preferences: any PreferencesStore) {
        _model = State(initialValue: ExternalMediaPreferencesViewModel(preferences: preferences))
    }

    public var body: some View {
        Form {
            Section {
                Text("External media may allow websites to collect information about you and your device. No information is sent or requested until you press the play button.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ExternalMediaSource.allCases) { source in
                    Toggle(isOn: Binding(
                        get: { model.preferences[source] },
                        set: { newValue in model.set(source, isOn: newValue) }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.displayName)
                                Text("Enable inline players")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: source.systemImageName)
                        }
                    }
                }
            } header: {
                Text("Enable media players for")
            }
        }
        .navigationTitle("External Media Preferences")
    }
}

// MARK: - View model

@MainActor
@Observable
final class ExternalMediaPreferencesViewModel {

    /// Authoritative copy of the per-source flags. Loaded from
    /// `PreferencesStore` on init; every change is persisted immediately so
    /// the embed renderer side sees the same value on next launch.
    var preferences: ExternalEmbedsPreferences = .default

    private let store: any PreferencesStore

    init(preferences store: any PreferencesStore) {
        self.store = store
        self.preferences = Self.load(from: store)
    }

    func set(_ source: ExternalMediaSource, isOn: Bool) {
        guard preferences[source] != isOn else { return }
        preferences[source] = isOn
        save()
    }

    private func save() {
        do {
            try store.set(preferences, for: ExternalEmbedsPreferencesKey.storage)
        } catch {
            logger.error("Failed to save external embeds prefs: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from store: any PreferencesStore) -> ExternalEmbedsPreferences {
        do {
            if let stored = try store.get(ExternalEmbedsPreferences.self, for: ExternalEmbedsPreferencesKey.storage) {
                return stored
            }
        } catch {
            logger.warning("Failed to load external embeds prefs: \(error.localizedDescription, privacy: .public). Using defaults.")
        }
        return .default
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

// MARK: - Previews

#Preview("ExternalMediaPreferencesScreen — Light") {
    NavigationStack {
        ExternalMediaPreferencesScreen(preferences: PreviewPreferences())
    }
    .preferredColorScheme(.light)
}

#Preview("ExternalMediaPreferencesScreen — Dark") {
    NavigationStack {
        ExternalMediaPreferencesScreen(preferences: PreviewPreferences())
    }
    .preferredColorScheme(.dark)
}
