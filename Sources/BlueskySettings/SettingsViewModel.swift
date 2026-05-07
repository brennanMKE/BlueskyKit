import Foundation
import Observation
import OSLog
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "SettingsViewModel")

// MARK: - Keys

private enum PrefKey {
    static let fontSize = "settings.fontSize"
    static let autoplayVideo = "settings.autoplayVideo"
    static let externalEmbeds = "settings.externalEmbeds"
    static let altTextRequired = "settings.altTextRequired"
    static let reduceMotion = "settings.reduceMotion"
    static let openLinksInApp = "settings.openLinksInApp"
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
    // The app follows the system appearance (light/dark) on macOS — there is no
    // in-app theme picker. Only typographic preferences live here.

    public var fontSize: Double = 16

    // MARK: - Content & media

    public var autoplayVideo = true
    public var externalEmbeds = true
    public var altTextRequired = false

    // MARK: - Accessibility

    public var reduceMotion = false
    public var openLinksInApp = true

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
        fontSize = loadValue(Double.self, key: PrefKey.fontSize, default: 16)
        autoplayVideo = loadValue(Bool.self, key: PrefKey.autoplayVideo, default: true)
        externalEmbeds = loadValue(Bool.self, key: PrefKey.externalEmbeds, default: true)
        altTextRequired = loadValue(Bool.self, key: PrefKey.altTextRequired, default: false)
        reduceMotion = loadValue(Bool.self, key: PrefKey.reduceMotion, default: false)
        openLinksInApp = loadValue(Bool.self, key: PrefKey.openLinksInApp, default: true)
        postLanguages = loadValue([String].self, key: PrefKey.postLanguages, default: ["en"])
        notifyLikes = loadValue(Bool.self, key: PrefKey.notifyLikes, default: true)
        notifyReposts = loadValue(Bool.self, key: PrefKey.notifyReposts, default: true)
        notifyFollows = loadValue(Bool.self, key: PrefKey.notifyFollows, default: true)
        notifyMentions = loadValue(Bool.self, key: PrefKey.notifyMentions, default: true)
        notifyReplies = loadValue(Bool.self, key: PrefKey.notifyReplies, default: true)
        notifyQuotes = loadValue(Bool.self, key: PrefKey.notifyQuotes, default: true)
    }

    public func save() {
        saveValue(fontSize, key: PrefKey.fontSize)
        saveValue(autoplayVideo, key: PrefKey.autoplayVideo)
        saveValue(externalEmbeds, key: PrefKey.externalEmbeds)
        saveValue(altTextRequired, key: PrefKey.altTextRequired)
        saveValue(reduceMotion, key: PrefKey.reduceMotion)
        saveValue(openLinksInApp, key: PrefKey.openLinksInApp)
        saveValue(postLanguages, key: PrefKey.postLanguages)
        saveValue(notifyLikes, key: PrefKey.notifyLikes)
        saveValue(notifyReposts, key: PrefKey.notifyReposts)
        saveValue(notifyFollows, key: PrefKey.notifyFollows)
        saveValue(notifyMentions, key: PrefKey.notifyMentions)
        saveValue(notifyReplies, key: PrefKey.notifyReplies)
        saveValue(notifyQuotes, key: PrefKey.notifyQuotes)
    }
}
