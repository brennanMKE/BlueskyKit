import Foundation
import BlueskyCore

// MARK: - Draft

/// A persisted snapshot of in-progress composer state. Mirrors RN's
/// `view/com/composer/drafts/state/schema.ts` (`DraftSummary`) but pared down
/// to the subset of fields the SwiftUI composer actually drives.
///
/// Persistence shape:
///   - JSON-encoded into `UserDefaults` under `bluesky.composer.drafts` as an
///     array of `Draft`. Sized for tens-of-drafts at most — if a future Bluesky
///     parity bump pushes that volume up, swap the backing store for SwiftData.
///   - Image bytes are intentionally **not** persisted (see Gotchas in #0100).
///     The composer re-opens drafts with text + GIF + threadgate intact, but
///     image attachments are dropped. RN persists local file paths and re-loads
///     from the system media library; the SwiftUI composer holds raw `Data`
///     blobs from `PHPickerResult` / `NSOpenPanel` which have no stable handle
///     to round-trip back into a `PHPickerItem`.
public struct Draft: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var text: String
    public let createdAt: Date
    public var updatedAt: Date
    /// Set when drafting a reply — the parent post URI.
    public var replyTo: ATURI?
    /// Set when drafting a quote — the quoted post URI.
    public var quotedPostURI: ATURI?
    public var selectedLanguages: [String]
    public var selfLabels: Set<String>
    /// Codable mirror of `ThreadgateAllowSelection`. The runtime value type is
    /// an enum with associated values; flattening it to a stable wire form
    /// here insulates persisted drafts from future enum-case additions.
    public var threadgateAllow: ThreadgateAllowSelectionSnapshot
    public var quotesEnabled: Bool
    /// Optional thumbnail metadata for image attachments. **Currently always
    /// nil** — image persistence is deferred (see #0100 Gotchas). Reserved on
    /// the wire so a future change to persist thumbnails doesn't bump the
    /// draft schema.
    public var imagePreviews: [DraftImage]?
    /// Re-opens with the previously-selected GIF intact (`TenorGif` is small
    /// and Codable as of #0100).
    public var selectedGIF: TenorGif?
    /// Reserved for thread-draft persistence. **Currently always nil** — see
    /// the deferred-thread-draft Gotcha on #0100.
    public var additionalPosts: [DraftPost]?

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        replyTo: ATURI? = nil,
        quotedPostURI: ATURI? = nil,
        selectedLanguages: [String] = ["en"],
        selfLabels: Set<String> = [],
        threadgateAllow: ThreadgateAllowSelectionSnapshot = .everyone,
        quotesEnabled: Bool = true,
        imagePreviews: [DraftImage]? = nil,
        selectedGIF: TenorGif? = nil,
        additionalPosts: [DraftPost]? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.replyTo = replyTo
        self.quotedPostURI = quotedPostURI
        self.selectedLanguages = selectedLanguages
        self.selfLabels = selfLabels
        self.threadgateAllow = threadgateAllow
        self.quotesEnabled = quotesEnabled
        self.imagePreviews = imagePreviews
        self.selectedGIF = selectedGIF
        self.additionalPosts = additionalPosts
    }
}

// MARK: - DraftImage

/// Thumbnail-sized JPEG of an image attachment, plus its alt text. Reserved
/// for a future image-persistence pass — the current composer never writes
/// this (see #0100 Gotchas).
public struct DraftImage: Codable, Sendable, Equatable {
    public let id: UUID
    public let thumbnailData: Data
    public let altText: String

    public init(id: UUID = UUID(), thumbnailData: Data, altText: String = "") {
        self.id = id
        self.thumbnailData = thumbnailData
        self.altText = altText
    }
}

// MARK: - DraftPost

/// Reserved for thread-draft persistence (a thread-with-multiple-posts draft).
/// Today the composer flattens additional posts into a `[String]` and we don't
/// persist them — see the thread-draft Gotcha on #0100.
public struct DraftPost: Codable, Sendable, Equatable {
    public let id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

// MARK: - ThreadgateAllowSelectionSnapshot

/// Codable wire-format mirror of `ThreadgateAllowSelection`. The runtime enum
/// uses associated values for the granular case which Codable's auto-synthesis
/// does encode, but the resulting JSON is brittle to enum-case reordering
/// (Codable encodes the case name as a key plus the payload as a tuple). This
/// snapshot type is a hand-rolled struct with explicit `kind` discriminator so
/// adding a new restriction kind in the future doesn't invalidate persisted
/// drafts.
public struct ThreadgateAllowSelectionSnapshot: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case everyone
        case nobody
        case granular
    }

    public let kind: Kind
    public let mention: Bool
    public let following: Bool
    public let follower: Bool
    public let listURIs: [ATURI]

    public init(
        kind: Kind,
        mention: Bool = false,
        following: Bool = false,
        follower: Bool = false,
        listURIs: [ATURI] = []
    ) {
        self.kind = kind
        self.mention = mention
        self.following = following
        self.follower = follower
        self.listURIs = listURIs
    }

    public static let everyone = ThreadgateAllowSelectionSnapshot(kind: .everyone)
    public static let nobody = ThreadgateAllowSelectionSnapshot(kind: .nobody)

    /// Convert from the live runtime selection to a persistable snapshot.
    public init(from selection: ThreadgateAllowSelection) {
        switch selection {
        case .everyone:
            self = .everyone
        case .nobody:
            self = .nobody
        case .granular(let mention, let following, let follower, let listURIs):
            self.init(
                kind: .granular,
                mention: mention,
                following: following,
                follower: follower,
                listURIs: listURIs
            )
        }
    }

    /// Convert back to the runtime selection for restoring into a composer.
    public func toSelection() -> ThreadgateAllowSelection {
        switch kind {
        case .everyone:
            return .everyone
        case .nobody:
            return .nobody
        case .granular:
            return .granular(
                mention: mention,
                following: following,
                follower: follower,
                listURIs: listURIs
            )
        }
    }
}
