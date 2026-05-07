import SwiftUI
import BlueskyCore
import BlueskyKit

// MARK: - NotificationTypeSettingsScreen

/// Per-type notification settings sub-screen. Mirrors RN's
/// `LikeNotificationSettings` / `MentionNotificationSettings` /
/// `ReplyNotificationSettings` etc. — every sub-screen has the same shape,
/// so we model it once and parameterize on `NotificationKind`.
///
/// Layout matches RN's `PreferenceControls`:
/// - Header row with the kind icon, title, and one-sentence subtitle.
/// - "Channels" section with a Push toggle and an Email toggle (RN uses
///   "in-app" for the second slot; SwiftUI exposes Email here because it is
///   what the issue spec asks for and the in-app-list channel is implicit on
///   the native client).
/// - "From" section with a radio-style picker (Anyone / People you follow /
///   Verified accounts) — only rendered when the kind supports a filter
///   (matches RN's `'include' in preference` branch).
///
/// Persistence is local-only today; see `NotificationPreferencesStore` and
/// the gotchas on issue #0115.
struct NotificationTypeSettingsScreen: View {
    let kind: NotificationKind
    let store: NotificationPreferencesStore

    @State private var preference: NotificationTypePreference

    init(kind: NotificationKind, store: NotificationPreferencesStore) {
        self.kind = kind
        self.store = store
        _preference = State(initialValue: store.load(kind))
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: kind.iconSystemName)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.title)
                            .font(.headline)
                        Text(kind.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle(isOn: $preference.push) {
                    Label("Push notifications", systemImage: "bell")
                }
                Toggle(isOn: $preference.email) {
                    Label("Email notifications", systemImage: "envelope")
                }
            } header: {
                Text("Channels")
            } footer: {
                Text("Push notifications also require permission in iOS Settings.")
            }

            if kind.supportsIncludeFilter {
                Section {
                    ForEach(IncludeFilter.allCases) { filter in
                        Button {
                            preference.include = filter
                        } label: {
                            HStack {
                                Text(filter.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if preference.include == filter {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!preference.push && !preference.email)
                    }
                } header: {
                    Text("From")
                } footer: {
                    if !preference.push && !preference.email {
                        Text("Turn on Push or Email to choose who notifications come from.")
                    } else {
                        Text("Choose whose activity counts for this notification type.")
                    }
                }
            }
        }
        .navigationTitle(kind.title)
        .onChange(of: preference) { _, newValue in
            store.save(newValue, for: kind)
        }
    }
}

// MARK: - Previews

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

#Preview("NotificationType — Likes (Light)") {
    NavigationStack {
        NotificationTypeSettingsScreen(
            kind: .like,
            store: NotificationPreferencesStore(preferences: PreviewPreferences())
        )
    }
    .preferredColorScheme(.light)
}

#Preview("NotificationType — DM (Dark)") {
    NavigationStack {
        NotificationTypeSettingsScreen(
            kind: .dm,
            store: NotificationPreferencesStore(preferences: PreviewPreferences())
        )
    }
    .preferredColorScheme(.dark)
}
