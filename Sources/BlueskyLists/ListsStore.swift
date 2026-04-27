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
        guard let viewerDID = try? await accountStore.loadCurrentDID() else { return }
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
        guard let rkey = uri.rkey,
              let viewerDID = try? await accountStore.loadCurrentDID() else { return }
        lists.removeAll { $0.uri == uri }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: DeleteRecordRequest(repo: viewerDID.rawValue, collection: "app.bsky.graph.list", rkey: rkey)
            )
        } catch {
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
        guard let viewerDID = try? await accountStore.loadCurrentDID() else { return }
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
        guard let viewerDID = try? await accountStore.loadCurrentDID(),
              let members = pack.listItemsSample else { return }
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

    public init(network: any NetworkClient) {
        self.network = network
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
}
