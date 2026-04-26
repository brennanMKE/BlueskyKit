import Foundation
import Observation
import BlueskyCore
import BlueskyKit
import BlueskyUI

// MARK: - Keys

private enum PrefKey {
    static let themeVariant = "settings.themeVariant"
    static let fontSize = "settings.fontSize"
    static let autoplayVideo = "settings.autoplayVideo"
    static let externalEmbeds = "settings.externalEmbeds"
    static let altTextRequired = "settings.altTextRequired"
    static let reduceMotion = "settings.reduceMotion"
    static let openLinksInApp = "settings.openLinksInApp"
    static let postLanguages = "settings.postLanguages"
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

    public var themeVariant: BlueskyTheme.Variant = .light
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

    // MARK: - Notifications

    public var notifyLikes = true
    public var notifyReposts = true
    public var notifyFollows = true
    public var notifyMentions = true
    public var notifyReplies = true
    public var notifyQuotes = true

    // MARK: - State

    public var isSaving = false

    // MARK: - Dependencies

    private let preferences: any PreferencesStore
    let accountStore: any AccountStore

    public init(preferences: any PreferencesStore, accountStore: any AccountStore) {
        self.preferences = preferences
        self.accountStore = accountStore
    }

    // MARK: - Load / save

    public func load() {
        themeVariant = (try? preferences.get(String.self, for: PrefKey.themeVariant))
            .flatMap { BlueskyTheme.Variant(rawValue: $0) } ?? .light
        fontSize = (try? preferences.get(Double.self, for: PrefKey.fontSize)) ?? 16
        autoplayVideo = (try? preferences.get(Bool.self, for: PrefKey.autoplayVideo)) ?? true
        externalEmbeds = (try? preferences.get(Bool.self, for: PrefKey.externalEmbeds)) ?? true
        altTextRequired = (try? preferences.get(Bool.self, for: PrefKey.altTextRequired)) ?? false
        reduceMotion = (try? preferences.get(Bool.self, for: PrefKey.reduceMotion)) ?? false
        openLinksInApp = (try? preferences.get(Bool.self, for: PrefKey.openLinksInApp)) ?? true
        postLanguages = (try? preferences.get([String].self, for: PrefKey.postLanguages)) ?? ["en"]
        notifyLikes = (try? preferences.get(Bool.self, for: PrefKey.notifyLikes)) ?? true
        notifyReposts = (try? preferences.get(Bool.self, for: PrefKey.notifyReposts)) ?? true
        notifyFollows = (try? preferences.get(Bool.self, for: PrefKey.notifyFollows)) ?? true
        notifyMentions = (try? preferences.get(Bool.self, for: PrefKey.notifyMentions)) ?? true
        notifyReplies = (try? preferences.get(Bool.self, for: PrefKey.notifyReplies)) ?? true
        notifyQuotes = (try? preferences.get(Bool.self, for: PrefKey.notifyQuotes)) ?? true
    }

    public func save() {
        try? preferences.set(themeVariant.rawValue, for: PrefKey.themeVariant)
        try? preferences.set(fontSize, for: PrefKey.fontSize)
        try? preferences.set(autoplayVideo, for: PrefKey.autoplayVideo)
        try? preferences.set(externalEmbeds, for: PrefKey.externalEmbeds)
        try? preferences.set(altTextRequired, for: PrefKey.altTextRequired)
        try? preferences.set(reduceMotion, for: PrefKey.reduceMotion)
        try? preferences.set(openLinksInApp, for: PrefKey.openLinksInApp)
        try? preferences.set(postLanguages, for: PrefKey.postLanguages)
        try? preferences.set(notifyLikes, for: PrefKey.notifyLikes)
        try? preferences.set(notifyReposts, for: PrefKey.notifyReposts)
        try? preferences.set(notifyFollows, for: PrefKey.notifyFollows)
        try? preferences.set(notifyMentions, for: PrefKey.notifyMentions)
        try? preferences.set(notifyReplies, for: PrefKey.notifyReplies)
        try? preferences.set(notifyQuotes, for: PrefKey.notifyQuotes)
    }

    public func setTheme(_ variant: BlueskyTheme.Variant) {
        themeVariant = variant
        try? preferences.set(variant.rawValue, for: PrefKey.themeVariant)
    }
}
