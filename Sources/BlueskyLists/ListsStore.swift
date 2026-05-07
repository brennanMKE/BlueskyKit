import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "ListsStore")

// MARK: - ListsStoring

public protocol ListsStoring: AnyObject, Observable, Sendable {
    var lists: [ListView] { get }
    var starterPack: StarterPackView? { get }
    var isLoading: Bool { get }
    var error: String? { get }

    func loadLists(actorDID: String) async
    func loadMore(actorDID: String) async
    func createList(name: String, description: String?, purpose: String) async
    func deleteList(uri: ATURI) async
    func addMember(listURI: ATURI, subjectDID: DID, repo: String) async
    func removeMember(itemURI: ATURI, repo: String) async
    func createStarterPack(name: String, description: String?, listURI: ATURI) async
    func loadStarterPack(uri: ATURI) async
    func followAll(pack: StarterPackView) async
    func clearError()
}

// MARK: - ListsStore

@Observable
public final class ListsStore: ListsStoring {

    public private(set) var lists: [ListView] = []
    public private(set) var starterPack: StarterPackView?
    public private(set) var isLoading = false
    public private(set) var error: String?

    private var cursor: Cursor?

    private let network: any NetworkClient
    private let accountStore: any AccountStore

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.network = network
        self.accountStore = accountStore
    }

    // MARK: - DID helper

    func currentDID() async throws -> String? {
        try await accountStore.loadCurrentDID()?.rawValue
    }

    // MARK: - Load lists

    public func loadLists(actorDID: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            let resp: GetListsResponse = try await network.get(
                lexicon: "app.bsky.graph.getLists",
                params: ["actor": actorDID, "limit": "50"]
            )
            lists = resp.lists
            cursor = resp.cursor
        } catch {
            logger.error("lists load error: \(error, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    public func loadMore(actorDID: String) async {
        guard let cursor else { return }
        do {
            let resp: GetListsResponse = try await network.get(
                lexicon: "app.bsky.graph.getLists",
                params: ["actor": actorDID, "limit": "50", "cursor": cursor]
            )
            lists.append(contentsOf: resp.lists)
            self.cursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Create list

    public func createList(name: String, description: String?, purpose: String = "app.bsky.graph.defs#curatelist") async {
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("createList: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return
        }
        guard let viewerDID else { return }
        do {
            let record = ListRecord(name: name, description: description, purpose: purpose)
            let req = CreateRecordRequest(
                repo: viewerDID.rawValue,
                collection: "app.bsky.graph.list",
                record: record
            )
            let _: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord", body: req
            )
            await loadLists(actorDID: viewerDID.rawValue)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Delete list

    public func deleteList(uri: ATURI) async {
        guard let rkey = uri.rkey else { return }
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("deleteList: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return
        }
        guard let viewerDID else { return }
        let removed = lists.first { $0.uri == uri }
        lists.removeAll { $0.uri == uri }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: DeleteRecordRequest(repo: viewerDID.rawValue, collection: "app.bsky.graph.list", rkey: rkey)
            )
        } catch {
            // Restore the list so the UI doesn't lie about its absence.
            if let removed { lists.insert(removed, at: 0) }
            self.error = error.localizedDescription
        }
    }

    // MARK: - Members

    public func addMember(listURI: ATURI, subjectDID: DID, repo: String) async {
        do {
            let record = ListItemRecord(list: listURI, subject: subjectDID)
            let _: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: CreateRecordRequest(repo: repo, collection: "app.bsky.graph.listitem", record: record)
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func removeMember(itemURI: ATURI, repo: String) async {
        guard let rkey = itemURI.rkey else { return }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: DeleteRecordRequest(repo: repo, collection: "app.bsky.graph.listitem", rkey: rkey)
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Starter packs

    public func createStarterPack(name: String, description: String?, listURI: ATURI) async {
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("createStarterPack: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return
        }
        guard let viewerDID else { return }
        let record = StarterPackRecord(name: name, description: description, list: listURI)
        let req = CreateRecordRequest(
            repo: viewerDID.rawValue,
            collection: "app.bsky.graph.starterpack",
            record: record
        )
        do {
            let _: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord", body: req
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func loadStarterPack(uri: ATURI) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: GetStarterPackResponse = try await network.get(
                lexicon: "app.bsky.graph.getStarterPack",
                params: ["starterPack": uri.rawValue]
            )
            starterPack = resp.starterPack
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func followAll(pack: StarterPackView) async {
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("followAll: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return
        }
        guard let viewerDID, let members = pack.listItemsSample else { return }
        for item in members {
            do {
                let _: CreateRecordResponse = try await network.post(
                    lexicon: "com.atproto.repo.createRecord",
                    body: CreateRecordRequest(
                        repo: viewerDID.rawValue,
                        collection: "app.bsky.graph.follow",
                        record: FollowRecord(subject: item.subject.did)
                    )
                )
            } catch {
                self.error = error.localizedDescription
                return
            }
        }
    }

    public func clearError() {
        error = nil
    }
}

// MARK: - ListDetailStoring

public protocol ListDetailStoring: AnyObject, Observable, Sendable {
    var list: ListView? { get }
    var members: [ListItemView] { get }
    var feed: [FeedViewPost] { get }
    var isLoading: Bool { get }
    var error: String? { get }

    func load(listURI: ATURI) async
    func loadMore() async
    func loadFeed() async
    func loadMoreFeed() async

    /// Subscribe to a moderation list as a mute. Mirrors RN's
    /// `useListMuteMutation({mute: true})` path on
    /// `app.bsky.graph.muteActorList`.
    func muteList() async
    /// Unsubscribe a moderation-list mute.
    func unmuteList() async

    /// Edit the loaded list's name/description. Mirrors RN's
    /// `useListMetadataMutation`: fetch the existing record, mutate the
    /// fields, then `putRecord` it back so the avatar blob is preserved.
    /// Optimistically updates the local `list` value on success.
    /// Returns `true` on success.
    func editList(name: String, description: String?) async -> Bool

    /// Delete the loaded list record. Returns `true` on success so the
    /// caller can pop back to the lists hub.
    func deleteList() async -> Bool
}

// MARK: - ListDetailStore

@Observable
public final class ListDetailStore: ListDetailStoring {

    public private(set) var list: ListView?
    public private(set) var members: [ListItemView] = []
    public private(set) var feed: [FeedViewPost] = []
    public private(set) var isLoading = false
    public private(set) var error: String?

    private var listURI: ATURI?
    private var membersCursor: Cursor?
    private var feedCursor: Cursor?

    private let network: any NetworkClient
    /// Optional — required for owner-only mutations (edit / delete). The
    /// existing read-only call site (`ListDetailScreen` previews) passes
    /// `nil`; mutations short-circuit when the store cannot resolve a
    /// viewer DID.
    private let accountStore: (any AccountStore)?

    public init(network: any NetworkClient, accountStore: (any AccountStore)? = nil) {
        self.network = network
        self.accountStore = accountStore
    }

    public func load(listURI: ATURI) async {
        self.listURI = listURI
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            let resp: GetListResponse = try await network.get(
                lexicon: "app.bsky.graph.getList",
                params: ["list": listURI.rawValue, "limit": "50"]
            )
            list = resp.list
            members = resp.items
            membersCursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func loadMore() async {
        guard let listURI, let cursor = membersCursor else { return }
        do {
            let resp: GetListResponse = try await network.get(
                lexicon: "app.bsky.graph.getList",
                params: ["list": listURI.rawValue, "limit": "50", "cursor": cursor]
            )
            members.append(contentsOf: resp.items)
            membersCursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func loadFeed() async {
        guard let listURI else { return }
        do {
            let resp: GetListFeedResponse = try await network.get(
                lexicon: "app.bsky.feed.getListFeed",
                params: ["list": listURI.rawValue, "limit": "50"]
            )
            feed = resp.feed
            feedCursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func loadMoreFeed() async {
        guard let listURI, let cursor = feedCursor else { return }
        do {
            let resp: GetListFeedResponse = try await network.get(
                lexicon: "app.bsky.feed.getListFeed",
                params: ["list": listURI.rawValue, "limit": "50", "cursor": cursor]
            )
            feed.append(contentsOf: resp.feed)
            feedCursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Mute / unmute (moderation list subscribe)

    public func muteList() async {
        guard let listURI else { return }
        let previous = list
        // Optimistic update so the header flips immediately.
        if let current = list {
            list = ListView(
                uri: current.uri,
                cid: current.cid,
                creator: current.creator,
                name: current.name,
                purpose: current.purpose,
                description: current.description,
                avatar: current.avatar,
                labels: current.labels,
                indexedAt: current.indexedAt,
                listItemCount: current.listItemCount,
                viewer: ListViewerState(muted: true, blocked: current.viewer?.blocked)
            )
        }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.graph.muteActorList",
                body: ListMuteRequest(list: listURI)
            )
        } catch {
            list = previous
            self.error = error.localizedDescription
        }
    }

    public func unmuteList() async {
        guard let listURI else { return }
        let previous = list
        if let current = list {
            list = ListView(
                uri: current.uri,
                cid: current.cid,
                creator: current.creator,
                name: current.name,
                purpose: current.purpose,
                description: current.description,
                avatar: current.avatar,
                labels: current.labels,
                indexedAt: current.indexedAt,
                listItemCount: current.listItemCount,
                viewer: ListViewerState(muted: false, blocked: current.viewer?.blocked)
            )
        }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.graph.unmuteActorList",
                body: ListMuteRequest(list: listURI)
            )
        } catch {
            list = previous
            self.error = error.localizedDescription
        }
    }

    // MARK: - Edit / delete

    /// Read-modify-write the list record. Matches RN's
    /// `useListMetadataMutation`: fetches the canonical record so the avatar
    /// blob and any unknown fields survive the round-trip, then `putRecord`s
    /// the mutated record back. Updates `list` optimistically on success.
    public func editList(name: String, description: String?) async -> Bool {
        guard let listURI, let rkey = listURI.rkey else { return false }
        guard let accountStore else {
            self.error = "Not signed in"
            return false
        }
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            self.error = error.localizedDescription
            return false
        }
        guard let viewerDID else {
            self.error = "Not signed in"
            return false
        }
        do {
            // Fetch the existing record so we preserve avatar + createdAt +
            // anything else stored on the list.
            let existing: GetRecordResponse<ListRecord> = try await network.get(
                lexicon: "com.atproto.repo.getRecord",
                params: [
                    "repo": viewerDID.rawValue,
                    "collection": "app.bsky.graph.list",
                    "rkey": rkey,
                ]
            )
            var record = existing.value
            record.name = name
            record.description = description
            let req = PutRecordRequest(
                repo: viewerDID.rawValue,
                collection: "app.bsky.graph.list",
                rkey: rkey,
                record: record
            )
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.putRecord",
                body: req
            )
            // Optimistically reflect the new metadata in the loaded view so
            // the header / About tab update without a refetch.
            if let current = list {
                self.list = ListView(
                    uri: current.uri,
                    cid: current.cid,
                    creator: current.creator,
                    name: name,
                    purpose: current.purpose,
                    description: description,
                    avatar: current.avatar,
                    labels: current.labels,
                    indexedAt: current.indexedAt,
                    listItemCount: current.listItemCount,
                    viewer: current.viewer
                )
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Delete the loaded list record. Mirrors RN's `useListDeleteMutation`'s
    /// minimal path — RN also bulk-deletes member `listitem` records before
    /// removing the list, but the appview cleans those up server-side; the
    /// SwiftUI client removes only the list record and pops to the hub.
    public func deleteList() async -> Bool {
        guard let listURI, let rkey = listURI.rkey else { return false }
        guard let accountStore else {
            self.error = "Not signed in"
            return false
        }
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            self.error = error.localizedDescription
            return false
        }
        guard let viewerDID else {
            self.error = "Not signed in"
            return false
        }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: DeleteRecordRequest(
                    repo: viewerDID.rawValue,
                    collection: "app.bsky.graph.list",
                    rkey: rkey
                )
            )
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
