import Foundation
import OSLog
import BlueskyKit

private nonisolated let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "NotificationPreferencesStore"
)

// MARK: - NotificationKind

/// One row in the notification settings hub. Mirrors the keys on RN's
/// `AppBskyNotificationDefs.Preferences` (the lexicon side of
/// `app.bsky.notification.putPreferences`). Each row maps to a per-type
/// sub-screen with push/email toggles and an optional "include from" filter.
public nonisolated enum NotificationKind: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case like
    case repost
    case follow
    case mention
    case reply
    case quote
    case subscribedPost
    case verifications
    case dm

    public var id: String { rawValue }

    /// Human-readable title used as the row label and as the sub-screen
    /// navigation title.
    public var title: String {
        switch self {
        case .like: return "Likes"
        case .repost: return "Reposts"
        case .follow: return "New followers"
        case .mention: return "Mentions"
        case .reply: return "Replies"
        case .quote: return "Quotes"
        case .subscribedPost: return "Activity from others"
        case .verifications: return "Verifications"
        case .dm: return "Direct messages"
        }
    }

    /// One-sentence description shown beneath the title on the per-type
    /// sub-screen. Wording mirrors RN's per-type screen copy.
    public var subtitle: String {
        switch self {
        case .like: return "Get notifications when people like your posts."
        case .repost: return "Get notifications when people repost your posts."
        case .follow: return "Get notifications when people follow you."
        case .mention: return "Get notifications when people mention you."
        case .reply: return "Get notifications when people reply to your posts."
        case .quote: return "Get notifications when people quote your posts."
        case .subscribedPost: return "Get notified about posts and replies from accounts you choose."
        case .verifications: return "Get notifications when your account verification status changes."
        case .dm: return "Get notifications when you receive a direct message."
        }
    }

    /// SF Symbol used on the hub row and at the top of the sub-screen.
    public var iconSystemName: String {
        switch self {
        case .like: return "heart"
        case .repost: return "arrow.2.squarepath"
        case .follow: return "person.badge.plus"
        case .mention: return "at"
        case .reply: return "bubble.left"
        case .quote: return "quote.bubble"
        case .subscribedPost: return "bell.badge"
        case .verifications: return "checkmark.seal"
        case .dm: return "message"
        }
    }

    /// `true` for kinds that support an "include from" filter (Anyone /
    /// People you follow). Mirrors RN's `FilterablePreference` on the
    /// activity-style notifications: like, repost, follow, mention, reply,
    /// quote, subscribed post. Verifications and DMs do not currently expose
    /// a filter on the lexicon (RN uses non-filterable `Preference`).
    public var supportsIncludeFilter: Bool {
        switch self {
        case .like, .repost, .follow, .mention, .reply, .quote, .subscribedPost:
            return true
        case .verifications, .dm:
            return false
        }
    }
}

// MARK: - IncludeFilter

/// "Include from" radio choice on the per-type sub-screen. Mirrors RN's
/// `include` field on `FilterablePreference`. RN today only ships `all` and
/// `follows`; "verified accounts" appears in some related Bluesky settings
/// and is included here so the UI can offer it once the lexicon catches up
/// — selecting it currently behaves identically to `all` on the server side
/// (we persist it locally, but a future server write would need lexicon
/// support).
public nonisolated enum IncludeFilter: String, Codable, Sendable, CaseIterable, Identifiable {
    case all
    case follows
    case verified

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "Anyone"
        case .follows: return "People you follow"
        case .verified: return "Verified accounts"
        }
    }
}

// MARK: - NotificationTypePreference

/// Per-type preference state. Local-only today: persisted via the project's
/// shared `PreferencesStore` (which under the app target is a UserDefaults
/// adapter). Server-side `app.bsky.notification.putPreferences` is **not**
/// wired in `BlueskyCore` yet (no `Preferences` lexicon types), so this
/// store is the source of truth in-app. See gotchas in issue #0115.
public nonisolated struct NotificationTypePreference: Codable, Sendable, Hashable {
    /// Push notification channel master toggle.
    public var push: Bool
    /// Email notification channel master toggle. The server-side persistence
    /// of email opt-in is handled through bsky.app for now; this flag drives
    /// only the in-app toggle state.
    public var email: Bool
    /// "Include from" filter. Ignored when `kind.supportsIncludeFilter` is
    /// false.
    public var include: IncludeFilter

    public init(push: Bool = true, email: Bool = false, include: IncludeFilter = .all) {
        self.push = push
        self.email = email
        self.include = include
    }
}

// MARK: - NotificationPreferencesStore

/// Local persistence for per-type notification preferences. Layered on top of
/// the shared `PreferencesStore` so the keying is consistent with the rest of
/// settings. Returns sensible defaults for any kind that has not been written
/// before.
public nonisolated struct NotificationPreferencesStore: Sendable {
    private let preferences: any PreferencesStore

    public init(preferences: any PreferencesStore) {
        self.preferences = preferences
    }

    private func key(for kind: NotificationKind) -> String {
        "settings.notifications.\(kind.rawValue)"
    }

    /// Read the persisted preference for `kind`, returning a default value
    /// (push on, email off, include = anyone) when no value has been stored.
    public func load(_ kind: NotificationKind) -> NotificationTypePreference {
        do {
            if let stored = try preferences.get(NotificationTypePreference.self, for: key(for: kind)) {
                return stored
            }
        } catch {
            logger.warning("Failed to load notification preference for \(kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return NotificationTypePreference()
    }

    /// Write `value` for `kind`, logging on failure so silent persistence
    /// loss is observable.
    public func save(_ value: NotificationTypePreference, for kind: NotificationKind) {
        do {
            try preferences.set(value, for: key(for: kind))
        } catch {
            logger.error("Failed to save notification preference for \(kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
