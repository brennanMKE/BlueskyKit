import Foundation

/// Topic interests mirror the React Native client's static list at
/// `Bluesky-ReactNative/src/lib/interests.ts`. Keep in sync with that file.
///
/// The `tag` value is what gets written to
/// `app.bsky.actor.defs#interestsPref` and what the server uses to seed the
/// Discover algorithm. Display names match RN's `useInterestsDisplayNames`.
public struct OnboardingInterest: Identifiable, Hashable, Sendable {
    public let tag: String
    public let displayName: String

    public var id: String { tag }
}

public enum OnboardingInterests {
    /// Order matches RN's alphabetical list. Keep this canonical: the server
    /// uses the tag values to build per-interest suggestion buckets.
    public static let all: [OnboardingInterest] = [
        .init(tag: "animals",     displayName: "Animals"),
        .init(tag: "art",         displayName: "Art"),
        .init(tag: "books",       displayName: "Books"),
        .init(tag: "comedy",      displayName: "Comedy"),
        .init(tag: "comics",      displayName: "Comics"),
        .init(tag: "culture",     displayName: "Culture"),
        .init(tag: "dev",         displayName: "Software Dev"),
        .init(tag: "education",   displayName: "Education"),
        .init(tag: "finance",     displayName: "Finance"),
        .init(tag: "food",        displayName: "Food"),
        .init(tag: "gaming",      displayName: "Video Games"),
        .init(tag: "journalism",  displayName: "Journalism"),
        .init(tag: "movies",      displayName: "Movies"),
        .init(tag: "music",       displayName: "Music"),
        .init(tag: "nature",      displayName: "Nature"),
        .init(tag: "news",        displayName: "News"),
        .init(tag: "pets",        displayName: "Pets"),
        .init(tag: "photography", displayName: "Photography"),
        .init(tag: "politics",    displayName: "Politics"),
        .init(tag: "science",     displayName: "Science"),
        .init(tag: "sports",      displayName: "Sports"),
        .init(tag: "tech",        displayName: "Tech"),
        .init(tag: "tv",          displayName: "TV"),
        .init(tag: "writers",     displayName: "Writers"),
    ]

    /// Convenience: lookup by tag, falling back to a capitalized form for any
    /// future server-side tag we haven't added a display name for yet.
    public static func displayName(for tag: String) -> String {
        if let match = all.first(where: { $0.tag == tag }) {
            return match.displayName
        }
        return tag.prefix(1).uppercased() + tag.dropFirst()
    }
}
