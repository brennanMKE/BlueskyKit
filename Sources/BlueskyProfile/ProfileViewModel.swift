import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class ProfileViewModel {

    public enum ProfileTab: String, CaseIterable, Identifiable {
        case posts, replies, media, likes
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .posts:   "Posts"
            case .replies: "Replies"
            case .media:   "Media"
            case .likes:   "Likes"
            }
        }
    }

    public var profile: ProfileDetailed?
    public var isLoading = false
    public var errorMessage: String?

    private var tabPosts: [ProfileTab: [FeedViewPost]] = [:]
    private var tabCursors: [ProfileTab: String?] = [:]
    private var tabLoading: [ProfileTab: Bool] = [:]

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    public let actorDID: DID

    public init(network: any NetworkClient, accountStore: any AccountStore, actorDID: DID) {
        self.network = network
        self.accountStore = accountStore
        self.actorDID = actorDID
    }

    public func posts(for tab: ProfileTab) -> [FeedViewPost] { tabPosts[tab] ?? [] }
    public func isLoadingFeed(for tab: ProfileTab) -> Bool { tabLoading[tab] ?? false }

    // MARK: - Load profile

    public func loadProfile() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let params = ["actor": actorDID.rawValue]
            profile = try await network.get(lexicon: "app.bsky.actor.getProfile", params: params)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Load feed tab

    public func loadFeed(tab: ProfileTab) async {
        guard tabLoading[tab] != true, tabPosts[tab] == nil else { return }
        tabLoading[tab] = true
        defer { tabLoading[tab] = false }
        do {
            let response: FeedResponse = try await fetchTab(tab, cursor: nil)
            tabPosts[tab] = response.feed
            tabCursors[tab] = response.cursor
        } catch {}
    }

    public func loadMoreFeed(tab: ProfileTab) async {
        guard tabLoading[tab] != true else { return }
        guard let cursor = tabCursors[tab] ?? nil else { return }
        tabLoading[tab] = true
        defer { tabLoading[tab] = false }
        do {
            let response: FeedResponse = try await fetchTab(tab, cursor: cursor)
            tabPosts[tab, default: []].append(contentsOf: response.feed)
            tabCursors[tab] = response.cursor
        } catch {}
    }

    private func fetchTab(_ tab: ProfileTab, cursor: String?) async throws -> FeedResponse {
        var params: [String: String] = ["actor": actorDID.rawValue, "limit": "50"]
        if let cursor { params["cursor"] = cursor }
        switch tab {
        case .posts:
            params["filter"] = "posts_no_replies"
            return try await network.get(lexicon: "app.bsky.feed.getAuthorFeed", params: params)
        case .replies:
            params["filter"] = "posts_with_replies"
            return try await network.get(lexicon: "app.bsky.feed.getAuthorFeed", params: params)
        case .media:
            params["filter"] = "posts_with_media"
            return try await network.get(lexicon: "app.bsky.feed.getAuthorFeed", params: params)
        case .likes:
            return try await network.get(lexicon: "app.bsky.feed.getActorLikes", params: params)
        }
    }

    // MARK: - Follow / Unfollow

    public func follow() async {
        guard let profile else { return }
        guard let viewerDID = try? await accountStore.loadCurrentDID() else { return }
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
        guard let profile,
              let followURI = profile.viewer?.following,
              let rkey = followURI.rkey else { return }
        guard let viewerDID = try? await accountStore.loadCurrentDID() else { return }
        let original = self.profile
        self.profile = profile
            .adjustingFollowersCount(by: -1)
            .withViewer { v in ProfileViewerState(
                muted: v?.muted, mutedByList: v?.mutedByList,
                blockedBy: v?.blockedBy, blocking: v?.blocking,
                following: nil, followedBy: v?.followedBy
            )}
        do {
            let req = DeleteRecordRequest(
                repo: viewerDID.rawValue, collection: "app.bsky.graph.follow", rkey: rkey
            )
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord", body: req
            )
        } catch {
            self.profile = original
        }
    }

    // MARK: - Block / Unblock

    public func block() async {
        guard let profile else { return }
        guard let viewerDID = try? await accountStore.loadCurrentDID() else { return }
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
        guard let profile,
              let blockURI = profile.viewer?.blocking,
              let rkey = blockURI.rkey else { return }
        guard let viewerDID = try? await accountStore.loadCurrentDID() else { return }
        let original = self.profile
        self.profile = profile.withViewer { v in ProfileViewerState(
            muted: v?.muted, mutedByList: v?.mutedByList,
            blockedBy: v?.blockedBy, blocking: nil,
            following: v?.following, followedBy: v?.followedBy
        )}
        do {
            let req = DeleteRecordRequest(
                repo: viewerDID.rawValue, collection: "app.bsky.graph.block", rkey: rkey
            )
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord", body: req
            )
        } catch {
            self.profile = original
        }
    }

    // MARK: - Mute / Unmute

    public func mute() async {
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

    // MARK: - Edit profile

    public func updateProfile(displayName: String?, description: String?) async throws {
        guard let viewerDID = try? await accountStore.loadCurrentDID() else { return }
        let req = PutRecordRequest(
            repo: viewerDID.rawValue,
            collection: "app.bsky.actor.profile",
            rkey: "self",
            record: ProfileRecord(displayName: displayName, description: description)
        )
        let _: EmptyResponse = try await network.post(
            lexicon: "com.atproto.repo.putRecord", body: req
        )
        await loadProfile()
    }
}

// MARK: - ProfileDetailed mutation helpers

private extension ProfileDetailed {
    func withViewer(_ transform: (ProfileViewerState?) -> ProfileViewerState) -> ProfileDetailed {
        ProfileDetailed(
            did: did, handle: handle, displayName: displayName,
            description: description, avatar: avatar, banner: banner,
            followersCount: followersCount, followsCount: followsCount,
            postsCount: postsCount, labels: labels,
            createdAt: createdAt, indexedAt: indexedAt,
            viewer: transform(viewer)
        )
    }

    func adjustingFollowersCount(by delta: Int) -> ProfileDetailed {
        ProfileDetailed(
            did: did, handle: handle, displayName: displayName,
            description: description, avatar: avatar, banner: banner,
            followersCount: max(0, followersCount + delta), followsCount: followsCount,
            postsCount: postsCount, labels: labels,
            createdAt: createdAt, indexedAt: indexedAt, viewer: viewer
        )
    }
}
