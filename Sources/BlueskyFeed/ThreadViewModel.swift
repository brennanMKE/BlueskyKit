import Foundation
import Observation
import BlueskyCore
import BlueskyKit

/// Per-view reply sort. Mirrors the lexicon values carried by
/// `app.bsky.actor.defs#threadViewPref.sort` and the RN `HeaderDropdown`
/// reply-sort options. Values are stable across server boundaries —
/// `rawValue` is the lexicon string used by `getPreferences` /
/// `putPreferences`.
public enum ThreadSort: String, CaseIterable, Sendable, Hashable {
    /// Engagement-weighted ("Hot"). Server-side default.
    case hotness
    /// Highest like count first ("Top").
    case mostLikes = "most-likes"
    /// Most recent first.
    case newest
    /// Oldest first (chronological).
    case oldest
    /// Random order; reseeded per `setSort` invocation.
    case random

    /// Localized label shown in the dropdown menu. Order in
    /// `displayOrder` matches RN's full lexicon set
    /// (Hot, Top, Newest, Oldest, Random).
    public var label: String {
        switch self {
        case .hotness: return "Hot"
        case .mostLikes: return "Top"
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .random: return "Random"
        }
    }

    /// Render order for the menu — RN's `HeaderDropdown` exposes
    /// `top / oldest / newest`; the issue spec for #0140 calls for the
    /// full lexicon set in this order.
    public static let displayOrder: [ThreadSort] = [
        .hotness, .mostLikes, .newest, .oldest, .random
    ]

    /// Lexicon string ↔ enum, with a fallback for unknown server
    /// values. Mirrors the tolerance in `ThreadViewPref` (free-form
    /// string with UI mapping known values).
    public init(lexiconValue: String) {
        self = ThreadSort(rawValue: lexiconValue) ?? .hotness
    }
}

@Observable
public final class ThreadViewModel {

    public var thread: ThreadViewPost?
    public var isLoading = false
    public var errorMessage: String?

    /// Active reply-sort. Seeded from the user's
    /// `app.bsky.actor.defs#threadViewPref.sort` preference on first
    /// `load()`, then overridden per-session by `setSort(_:)`.
    /// Per-session only — sort changes do not write back to
    /// `putPreferences`; the per-user default is owned by the Thread
    /// Preferences settings screen (#0116).
    public var sort: ThreadSort = .hotness

    /// URIs of nested-reply nodes the user has explicitly expanded by
    /// tapping a "Show N more replies" button (#0141). Drives the tree
    /// renderer in `ThreadView` so a deep branch only walks past
    /// `MAX_TREE_DEPTH` once the user opts in. Mutated via
    /// `toggleExpanded(_:)`.
    public var expandedNodes: Set<ATURI> = []

    /// Random seed reshuffled each time the user picks `random`. Drives
    /// `sortedReplies` deterministically within a session so SwiftUI
    /// list diffing doesn't churn between renders.
    private var randomSeed: UInt64 = 0

    /// Whether the per-user default sort has been hydrated. `load()`
    /// writes this to `true` after reading `getPreferences`; subsequent
    /// `load()` calls (refresh) keep the user's per-session override.
    private var didHydrateDefault = false

    private let network: any NetworkClient
    private let uri: ATURI

    public init(network: any NetworkClient, uri: ATURI) {
        self.network = network
        self.uri = uri
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Hydrate the user's default sort once, on first load. Failures
        // here are non-fatal — the dropdown falls back to `.hotness`.
        if !didHydrateDefault {
            await hydrateDefaultSort()
            didHydrateDefault = true
        }

        do {
            let params: [String: String] = [
                "uri": uri.rawValue,
                "depth": "6",
                "parentHeight": "80"
            ]
            let response: GetPostThreadResponse = try await network.get(
                lexicon: "app.bsky.feed.getPostThread", params: params
            )
            thread = response.thread
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Mark a reply node as expanded (or collapse it). Used by the
    /// tree renderer to reveal nested replies that sit at or beyond
    /// the indentation cap.
    public func toggleExpanded(_ uri: ATURI) {
        if expandedNodes.contains(uri) {
            expandedNodes.remove(uri)
        } else {
            expandedNodes.insert(uri)
        }
    }

    /// Switch the active reply-sort. Pure UI-state update; the loaded
    /// thread tree is re-ordered via `sortedReplies`. No network call.
    public func setSort(_ newValue: ThreadSort) {
        guard newValue != sort else {
            // Re-tapping `random` should reshuffle.
            if newValue == .random {
                randomSeed = UInt64.random(in: 0..<UInt64.max)
            }
            return
        }
        sort = newValue
        if newValue == .random {
            randomSeed = UInt64.random(in: 0..<UInt64.max)
        }
    }

    /// Direct replies of the focal post, ordered per the active
    /// `sort`. Non-`.post` replies (notFound / blocked / unknown) keep
    /// their server position at the end so the focal-row → reply
    /// relationship stays predictable.
    public var sortedReplies: [ThreadViewPost] {
        guard case .post(let tp) = thread, let replies = tp.replies else {
            return []
        }
        return Self.sort(replies, by: sort, randomSeed: randomSeed)
    }

    /// URIs of replies the OP has explicitly hidden via the focal post's
    /// threadgate (`record.hiddenReplies`). Drives the "Hidden replies"
    /// divider in `ThreadView`. Mirrors RN's
    /// `useMergedThreadgateHiddenReplies` (minus the optimistic
    /// add/remove overlay, which lives in the threadgate-edit flow). Only
    /// the focal post's threadgate is consulted — nested posts in a
    /// thread can carry their own threadgates, but for hide-replies UX
    /// we follow RN and use the root.
    public var hiddenReplyURIs: Set<ATURI> {
        guard case .post(let tp) = thread,
              let uris = tp.threadgate?.record?.hiddenReplies else {
            return []
        }
        return Set(uris)
    }

    // MARK: - Internals

    private func hydrateDefaultSort() async {
        do {
            let resp: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            if let pref = resp.threadView {
                self.sort = ThreadSort(lexiconValue: pref.sort)
            }
        } catch {
            // Silent fallback — the dropdown will sit at `.hotness`.
        }
    }

    /// Pure sorting helper. Internal/static so tests can call it
    /// without standing up a `ThreadViewModel`.
    static func sort(
        _ replies: [ThreadViewPost],
        by sort: ThreadSort,
        randomSeed: UInt64
    ) -> [ThreadViewPost] {
        // Partition: real posts go through the comparator; non-post
        // sentinels (notFound / blocked / unknown) keep server order
        // and trail the sorted posts.
        var posts: [(idx: Int, node: ThreadViewPost, post: PostView)] = []
        var sentinels: [ThreadViewPost] = []
        for (idx, node) in replies.enumerated() {
            if case .post(let tp) = node {
                posts.append((idx, node, tp.post))
            } else {
                sentinels.append(node)
            }
        }

        switch sort {
        case .mostLikes:
            posts.sort { lhs, rhs in
                if lhs.post.likeCount != rhs.post.likeCount {
                    return lhs.post.likeCount > rhs.post.likeCount
                }
                // Tie-break: newer first, then original order.
                if lhs.post.indexedAt != rhs.post.indexedAt {
                    return lhs.post.indexedAt > rhs.post.indexedAt
                }
                return lhs.idx < rhs.idx
            }
        case .newest:
            posts.sort { lhs, rhs in
                if lhs.post.indexedAt != rhs.post.indexedAt {
                    return lhs.post.indexedAt > rhs.post.indexedAt
                }
                return lhs.idx < rhs.idx
            }
        case .oldest:
            posts.sort { lhs, rhs in
                if lhs.post.indexedAt != rhs.post.indexedAt {
                    return lhs.post.indexedAt < rhs.post.indexedAt
                }
                return lhs.idx < rhs.idx
            }
        case .hotness:
            // Approximate the appview's "hotness" heuristic:
            // engagement (likes + 2·reposts + 4·replies) decayed by
            // age. Server-side `hotness` is the source of truth — this
            // is a best-effort client fallback when a `?sort=hotness`
            // refetch is unavailable on the V1 lexicon we ship.
            let now = Date()
            posts.sort { lhs, rhs in
                let lh = Self.hotnessScore(lhs.post, now: now)
                let rh = Self.hotnessScore(rhs.post, now: now)
                if lh != rh { return lh > rh }
                return lhs.idx < rhs.idx
            }
        case .random:
            var rng = SeededRNG(seed: randomSeed == 0 ? 0xDEADBEEF : randomSeed)
            posts.shuffle(using: &rng)
        }

        return posts.map(\.node) + sentinels
    }

    /// Engagement-weighted score with a gentle age decay. Mirrors the
    /// shape (not the exact constants) of the appview's hotness rank:
    /// `engagement / (hours_since_indexed + 2)^1.8`.
    private static func hotnessScore(_ post: PostView, now: Date) -> Double {
        let engagement = Double(post.likeCount)
            + 2.0 * Double(post.repostCount)
            + 4.0 * Double(post.replyCount)
        let hours = max(0.0, now.timeIntervalSince(post.indexedAt) / 3600.0)
        return (engagement + 1.0) / pow(hours + 2.0, 1.8)
    }
}

/// Tiny seeded RNG — splitmix64 — used so `random` sort is stable
/// within a session (re-renders don't reshuffle) but reseeds on the
/// next user tap.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}
