import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "ProfileStore")

// MARK: - ProfileTab

public enum ProfileTab: String, CaseIterable, Identifiable {
    // Tab order matches the React Native reference (#0086, #0206):
    // Posts · Replies · Media · Videos · Likes · Feeds · Starter Packs · Lists
    // (`Profile.tsx` sectionTitles puts Starter Packs between Feeds and the
    // trailing Lists tab).
    case posts, replies, media, videos, likes, feeds, starterPacks, lists
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .posts:        "Posts"
        case .replies:      "Replies"
        case .media:        "Media"
        case .videos:       "Videos"
        case .likes:        "Likes"
        case .feeds:        "Feeds"
        case .starterPacks: "Starter Packs"
        case .lists:        "Lists"
        }
    }
}

// MARK: - ProfileStoring

public protocol ProfileStoring: AnyObject, Observable, Sendable {
    var profile: ProfileDetailed? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    var actorFeeds: [GeneratorView] { get }
    var actorLists: [ListView] { get }
    var actorStarterPacks: [StarterPackBasic] { get }
    var knownFollowers: [ProfileView] { get }

    func posts(for tab: ProfileTab) -> [FeedViewPost]
    func isLoadingFeed(for tab: ProfileTab) -> Bool

    func loadProfile(actorDID: DID) async
    func loadFeed(tab: ProfileTab, actorDID: DID) async
    func loadMoreFeed(tab: ProfileTab, actorDID: DID) async
    func loadFeeds(actorDID: DID) async
    func loadLists(actorDID: DID) async
    /// Loads the actor's starter packs for the Starter Packs tab (#0206).
    /// Unlike `loadFeeds`/`loadLists` this re-fetches on every call (with an
    /// in-flight guard) so the tab reflects a pack created or deleted during
    /// the session as soon as the user re-enters it or pulls to refresh.
    func loadStarterPacks(actorDID: DID) async
    func follow() async
    func unfollow() async
    func block() async
    func unblock() async
    func mute() async
    func unmute() async
    func updateProfile(displayName: String?, description: String?) async throws

    // MARK: Per-post interactions (#0159)
    //
    // Mirror the like / repost / bookmark mutation surface of `FeedStore` so
    // that post rows on the Profile screen tabs (Posts / Replies / Media /
    // Videos / Likes) get functional action-bar callbacks instead of the
    // previous no-op `PostCard.Actions()`. Implementation is a leaner
    // duplicate of `FeedStore`'s logic: we don't currently freshen viewer
    // state from `getPosts` before toggling — the profile feed is re-fetched
    // on tab switch which is usually enough, and adding the freshener here
    // would require lifting the `freshenedPost` helper into a shared
    // location. Acceptable trade-off per the issue spec; revisit if the
    // staleness-revert behavior in #0041 starts surfacing on profile rows
    // too.
    func toggleLike(post: PostView) async
    func toggleRepost(post: PostView) async
    func bookmark(post: PostView) async
    func unbookmark(post: PostView) async
}

// MARK: - ProfileStore

@Observable
public final class ProfileStore: ProfileStoring {

    public private(set) var profile: ProfileDetailed?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var actorFeeds: [GeneratorView] = []
    public private(set) var actorLists: [ListView] = []
    public private(set) var actorStarterPacks: [StarterPackBasic] = []
    public private(set) var knownFollowers: [ProfileView] = []

    /// In-flight guard for `loadStarterPacks` (which always re-fetches).
    private var starterPacksLoading = false

    private var tabPosts: [ProfileTab: [FeedViewPost]] = [:]
    private var tabCursors: [ProfileTab: String?] = [:]
    private var tabLoading: [ProfileTab: Bool] = [:]

    /// Post URIs whose like state is currently being mutated.
    /// Mirrors `FeedStore`'s double-tap guard.
    private var likeInFlight: Set<ATURI> = []
    /// Post URIs whose repost state is currently being mutated.
    private var repostInFlight: Set<ATURI> = []
    /// Post URIs whose bookmark state is currently being mutated.
    private var bookmarkInFlight: Set<ATURI> = []
    /// Guards the viewer-relationship mutations (follow/unfollow/block/unblock/
    /// mute/unmute) against re-entrant taps. Unlike the per-post sets above
    /// these target a single subject (the profile), so one flag suffices.
    /// Without it, overlapping taps fired duplicate create/delete records and a
    /// failed call could revert to a half-applied `original` snapshot (#0228).
    private var relationshipInFlight = false

    private let network: any NetworkClient
    private let accountStore: any AccountStore

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.network = network
        self.accountStore = accountStore
    }

    public func posts(for tab: ProfileTab) -> [FeedViewPost] { tabPosts[tab] ?? [] }
    public func isLoadingFeed(for tab: ProfileTab) -> Bool { tabLoading[tab] ?? false }

    // MARK: - Load profile

    public func loadProfile(actorDID: DID) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            profile = try await network.get(
                lexicon: "app.bsky.actor.getProfile",
                params: ["actor": actorDID.rawValue]
            )
        } catch {
            logger.error("profile fetch error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        do {
            let response: GetKnownFollowersResponse = try await network.get(
                lexicon: "app.bsky.graph.getKnownFollowers",
                params: ["actor": actorDID.rawValue, "limit": "3"]
            )
            knownFollowers = Array(response.followers.prefix(3))
        } catch {
            logger.debug("getKnownFollowers unavailable or error: \(error, privacy: .public)")
            // graceful degradation: knownFollowers stays empty
        }
    }

    // MARK: - Load feeds / lists tabs

    public func loadFeeds(actorDID: DID) async {
        guard actorFeeds.isEmpty else { return }
        do {
            let response: GetActorFeedsResponse = try await network.get(
                lexicon: "app.bsky.feed.getActorFeeds",
                params: ["actor": actorDID.rawValue, "limit": "50"]
            )
            actorFeeds = response.feeds
        } catch {
            logger.error("getActorFeeds error: \(error, privacy: .public)")
        }
    }

    public func loadLists(actorDID: DID) async {
        guard actorLists.isEmpty else { return }
        do {
            let response: GetListsResponse = try await network.get(
                lexicon: "app.bsky.graph.getLists",
                params: ["actor": actorDID.rawValue, "limit": "50"]
            )
            actorLists = response.lists
        } catch {
            logger.error("getLists error: \(error, privacy: .public)")
        }
    }

    public func loadStarterPacks(actorDID: DID) async {
        guard !starterPacksLoading else { return }
        starterPacksLoading = true
        defer { starterPacksLoading = false }
        do {
            // RN pages `getActorStarterPacks` at 10; the profile tabs here
            // use a single 50-item fetch like `loadFeeds`/`loadLists`.
            let response: GetActorStarterPacksResponse = try await network.get(
                lexicon: "app.bsky.graph.getActorStarterPacks",
                params: ["actor": actorDID.rawValue, "limit": "50"]
            )
            actorStarterPacks = response.starterPacks
        } catch {
            logger.error("getActorStarterPacks error: \(error, privacy: .public)")
        }
    }

    // MARK: - Load feed tab

    public func loadFeed(tab: ProfileTab, actorDID: DID) async {
        guard tabLoading[tab] != true, tabPosts[tab] == nil else { return }
        tabLoading[tab] = true
        defer { tabLoading[tab] = false }
        do {
            let response: FeedResponse = try await fetchTab(tab, actorDID: actorDID, cursor: nil)
            tabPosts[tab] = response.feed
            tabCursors[tab] = response.cursor
        } catch {}
    }

    public func loadMoreFeed(tab: ProfileTab, actorDID: DID) async {
        guard tabLoading[tab] != true else { return }
        guard let cursor = tabCursors[tab] ?? nil else { return }
        tabLoading[tab] = true
        defer { tabLoading[tab] = false }
        do {
            let response: FeedResponse = try await fetchTab(tab, actorDID: actorDID, cursor: cursor)
            tabPosts[tab, default: []].append(contentsOf: response.feed)
            tabCursors[tab] = response.cursor
        } catch {}
    }

    private func fetchTab(_ tab: ProfileTab, actorDID: DID, cursor: String?) async throws -> FeedResponse {
        var params: [String: String] = ["actor": actorDID.rawValue, "limit": "50"]
        if let cursor { params["cursor"] = cursor }
        switch tab {
        case .posts:
            // Match the RN reference exactly (#0087): the Posts tab uses the
            // `posts_and_author_threads` filter with `includePins=true`. The
            // PDS surfaces the actor's pinned post (if any) as the first item
            // in the response with `reason` of type
            // `app.bsky.feed.defs#reasonPin`. The same post may appear again
            // later in chronological order — we render both copies, no
            // de-duplication, matching RN.
            params["filter"] = "posts_and_author_threads"
            params["includePins"] = "true"
            return try await network.get(lexicon: "app.bsky.feed.getAuthorFeed", params: params)
        case .replies:
            params["filter"] = "posts_with_replies"
            return try await network.get(lexicon: "app.bsky.feed.getAuthorFeed", params: params)
        case .media:
            params["filter"] = "posts_with_media"
            return try await network.get(lexicon: "app.bsky.feed.getAuthorFeed", params: params)
        case .videos:
            // #0086: server-side `posts_with_video` filter, matching the React
            // Native reference (`state/queries/post-feed.ts` whitelists the
            // value, and `Profile.tsx` builds the videos feed as
            // `author|<did>|posts_with_video`). Falls back gracefully if the
            // PDS doesn't recognize it — the request just returns nothing.
            params["filter"] = "posts_with_video"
            return try await network.get(lexicon: "app.bsky.feed.getAuthorFeed", params: params)
        case .likes:
            return try await network.get(lexicon: "app.bsky.feed.getActorLikes", params: params)
        case .feeds, .starterPacks, .lists:
            // Feeds / Starter Packs / Lists tabs use dedicated load methods;
            // this path is never reached.
            throw URLError(.unsupportedURL)
        }
    }

    // MARK: - Follow / Unfollow

    public func follow() async {
        guard !relationshipInFlight else { return }
        relationshipInFlight = true
        defer { relationshipInFlight = false }
        guard let profile else { return }
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("follow: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }
        guard let viewerDID else { return }
        let original = self.profile
        let pendingURI = ATURI(rawValue: "pending:follow")
        self.profile = profile
            .adjustingFollowersCount(by: 1)
            .withViewer { v in ProfileViewerState(
                muted: v?.muted, mutedByList: v?.mutedByList,
                blockedBy: v?.blockedBy, blocking: v?.blocking,
                following: pendingURI, followedBy: v?.followedBy
            )}
        do {
            let req = CreateRecordRequest(
                repo: viewerDID.rawValue,
                collection: "app.bsky.graph.follow",
                record: FollowRecord(subject: profile.did)
            )
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord", body: req
            )
            let cur = self.profile ?? profile
            self.profile = cur.withViewer { v in ProfileViewerState(
                muted: v?.muted, mutedByList: v?.mutedByList,
                blockedBy: v?.blockedBy, blocking: v?.blocking,
                following: resp.uri, followedBy: v?.followedBy
            )}
        } catch {
            self.profile = original
        }
    }

    public func unfollow() async {
        guard !relationshipInFlight else { return }
        relationshipInFlight = true
        defer { relationshipInFlight = false }
        guard let profile,
              let followURI = profile.viewer?.following,
              let rkey = followURI.rkey else { return }
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("unfollow: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }
        guard let viewerDID else { return }
        let original = self.profile
        self.profile = profile
            .adjustingFollowersCount(by: -1)
            .withViewer { v in ProfileViewerState(
                muted: v?.muted, mutedByList: v?.mutedByList,
                blockedBy: v?.blockedBy, blocking: v?.blocking,
                following: nil, followedBy: v?.followedBy
            )}
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: DeleteRecordRequest(repo: viewerDID.rawValue, collection: "app.bsky.graph.follow", rkey: rkey)
            )
        } catch {
            self.profile = original
        }
    }

    // MARK: - Block / Unblock

    public func block() async {
        guard !relationshipInFlight else { return }
        relationshipInFlight = true
        defer { relationshipInFlight = false }
        guard let profile else { return }
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("block: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }
        guard let viewerDID else { return }
        let original = self.profile
        let pendingURI = ATURI(rawValue: "pending:block")
        self.profile = profile.withViewer { v in ProfileViewerState(
            muted: v?.muted, mutedByList: v?.mutedByList,
            blockedBy: v?.blockedBy, blocking: pendingURI,
            following: v?.following, followedBy: v?.followedBy
        )}
        do {
            let req = CreateRecordRequest(
                repo: viewerDID.rawValue,
                collection: "app.bsky.graph.block",
                record: BlockRecord(subject: profile.did)
            )
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord", body: req
            )
            let cur = self.profile ?? profile
            self.profile = cur.withViewer { v in ProfileViewerState(
                muted: v?.muted, mutedByList: v?.mutedByList,
                blockedBy: v?.blockedBy, blocking: resp.uri,
                following: v?.following, followedBy: v?.followedBy
            )}
        } catch {
            self.profile = original
        }
    }

    public func unblock() async {
        guard !relationshipInFlight else { return }
        relationshipInFlight = true
        defer { relationshipInFlight = false }
        guard let profile,
              let blockURI = profile.viewer?.blocking,
              let rkey = blockURI.rkey else { return }
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("unblock: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }
        guard let viewerDID else { return }
        let original = self.profile
        self.profile = profile.withViewer { v in ProfileViewerState(
            muted: v?.muted, mutedByList: v?.mutedByList,
            blockedBy: v?.blockedBy, blocking: nil,
            following: v?.following, followedBy: v?.followedBy
        )}
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: DeleteRecordRequest(repo: viewerDID.rawValue, collection: "app.bsky.graph.block", rkey: rkey)
            )
        } catch {
            self.profile = original
        }
    }

    // MARK: - Mute / Unmute

    public func mute() async {
        guard !relationshipInFlight else { return }
        relationshipInFlight = true
        defer { relationshipInFlight = false }
        guard let profile else { return }
        let original = self.profile
        self.profile = profile.withViewer { v in ProfileViewerState(
            muted: true, mutedByList: v?.mutedByList,
            blockedBy: v?.blockedBy, blocking: v?.blocking,
            following: v?.following, followedBy: v?.followedBy
        )}
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.graph.muteActor", body: MuteActorRequest(actor: profile.did)
            )
        } catch {
            self.profile = original
        }
    }

    public func unmute() async {
        guard !relationshipInFlight else { return }
        relationshipInFlight = true
        defer { relationshipInFlight = false }
        guard let profile else { return }
        let original = self.profile
        self.profile = profile.withViewer { v in ProfileViewerState(
            muted: false, mutedByList: v?.mutedByList,
            blockedBy: v?.blockedBy, blocking: v?.blocking,
            following: v?.following, followedBy: v?.followedBy
        )}
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.graph.unmuteActor", body: MuteActorRequest(actor: profile.did)
            )
        } catch {
            self.profile = original
        }
    }

    // MARK: - Per-post interactions (#0159)

    public func toggleLike(post: PostView) async {
        guard likeInFlight.insert(post.uri).inserted else { return }
        defer { likeInFlight.remove(post.uri) }
        let live = currentPost(for: post.uri) ?? post
        if live.viewer?.like != nil {
            await performUnlike(post: live)
        } else {
            await performLike(post: live)
        }
    }

    public func toggleRepost(post: PostView) async {
        guard repostInFlight.insert(post.uri).inserted else { return }
        defer { repostInFlight.remove(post.uri) }
        let live = currentPost(for: post.uri) ?? post
        if live.viewer?.repost != nil {
            await performUnrepost(post: live)
        } else {
            await performRepost(post: live)
        }
    }

    public func bookmark(post: PostView) async {
        guard bookmarkInFlight.insert(post.uri).inserted else { return }
        defer { bookmarkInFlight.remove(post.uri) }
        let live = currentPost(for: post.uri) ?? post
        guard live.viewer?.bookmarked != true else { return }
        updatePost(uri: post.uri) { $0.withBookmarked(true) }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.bookmark.createBookmark",
                body: CreateBookmarkRequest(post: live)
            )
        } catch {
            logger.error("bookmark failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withBookmarked(false) }
        }
    }

    public func unbookmark(post: PostView) async {
        guard bookmarkInFlight.insert(post.uri).inserted else { return }
        defer { bookmarkInFlight.remove(post.uri) }
        updatePost(uri: post.uri) { $0.withBookmarked(false) }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.bookmark.deleteBookmark",
                body: DeleteBookmarkRequest(postURI: post.uri)
            )
        } catch {
            logger.error("unbookmark failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withBookmarked(true) }
        }
    }

    private func performLike(post: PostView) async {
        guard let did = await loadCurrentDID() else { return }
        guard post.viewer?.like == nil else { return }
        updatePost(uri: post.uri) { $0.withLike(ATURI(rawValue: "pending://like")) }
        do {
            let req = CreateRecordRequest(
                repo: did.rawValue,
                collection: "app.bsky.feed.like",
                record: LikeRecord(subject: PostRef(uri: post.uri, cid: post.cid))
            )
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord", body: req
            )
            updatePost(uri: post.uri) { $0.withLike(resp.uri) }
        } catch {
            logger.error("like failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withLike(nil) }
        }
    }

    private func performUnlike(post: PostView) async {
        guard let likeURI = post.viewer?.like,
              let did = await loadCurrentDID(),
              let rkey = likeURI.rkey else { return }
        updatePost(uri: post.uri) { $0.withLike(nil) }
        do {
            let req = DeleteRecordRequest(repo: did.rawValue, collection: "app.bsky.feed.like", rkey: rkey)
            let _: EmptyResponse = try await network.post(lexicon: "com.atproto.repo.deleteRecord", body: req)
        } catch {
            logger.error("unlike failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withLike(likeURI) }
        }
    }

    public func repost(post: PostView) async {
        guard repostInFlight.insert(post.uri).inserted else { return }
        defer { repostInFlight.remove(post.uri) }
        await performRepost(post: post)
    }

    private func performRepost(post: PostView) async {
        guard let did = await loadCurrentDID() else { return }
        guard post.viewer?.repost == nil else { return }
        updatePost(uri: post.uri) { $0.withRepost(ATURI(rawValue: "pending://repost")) }
        do {
            let req = CreateRecordRequest(
                repo: did.rawValue,
                collection: "app.bsky.feed.repost",
                record: RepostRecord(subject: PostRef(uri: post.uri, cid: post.cid))
            )
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord", body: req
            )
            updatePost(uri: post.uri) { $0.withRepost(resp.uri) }
        } catch {
            logger.error("repost failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withRepost(nil) }
        }
    }

    private func performUnrepost(post: PostView) async {
        guard let repostURI = post.viewer?.repost,
              let did = await loadCurrentDID(),
              let rkey = repostURI.rkey else { return }
        updatePost(uri: post.uri) { $0.withRepost(nil) }
        do {
            let req = DeleteRecordRequest(repo: did.rawValue, collection: "app.bsky.feed.repost", rkey: rkey)
            let _: EmptyResponse = try await network.post(lexicon: "com.atproto.repo.deleteRecord", body: req)
        } catch {
            logger.error("unrepost failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withRepost(repostURI) }
        }
    }

    /// Returns the most recent `PostView` we have cached for `uri` across any
    /// tab. The same post can appear in multiple tabs (e.g. a media post
    /// shows up under both Posts and Media); we don't try to deduplicate, but
    /// the per-tab `tabPosts` arrays are kept in sync via `updatePost` below.
    private func currentPost(for uri: ATURI) -> PostView? {
        for items in tabPosts.values {
            if let match = items.first(where: { $0.post.uri == uri }) {
                return match.post
            }
        }
        return nil
    }

    /// Apply `transform` to every occurrence of `uri` across every tab so the
    /// optimistic UI flip is visible no matter which tab the user is looking
    /// at when they tap. The same post appearing under both Posts and Media
    /// keeps a consistent like/repost/bookmark state.
    private func updatePost(uri: ATURI, transform: (PostView) -> PostView) {
        for tab in tabPosts.keys {
            guard var items = tabPosts[tab] else { continue }
            var changed = false
            for idx in items.indices where items[idx].post.uri == uri {
                let old = items[idx]
                items[idx] = FeedViewPost(post: transform(old.post), reply: old.reply, reason: old.reason)
                changed = true
            }
            if changed {
                tabPosts[tab] = items
            }
        }
    }

    private func loadCurrentDID() async -> DID? {
        do {
            return try await accountStore.loadCurrentDID()
        } catch {
            logger.error("loadCurrentDID failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Edit profile

    public func updateProfile(displayName: String?, description: String?) async throws {
        guard let viewerDID = try await accountStore.loadCurrentDID() else { return }

        // Read-modify-write the existing `app.bsky.actor.profile` record as raw
        // JSON so avatar, banner, pinnedPost, self-labels, and any unmodeled
        // fields survive. `putRecord` REPLACES the whole record, and the typed
        // `ProfileRecord` only carries displayName/description/labels — writing
        // a fresh one wiped everything else (#0210).
        var fields: [String: JSONValue]
        do {
            let existing: GetRecordResponse<JSONValue> = try await network.get(
                lexicon: "com.atproto.repo.getRecord",
                params: [
                    "repo": viewerDID.rawValue,
                    "collection": "app.bsky.actor.profile",
                    "rkey": "self"
                ]
            )
            fields = existing.value.objectValue ?? [:]
        } catch {
            // No existing record yet (first profile edit) — start fresh.
            logger.debug("updateProfile: getRecord failed, writing a fresh record: \(error.localizedDescription, privacy: .public)")
            fields = [:]
        }

        fields["$type"] = .string("app.bsky.actor.profile")
        // Assigning nil removes the key, so clearing a field omits it (matching
        // the record's "absent when empty" convention) rather than writing "".
        fields["displayName"] = displayName.map(JSONValue.string)
        fields["description"] = description.map(JSONValue.string)

        let req = PutRecordRequest(
            repo: viewerDID.rawValue,
            collection: "app.bsky.actor.profile",
            rkey: "self",
            record: JSONValue.object(fields)
        )
        let _: EmptyResponse = try await network.post(
            lexicon: "com.atproto.repo.putRecord", body: req
        )
        await loadProfile(actorDID: viewerDID)
    }
}

// MARK: - PostView mutation helpers (#0159, optimistic updates)
//
// These mirror the file-private helpers in `BlueskyFeed/FeedViewModel.swift`.
// Duplicated rather than shared because moving them into BlueskyCore would
// require BlueskyCore to take on optimistic-UI vocabulary that doesn't
// belong in a pure data-model layer, and lifting them into BlueskyKit was
// rejected — the helpers are tied to a specific PostView shape rather than a
// generic protocol. If a third Layer-3 module ends up needing them, fold
// them into a shared `BlueskyUI` extension.

private extension PostView {
    func withLike(_ likeURI: ATURI?) -> PostView {
        let wasLiked = viewer?.like != nil
        let newCount = wasLiked && likeURI == nil ? max(0, likeCount - 1)
                     : !wasLiked && likeURI != nil ? likeCount + 1
                     : likeCount
        let v = PostViewerState(
            like: likeURI,
            repost: viewer?.repost,
            threadMuted: viewer?.threadMuted,
            replyDisabled: viewer?.replyDisabled,
            bookmarked: viewer?.bookmarked
        )
        return PostView(
            uri: uri, cid: cid, author: author, record: record, embed: embed,
            replyCount: replyCount, repostCount: repostCount,
            likeCount: newCount, quoteCount: quoteCount,
            indexedAt: indexedAt, labels: labels, viewer: v
        )
    }

    func withRepost(_ repostURI: ATURI?) -> PostView {
        let wasReposted = viewer?.repost != nil
        let newCount = wasReposted && repostURI == nil ? max(0, repostCount - 1)
                     : !wasReposted && repostURI != nil ? repostCount + 1
                     : repostCount
        let v = PostViewerState(
            like: viewer?.like,
            repost: repostURI,
            threadMuted: viewer?.threadMuted,
            replyDisabled: viewer?.replyDisabled,
            bookmarked: viewer?.bookmarked
        )
        return PostView(
            uri: uri, cid: cid, author: author, record: record, embed: embed,
            replyCount: replyCount, repostCount: newCount,
            likeCount: likeCount, quoteCount: quoteCount,
            indexedAt: indexedAt, labels: labels, viewer: v
        )
    }

    func withBookmarked(_ bookmarked: Bool) -> PostView {
        let v = PostViewerState(
            like: viewer?.like,
            repost: viewer?.repost,
            threadMuted: viewer?.threadMuted,
            replyDisabled: viewer?.replyDisabled,
            bookmarked: bookmarked
        )
        return PostView(
            uri: uri, cid: cid, author: author, record: record, embed: embed,
            replyCount: replyCount, repostCount: repostCount,
            likeCount: likeCount, quoteCount: quoteCount,
            indexedAt: indexedAt, labels: labels, viewer: v
        )
    }
}

// MARK: - ProfileDetailed mutation helpers

private extension ProfileDetailed {
    func withViewer(_ transform: (ProfileViewerState?) -> ProfileViewerState) -> ProfileDetailed {
        ProfileDetailed(
            did: did, handle: handle, displayName: displayName,
            description: description, avatar: avatar, banner: banner,
            followersCount: followersCount, followsCount: followsCount,
            postsCount: postsCount, labels: labels, associated: associated,
            createdAt: createdAt, indexedAt: indexedAt,
            viewer: transform(viewer)
        )
    }

    func adjustingFollowersCount(by delta: Int) -> ProfileDetailed {
        ProfileDetailed(
            did: did, handle: handle, displayName: displayName,
            description: description, avatar: avatar, banner: banner,
            followersCount: max(0, followersCount + delta), followsCount: followsCount,
            postsCount: postsCount, labels: labels, associated: associated,
            createdAt: createdAt, indexedAt: indexedAt, viewer: viewer
        )
    }
}
