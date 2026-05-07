import Foundation
import Observation
import OSLog
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "SettingsViewModel")

// MARK: - Keys

private enum PrefKey {
    // Appearance keys are owned by `AppearanceStore` (in BlueskyKit) — see
    // that type for `appearance.colorMode` / `appearance.darkVariant` /
    // `appearance.fontFamily` / `appearance.fontSize`. The legacy
    // `settings.fontSize` (a continuous-slider Double) was retired when the
    // discrete five-tier picker landed; the old key is no longer read or
    // written.
    static let autoplayVideo = "settings.autoplayVideo"
    static let externalEmbeds = "settings.externalEmbeds"
    static let altTextRequired = "settings.altTextRequired"
    static let largerAltBadge = "settings.largerAltBadge"
    static let reduceMotion = "settings.reduceMotion"
    static let openLinksInApp = "settings.openLinksInApp"
    static let disableHaptics = "settings.disableHaptics"
    static let postLanguages = "settings.postLanguages"

    // Legacy single-toggle notification keys (kept for read-side migration; the
    // hub now delegates to NotificationPreferencesStore for per-type prefs).
    static let notifyLikes = "settings.notifyLikes"
    static let notifyReposts = "settings.notifyReposts"
    static let notifyFollows = "settings.notifyFollows"
    static let notifyMentions = "settings.notifyMentions"
    static let notifyReplies = "settings.notifyReplies"
    static let notifyQuotes = "settings.notifyQuotes"
}

@Observable
public final class SettingsViewModel {

    // MARK: - Appearance
    //
    // Appearance preferences (color mode, dark variant, font family, font size
    // tier) are owned by `AppearanceStore` so they can be shared with the
    // SwiftUI app shell — the shell needs to read them at the root to apply
    // `.preferredColorScheme(_:)` and select the active `BlueskyTheme` palette.
    // The Settings appearance screen binds to that store directly via the
    // SwiftUI environment, so no fields live on this view model.

    // MARK: - Content & media

    public var autoplayVideo = true
    public var externalEmbeds = true
    public var altTextRequired = false

    // MARK: - Accessibility

    public var reduceMotion = false
    public var openLinksInApp = true
    /// Display larger ALT badges on image embeds for low-vision users.
    /// Mirrors RN's `large_alt_badge` toggle in `AccessibilitySettings.tsx`.
    public var largerAltBadge = false
    /// Disable haptic feedback on actions. iOS-only in RN, persisted on all
    /// platforms here so the preference round-trips even though only iOS
    /// surfaces the toggle.
    public var disableHaptics = false

    // MARK: - Language

    public var postLanguages: [String] = ["en"]

    // MARK: - Notifications (legacy single-toggle mirrors)
    //
    // The notification hub (see `NotificationSettingsScreen` and
    // `NotificationTypeSettingsScreen`) reads/writes per-type preferences
    // through `NotificationPreferencesStore`. These bools are kept on the view
    // model for backwards compat with any callers still toggling a flat row,
    // and so existing keys aren't orphaned during the transition. They mirror
    // the per-type "push" channel value and are not authoritative.

    public var notifyLikes = true
    public var notifyReposts = true
    public var notifyFollows = true
    public var notifyMentions = true
    public var notifyReplies = true
    public var notifyQuotes = true

    // MARK: - State

    public var isSaving = false

    // MARK: - Dependencies

    let preferences: any PreferencesStore
    let accountStore: any AccountStore

    public init(preferences: any PreferencesStore, accountStore: any AccountStore) {
        self.preferences = preferences
        self.accountStore = accountStore
    }

    // MARK: - Load / save

    /// Read a value from the preferences store, falling back to `defaultValue` and
    /// logging any non-`nil` (corruption, type-mismatch) failure so it is observable.
    private func loadValue<T: Codable & Sendable>(_ type: T.Type, key: String, default defaultValue: T) -> T {
        do {
            if let stored = try preferences.get(type, for: key) {
                return stored
            }
            return defaultValue
        } catch {
            logger.warning("Failed to load preference \(key, privacy: .public): \(error.localizedDescription, privacy: .public). Using default.")
            return defaultValue
        }
    }

    /// Write a value to the preferences store, logging any failure so silent persistence
    /// loss is observable.
    private func saveValue<T: Codable & Sendable>(_ value: T, key: String) {
        do {
            try preferences.set(value, for: key)
        } catch {
            logger.error("Failed to save preference \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    public func load() {
        autoplayVideo = loadValue(Bool.self, key: PrefKey.autoplayVideo, default: true)
        externalEmbeds = loadValue(Bool.self, key: PrefKey.externalEmbeds, default: true)
        altTextRequired = loadValue(Bool.self, key: PrefKey.altTextRequired, default: false)
        largerAltBadge = loadValue(Bool.self, key: PrefKey.largerAltBadge, default: false)
        reduceMotion = loadValue(Bool.self, key: PrefKey.reduceMotion, default: false)
        openLinksInApp = loadValue(Bool.self, key: PrefKey.openLinksInApp, default: true)
        disableHaptics = loadValue(Bool.self, key: PrefKey.disableHaptics, default: false)
        postLanguages = loadValue([String].self, key: PrefKey.postLanguages, default: ["en"])
        notifyLikes = loadValue(Bool.self, key: PrefKey.notifyLikes, default: true)
        notifyReposts = loadValue(Bool.self, key: PrefKey.notifyReposts, default: true)
        notifyFollows = loadValue(Bool.self, key: PrefKey.notifyFollows, default: true)
        notifyMentions = loadValue(Bool.self, key: PrefKey.notifyMentions, default: true)
        notifyReplies = loadValue(Bool.self, key: PrefKey.notifyReplies, default: true)
        notifyQuotes = loadValue(Bool.self, key: PrefKey.notifyQuotes, default: true)
    }

    public func save() {
        saveValue(autoplayVideo, key: PrefKey.autoplayVideo)
        saveValue(externalEmbeds, key: PrefKey.externalEmbeds)
        saveValue(altTextRequired, key: PrefKey.altTextRequired)
        saveValue(largerAltBadge, key: PrefKey.largerAltBadge)
        saveValue(reduceMotion, key: PrefKey.reduceMotion)
        saveValue(openLinksInApp, key: PrefKey.openLinksInApp)
        saveValue(disableHaptics, key: PrefKey.disableHaptics)
        saveValue(postLanguages, key: PrefKey.postLanguages)
        saveValue(notifyLikes, key: PrefKey.notifyLikes)
        saveValue(notifyReposts, key: PrefKey.notifyReposts)
        saveValue(notifyFollows, key: PrefKey.notifyFollows)
        saveValue(notifyMentions, key: PrefKey.notifyMentions)
        saveValue(notifyReplies, key: PrefKey.notifyReplies)
        saveValue(notifyQuotes, key: PrefKey.notifyQuotes)
    }
}
