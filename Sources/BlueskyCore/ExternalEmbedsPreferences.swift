import Foundation

// MARK: - ExternalMediaSource

/// Third-party players that may be inline-rendered inside a post's external
/// embed card.
///
/// Mirrors `Bluesky-ReactNative/src/lib/strings/embed-player.ts`
/// (`embedPlayerSources`). Order matches RN's `externalEmbedLabels` so the
/// settings list renders in the same sequence on both clients.
public enum ExternalMediaSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case youtube
    case youtubeShorts
    case vimeo
    case twitch
    case giphy
    case tenor
    case klipy
    case spotify
    case appleMusic
    case soundcloud
    case flickr
    case bandcamp

    public var id: String { rawValue }

    /// Human-readable label shown in the preferences list. Matches RN's
    /// `externalEmbedLabels` map verbatim.
    public var displayName: String {
        switch self {
        case .youtube:       return "YouTube"
        case .youtubeShorts: return "YouTube Shorts"
        case .vimeo:         return "Vimeo"
        case .twitch:        return "Twitch"
        case .giphy:         return "GIPHY"
        case .tenor:         return "Tenor"
        case .klipy:         return "KLIPY"
        case .spotify:       return "Spotify"
        case .appleMusic:    return "Apple Music"
        case .soundcloud:    return "SoundCloud"
        case .flickr:        return "Flickr"
        case .bandcamp:      return "Bandcamp"
        }
    }

    /// SF Symbol fallback glyph. Apple's symbol library doesn't ship vendor
    /// marks, so we pick a category-appropriate glyph for each source.
    public var systemImageName: String {
        switch self {
        case .youtube, .youtubeShorts, .vimeo, .twitch:
            return "play.rectangle"
        case .spotify, .appleMusic, .soundcloud, .bandcamp:
            return "music.note"
        case .giphy, .tenor, .klipy:
            return "sparkles"
        case .flickr:
            return "photo.on.rectangle"
        }
    }
}

// MARK: - ExternalEmbedsPreferences

/// Per-source toggles for inline rendering of external media players.
///
/// RN persists this as `Schema['externalEmbeds']` in local-only preferences
/// (see `Bluesky-ReactNative/src/state/persisted/schema.ts`) — values are
/// `'show' | 'hide' | undefined`. Defaults to `{}`, so any source that has
/// never been toggled by the user reads as **not** showing the inline player.
///
/// We model that semantics with a per-source `Bool` defaulting to `false`.
/// `true` ↔ RN's `'show'`; `false` ↔ RN's `'hide'` or undefined.
public struct ExternalEmbedsPreferences: Codable, Sendable, Equatable {
    public var youtube: Bool
    public var youtubeShorts: Bool
    public var vimeo: Bool
    public var twitch: Bool
    public var giphy: Bool
    public var tenor: Bool
    public var klipy: Bool
    public var spotify: Bool
    public var appleMusic: Bool
    public var soundcloud: Bool
    public var flickr: Bool
    public var bandcamp: Bool

    public init(
        youtube: Bool = false,
        youtubeShorts: Bool = false,
        vimeo: Bool = false,
        twitch: Bool = false,
        giphy: Bool = false,
        tenor: Bool = false,
        klipy: Bool = false,
        spotify: Bool = false,
        appleMusic: Bool = false,
        soundcloud: Bool = false,
        flickr: Bool = false,
        bandcamp: Bool = false
    ) {
        self.youtube = youtube
        self.youtubeShorts = youtubeShorts
        self.vimeo = vimeo
        self.twitch = twitch
        self.giphy = giphy
        self.tenor = tenor
        self.klipy = klipy
        self.spotify = spotify
        self.appleMusic = appleMusic
        self.soundcloud = soundcloud
        self.flickr = flickr
        self.bandcamp = bandcamp
    }

    /// RN default: all sources off (the `{}` default in `defaults.externalEmbeds`).
    public static let `default` = ExternalEmbedsPreferences()

    public subscript(source: ExternalMediaSource) -> Bool {
        get {
            switch source {
            case .youtube:       return youtube
            case .youtubeShorts: return youtubeShorts
            case .vimeo:         return vimeo
            case .twitch:        return twitch
            case .giphy:         return giphy
            case .tenor:         return tenor
            case .klipy:         return klipy
            case .spotify:       return spotify
            case .appleMusic:    return appleMusic
            case .soundcloud:    return soundcloud
            case .flickr:        return flickr
            case .bandcamp:      return bandcamp
            }
        }
        set {
            switch source {
            case .youtube:       youtube = newValue
            case .youtubeShorts: youtubeShorts = newValue
            case .vimeo:         vimeo = newValue
            case .twitch:        twitch = newValue
            case .giphy:         giphy = newValue
            case .tenor:         tenor = newValue
            case .klipy:         klipy = newValue
            case .spotify:       spotify = newValue
            case .appleMusic:    appleMusic = newValue
            case .soundcloud:    soundcloud = newValue
            case .flickr:        flickr = newValue
            case .bandcamp:      bandcamp = newValue
            }
        }
    }
}

// MARK: - Storage

/// Canonical `PreferencesStore` key for the per-source toggles. Exposed so
/// embed renderers (e.g. `PostEmbedView`) can read the same value the
/// settings screen writes.
public enum ExternalEmbedsPreferencesKey {
    public static let storage = "settings.externalEmbeds"
}
