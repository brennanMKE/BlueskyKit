import SwiftUI
import OSLog
import BlueskyCore
import BlueskyKit
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "NotificationSettings"
)

// MARK: - NotificationSettingsScreen
//
// Hub mirroring `Bluesky-ReactNative/src/screens/Settings/NotificationSettings/index.tsx`.
//
// Each notification type that RN ships as its own sub-screen
// (LikeNotificationSettings, RepostNotificationSettings, …) is rendered as a
// `NavigationLink` row that pushes a shared `NotificationTypeSettingsScreen`
// parameterized on `NotificationKind`.
//
// Push permission admonition: on iOS we observe
// `UNUserNotificationCenter.current().getNotificationSettings()`; if the user
// has not authorized notifications, a banner row at the top opens the system
// Settings deep link (matches RN's `Linking.openSettings()` fallback).
//
// **Persistence** is local-only today (see `NotificationPreferencesStore`).
// `app.bsky.notification.putPreferences` and the
// `app.bsky.notification.defs#preferences` lexicon are not modelled in
// `BlueskyCore` yet; wiring server-side persistence is a follow-up. The hub
// structure is the priority for #0115. The DM toggle similarly persists
// locally — server-side it's encoded on `chat.bsky.actor.declaration`'s
// `allowIncoming` field, which is not yet plumbed.
//
// Email notifications (digest, security alerts) are deferred to a referral
// sheet — these aren't on a stable public lexicon today; RN reaches them
// through bsky.app.

struct NotificationSettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel
    /// Local-only per-type store. Constructed from the same
    /// `PreferencesStore` instance the rest of settings shares.
    private let notificationStore: NotificationPreferencesStore

    @State private var permissionStatus: PushPermissionStatus = .unknown
    @State private var presentingSheet: SheetKind?

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self.notificationStore = NotificationPreferencesStore(preferences: viewModel.preferences)
    }

    var body: some View {
        Form {
            // MARK: Push permission admonition
            //
            // Only rendered when the OS reports a non-authorized status.
            // RN gates the equivalent banner on
            // `permissions && !permissions.granted`; we do the same here using
            // `UNUserNotificationCenter`.

            if permissionStatus == .denied || permissionStatus == .notDetermined {
                Section {
                    Button(action: openSystemNotificationSettings) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Push notifications are off")
                                    .font(.headline)
                                Text("Tap to open Settings and enable push notifications for Bluesky.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // MARK: Activity types

            Section {
                ForEach(activityKinds, id: \.self) { kind in
                    NavigationLink {
                        NotificationTypeSettingsScreen(kind: kind, store: notificationStore)
                    } label: {
                        rowLabel(for: kind)
                    }
                }
            } header: {
                Text("Activity")
            } footer: {
                Text("Choose which activity types send you push and email notifications.")
            }

            // MARK: Verifications

            Section {
                NavigationLink {
                    NotificationTypeSettingsScreen(kind: .verifications, store: notificationStore)
                } label: {
                    rowLabel(for: .verifications)
                }
            } header: {
                Text("Verifications")
            }

            // MARK: Direct messages

            Section {
                NavigationLink {
                    NotificationTypeSettingsScreen(kind: .dm, store: notificationStore)
                } label: {
                    rowLabel(for: .dm)
                }
            } header: {
                Text("Direct messages")
            } footer: {
                Text("DM notification settings are stored locally. Server-side message-request filters live on your chat declaration record — manage those on bsky.app for now.")
            }

            // MARK: Email notifications (referral)

            Section {
                Button {
                    presentingSheet = .emailReferral
                } label: {
                    HStack {
                        Label("Email notifications", systemImage: "envelope")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Email")
            } footer: {
                Text("Digest emails and security alerts are managed on bsky.app.")
            }
        }
        .navigationTitle("Notifications")
        .task { await refreshPermissionStatus() }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                Task { await refreshPermissionStatus() }
            }
        }
        .sheet(item: $presentingSheet) { kind in
            switch kind {
            case .emailReferral:
                EmailNotificationsReferralSheet(dismiss: { presentingSheet = nil })
            }
        }
    }

    // MARK: - Layout helpers

    @Environment(\.scenePhase) private var scenePhase

    /// Activity-style notifications grouped under "Activity" in the hub. RN
    /// orders these as Likes, New followers, Replies, Mentions, Quotes,
    /// Reposts, Activity from others; we follow that ordering.
    private var activityKinds: [NotificationKind] {
        [.like, .follow, .reply, .mention, .quote, .repost, .subscribedPost]
    }

    @ViewBuilder
    private func rowLabel(for kind: NotificationKind) -> some View {
        let pref = notificationStore.load(kind)
        HStack {
            Label(kind.title, systemImage: kind.iconSystemName)
            Spacer()
            Text(previewText(for: pref, kind: kind))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Mirrors RN's `SettingPreview` helper: condenses the channel + filter
    /// state into a short summary string for the hub row.
    private func previewText(for pref: NotificationTypePreference, kind: NotificationKind) -> String {
        let channels: [String] = {
            var arr: [String] = []
            if pref.push { arr.append("Push") }
            if pref.email { arr.append("Email") }
            return arr
        }()
        if channels.isEmpty { return "Off" }
        if kind.supportsIncludeFilter, pref.include != .all {
            return (channels + [pref.include.title]).joined(separator: ", ")
        }
        return channels.joined(separator: ", ")
    }

    // MARK: - Permission probing

    private func refreshPermissionStatus() async {
        #if canImport(UserNotifications) && !os(macOS)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let next: PushPermissionStatus
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            next = .authorized
        case .denied:
            next = .denied
        case .notDetermined:
            next = .notDetermined
        @unknown default:
            next = .unknown
        }
        await MainActor.run { self.permissionStatus = next }
        #else
        // macOS: the system notification settings prompt is handled by the
        // app delegate; we don't expose a permission gate here today.
        await MainActor.run { self.permissionStatus = .authorized }
        #endif
    }

    private func openSystemNotificationSettings() {
        #if canImport(UIKit) && !os(macOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        Task { @MainActor in
            await UIApplication.shared.open(url)
        }
        #elseif canImport(AppKit)
        // macOS deep-link to Notifications pane.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

// MARK: - Permission status

private enum PushPermissionStatus: Equatable {
    case unknown
    case notDetermined
    case authorized
    case denied
}

// MARK: - Sheets

private enum SheetKind: Identifiable, Hashable {
    case emailReferral
    var id: Self { self }
}

private struct EmailNotificationsReferralSheet: View {
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL
    private let bskyAppURL = URL(string: "https://bsky.app/settings/notifications")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "envelope.badge")
                            .font(.title2)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Email notifications")
                                .font(.headline)
                            Text("Digest emails and security alerts are managed on bsky.app. The native settings screen for these is coming in a later release.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button {
                        openURL(bskyAppURL)
                    } label: {
                        Label("Open bsky.app", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("Email notifications")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 320)
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
