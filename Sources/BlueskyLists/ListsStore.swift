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
    func createStarterPack(name: String, description: String?, listURI: ATURI) async
    /// Creates a starter pack end-to-end: a backing reference list of curated
    /// profiles plus the starter-pack record (with optional feeds). Mirrors
    /// RN's `useCreateStarterPackMutation` flow which first creates the list,
    /// fans out `applyWrites` to add list-item members, then creates the
    /// starter-pack record. Returns the new starter-pack record's AT-URI on
    /// success (RN navigates straight to the created pack), `nil` on failure.
    func createStarterPackWithProfiles(
        name: String,
        description: String?,
        profileDIDs: [DID],
        feedURIs: [ATURI]
    ) async -> ATURI?
    func loadStarterPack(uri: ATURI) async
    /// Deletes a starter pack the viewer owns (#0206). Mirrors RN's
    /// `useDeleteStarterPackMutation` (starter-pack record + backing list);
    /// additionally removes the backing list's `listitem` rows — RN orphans
    /// those on the PDS (see the #0204 gotcha). Returns `true` on success.
    func deleteStarterPack(pack: StarterPackView) async -> Bool
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

    /// Optimistically-inserted lists created in this session whose server
    /// copies have not yet appeared in a `getLists` response. The AppView
    /// indexes `createRecord` writes asynchronously, so the immediate
    /// post-create re-fetch routinely returns a stale set (#0203).
    /// Reconciliation keeps these entries alive across stale re-fetches and
    /// drops the local copy once the indexed server copy shows up
    /// (de-duped by URI). Newest first, matching `getLists` ordering.
    private var pendingCreated: [ListView] = []

    /// URIs of lists deleted in this session. A stale `getLists` response
    /// can still contain a record after the PDS delete succeeded;
    /// reconciliation filters these out so the deleted row doesn't
    /// resurrect until the AppView catches up.
    private var deletedURIs: Set<ATURI> = []

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
            lists = reconcile(resp.lists)
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
            // De-dupe against what's already shown (an optimistic insert may
            // surface on a later page) and drop tombstoned lists.
            let existing = Set(lists.map(\.uri))
            let page = resp.lists.filter {
                !deletedURIs.contains($0.uri) && !existing.contains($0.uri)
            }
            let pageURIs = Set(resp.lists.map(\.uri))
            pendingCreated.removeAll { pageURIs.contains($0.uri) }
            lists.append(contentsOf: page)
            self.cursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Merges a fresh first-page `getLists` response with the session's
    /// optimistic state: tombstoned (locally deleted) lists are filtered
    /// out, and optimistic inserts the AppView hasn't indexed yet are kept
    /// at the top (`getLists` returns newest-first). Once the server copy
    /// of an optimistic insert arrives it wins and local tracking stops.
    private func reconcile(_ serverLists: [ListView]) -> [ListView] {
        let kept = serverLists.filter { !deletedURIs.contains($0.uri) }
        let serverURIs = Set(kept.map(\.uri))
        pendingCreated.removeAll { serverURIs.contains($0.uri) }
        return pendingCreated + kept
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
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord", body: req
            )
            // Optimistic insert (#0203). The AppView indexes the new record
            // asynchronously, so an immediate `getLists` re-fetch usually
            // returns the stale pre-create set and the new list would stay
            // invisible. RN sidesteps the race by polling `getList` until
            // the AppView has the record before invalidating its lists
            // query; we instead surface a locally-built ListView right away
            // and reconcile (de-dupe by URI) when the indexed copy arrives.
            let optimistic = ListView(
                uri: resp.uri,
                cid: resp.cid,
                creator: await localCreatorProfile(did: viewerDID),
                name: name,
                purpose: purpose,
                description: description,
                avatar: nil,
                labels: [],
                indexedAt: record.createdAt,
                listItemCount: 0,
                viewer: nil
            )
            pendingCreated.insert(optimistic, at: 0)
            lists.insert(optimistic, at: 0)
            // Still re-fetch: if indexing already caught up the server copy
            // replaces the optimistic one; if not, reconciliation keeps it.
            await loadLists(actorDID: viewerDID.rawValue)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Builds a `ProfileView` for the signed-in account from the locally
    /// stored session (no network) so an optimistic `ListView` can carry a
    /// creator without waiting on the AppView. A keychain read failure must
    /// not abort the optimistic insert — the record already exists on the
    /// PDS — so this falls back to a DID-only profile and logs.
    private func localCreatorProfile(did: DID) async -> ProfileView {
        var account: Account?
        do {
            account = try await accountStore.load(did: did)?.account
        } catch {
            logger.warning("createList: could not load stored account for optimistic creator: \(error.localizedDescription, privacy: .public)")
        }
        return ProfileView(
            did: did,
            handle: account?.handle ?? Handle(rawValue: did.rawValue),
            displayName: account?.displayName,
            description: nil,
            avatar: account?.avatarURL,
            labels: [],
            indexedAt: nil,
            viewer: nil
        )
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
            // Tombstone so a stale `getLists` response (AppView not yet
            // caught up with the delete) can't resurrect the row (#0203).
            deletedURIs.insert(uri)
            pendingCreated.removeAll { $0.uri == uri }
        } catch {
            // Restore the list so the UI doesn't lie about its absence.
            if let removed { lists.insert(removed, at: 0) }
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

    /// Wizard create path. Mirrors RN's `useCreateStarterPackMutation` /
    /// `createStarterPackList` two-step:
    ///
    /// 1. Create a `app.bsky.graph.list` record (purpose `referencelist`).
    /// 2. Fan out `com.atproto.repo.applyWrites` with the curated members.
    /// 3. Create the `app.bsky.graph.starterpack` record pointing at the list
    ///    URI plus optional feeds.
    ///
    /// The list and members must exist before the starter pack record can
    /// reference them, so we cannot land all writes in a single `applyWrites`
    /// call (the listitem rows need the new list's URI). This matches RN.
    public func createStarterPackWithProfiles(
        name: String,
        description: String?,
        profileDIDs: [DID],
        feedURIs: [ATURI]
    ) async -> ATURI? {
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("createStarterPackWithProfiles: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return nil
        }
        guard let viewerDID else {
            self.error = "Not signed in"
            return nil
        }

        // 1) Create the backing list (referencelist purpose, matching RN).
        let listRecord = ListRecord(
            name: name,
            description: description,
            purpose: "app.bsky.graph.defs#referencelist"
        )
        let listURI: ATURI
        do {
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: CreateRecordRequest(
                    repo: viewerDID.rawValue,
                    collection: "app.bsky.graph.list",
                    record: listRecord
                )
            )
            listURI = resp.uri
        } catch {
            logger.error("createStarterPackWithProfiles: list create failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return nil
        }

        // 2) Apply writes for each member. Chunk at 50 to stay under server
        //    limits (matches RN's `chunk(profiles, 50)`).
        if !profileDIDs.isEmpty {
            let chunks = stride(from: 0, to: profileDIDs.count, by: 50).map {
                Array(profileDIDs[$0..<min($0 + 50, profileDIDs.count)])
            }
            for batch in chunks {
                let writes: [WriteOp] = batch.map { did in
                    .create(WriteCreate(
                        collection: "app.bsky.graph.listitem",
                        value: ListItemRecord(list: listURI, subject: did)
                    ))
                }
                do {
                    let _: ApplyWritesResponse = try await network.post(
                        lexicon: "com.atproto.repo.applyWrites",
                        body: ApplyWritesRequest(repo: viewerDID, writes: writes)
                    )
                } catch {
                    logger.error("createStarterPackWithProfiles: applyWrites failed: \(error.localizedDescription, privacy: .public)")
                    self.error = error.localizedDescription
                    return nil
                }
            }
        }

        // 3) Create the starter-pack record referencing the new list.
        let feedItems = feedURIs.isEmpty ? nil : feedURIs.map { StarterPackFeedItem(uri: $0) }
        let packRecord = StarterPackRecord(
            name: name,
            description: description,
            list: listURI,
            feeds: feedItems
        )
        do {
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: CreateRecordRequest(
                    repo: viewerDID.rawValue,
                    collection: "app.bsky.graph.starterpack",
                    record: packRecord
                )
            )
            return resp.uri
        } catch {
            logger.error("createStarterPackWithProfiles: starterpack create failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Owner delete (#0206). RN's `useDeleteStarterPackMutation` deletes the
    /// starter-pack record plus its backing reference list; this port also
    /// sweeps the list's `app.bsky.graph.listitem` rows first — RN leaves
    /// them orphaned on the PDS (the #0204 gotcha). The listitem rkeys come
    /// from `com.atproto.repo.listRecords` (PDS truth, no AppView indexing
    /// lag), filtered to the backing list's URI.
    public func deleteStarterPack(pack: StarterPackView) async -> Bool {
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("deleteStarterPack: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return false
        }
        guard let viewerDID, viewerDID == pack.creator.did else {
            self.error = "Only the creator can delete a starter pack."
            return false
        }
        guard let packRkey = pack.uri.rkey else {
            self.error = "Malformed starter pack URI."
            return false
        }

        // 1) Sweep the backing list's member rows, then the list itself.
        if let listURI = pack.list?.uri {
            var itemRkeys: [String] = []
            var cursor: String?
            repeat {
                var params = [
                    "repo": viewerDID.rawValue,
                    "collection": "app.bsky.graph.listitem",
                    "limit": "100",
                ]
                if let cursor { params["cursor"] = cursor }
                do {
                    let page: ListRecordsResponse<ListItemRecordValue> = try await network.get(
                        lexicon: "com.atproto.repo.listRecords", params: params
                    )
                    itemRkeys.append(contentsOf: page.records
                        .filter { $0.value.list == listURI.rawValue }
                        .compactMap { $0.uri.rkey })
                    cursor = page.records.isEmpty ? nil : page.cursor
                } catch {
                    logger.error("deleteStarterPack: listRecords failed: \(error.localizedDescription, privacy: .public)")
                    self.error = error.localizedDescription
                    return false
                }
            } while cursor != nil

            // Chunk at 50 like the create fan-out (applyWrites caps at 200).
            let chunks = stride(from: 0, to: itemRkeys.count, by: 50).map {
                Array(itemRkeys[$0..<min($0 + 50, itemRkeys.count)])
            }
            for batch in chunks {
                let writes: [WriteOp] = batch.map {
                    .delete(WriteDelete(collection: "app.bsky.graph.listitem", rkey: $0))
                }
                do {
                    let _: ApplyWritesResponse = try await network.post(
                        lexicon: "com.atproto.repo.applyWrites",
                        body: ApplyWritesRequest(repo: viewerDID, writes: writes)
                    )
                } catch {
                    logger.error("deleteStarterPack: listitem sweep failed: \(error.localizedDescription, privacy: .public)")
                    self.error = error.localizedDescription
                    return false
                }
            }

            if let listRkey = listURI.rkey {
                do {
                    let _: EmptyResponse = try await network.post(
                        lexicon: "com.atproto.repo.deleteRecord",
                        body: DeleteRecordRequest(repo: viewerDID.rawValue, collection: "app.bsky.graph.list", rkey: listRkey)
                    )
                } catch {
                    logger.error("deleteStarterPack: list delete failed: \(error.localizedDescription, privacy: .public)")
                    self.error = error.localizedDescription
                    return false
                }
            }
        }

        // 2) Delete the starter-pack record itself.
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: DeleteRecordRequest(repo: viewerDID.rawValue, collection: "app.bsky.graph.starterpack", rkey: packRkey)
            )
            return true
        } catch {
            logger.error("deleteStarterPack: starterpack delete failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return false
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

    /// Typeahead results backing the "Add people" sheet.
    var searchResults: [ProfileBasic] { get }
    var isSearching: Bool { get }

    func load(listURI: ATURI) async
    func loadMore() async
    func loadFeed() async
    func loadMoreFeed() async

    /// Debounced `app.bsky.actor.searchActorsTypeahead` query for the
    /// "Add people" sheet. Mirrors RN's `SearchablePeopleList` inside
    /// `ListAddRemoveUsersDialog`. Empty query clears `searchResults`.
    func searchMembers(query: String)

    /// Adds `profile` to the loaded list by creating an
    /// `app.bsky.graph.listitem` record in the viewer's repo (RN's
    /// `useListMembershipAddMutation`). Optimistically appends the new
    /// `ListItemView` to `members` using the `createRecord` response URI —
    /// the AppView indexes the write asynchronously, so re-fetches
    /// reconcile against this local state the same way #0203 handles list
    /// creation. Owner-only: no-ops with an error when the viewer does not
    /// own the list. Returns `true` on success.
    func addMember(_ profile: ProfileBasic) async -> Bool

    /// Removes the membership record `itemURI` (an
    /// `app.bsky.graph.listitem` URI from `getList`) via `deleteRecord`
    /// (RN's `useListMembershipRemoveMutation`). Optimistically removes the
    /// row, reverting on failure; on success the URI is tombstoned so a
    /// stale `getList` page cannot resurrect it. Returns `true` on success.
    func removeMember(itemURI: ATURI) async -> Bool

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

    public private(set) var searchResults: [ProfileBasic] = []
    public private(set) var isSearching = false

    private var listURI: ATURI?
    private var membersCursor: Cursor?
    private var feedCursor: Cursor?

    /// Optimistically-added members whose `listitem` records the AppView has
    /// not indexed into `getList` responses yet (same race as #0203's list
    /// creation). Reconciliation keeps them alive across stale re-fetches
    /// and drops the local copy once the indexed server copy arrives
    /// (de-duped by record URI / subject DID — server copy wins).
    private var pendingAddedItems: [ListItemView] = []

    /// `listitem` URIs removed in this session. A stale `getList` response
    /// can still contain the record after the PDS delete succeeded;
    /// reconciliation filters these so removed members don't resurrect.
    private var removedItemURIs: Set<ATURI> = []

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchID: UInt64 = 0

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
            members = reconcileMembers(resp.items)
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
            // De-dupe against rows already shown (an optimistic add may
            // surface on a later page) and drop tombstoned removals.
            let existing = Set(members.map(\.uri))
            let page = resp.items.filter {
                !removedItemURIs.contains($0.uri) && !existing.contains($0.uri)
            }
            let pageURIs = Set(resp.items.map(\.uri))
            pendingAddedItems.removeAll { pageURIs.contains($0.uri) }
            members.append(contentsOf: page)
            membersCursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Merges a fresh first-page `getList` response with the session's
    /// optimistic member state (#0203 pattern): tombstoned (locally removed)
    /// items are filtered out, and optimistic adds the AppView hasn't indexed
    /// yet are kept at the bottom (`getList` returns items in creation
    /// order). Once the indexed server copy of an optimistic add arrives —
    /// matched by record URI or subject DID — it wins and local tracking
    /// stops.
    private func reconcileMembers(_ serverItems: [ListItemView]) -> [ListItemView] {
        let kept = serverItems.filter { !removedItemURIs.contains($0.uri) }
        let serverURIs = Set(kept.map(\.uri))
        let serverDIDs = Set(kept.map(\.subject.did))
        pendingAddedItems.removeAll {
            serverURIs.contains($0.uri) || serverDIDs.contains($0.subject.did)
        }
        return kept + pendingAddedItems
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

    // MARK: - Member management (#0204)

    /// Debounced actor typeahead (200 ms) for the "Add people" sheet —
    /// `app.bsky.actor.searchActorsTypeahead`, the same lexicon RN's
    /// `SearchablePeopleList` queries. Empty query clears results.
    public func searchMembers(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        searchID &+= 1
        let id = searchID
        let net = network
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self else { return }
            self.isSearching = true
            defer {
                if id == self.searchID { self.isSearching = false }
            }
            do {
                let resp: SearchActorsTypeaheadResponse = try await net.get(
                    lexicon: "app.bsky.actor.searchActorsTypeahead",
                    params: ["q": trimmed, "limit": "12"]
                )
                guard id == self.searchID else { return }
                self.searchResults = resp.actors
            } catch {
                logger.error("searchMembers failed: \(error.localizedDescription, privacy: .public)")
                guard id == self.searchID else { return }
                self.searchResults = []
            }
        }
    }

    /// Resolves the signed-in viewer DID for member mutations, surfacing
    /// failures on `error`. `nil` means "cannot mutate" (logged out, no
    /// account store, or keychain failure).
    private func mutationViewerDID() async -> DID? {
        guard let accountStore else {
            self.error = "Not signed in"
            return nil
        }
        do {
            guard let did = try await accountStore.loadCurrentDID() else {
                self.error = "Not signed in"
                return nil
            }
            return did
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    public func addMember(_ profile: ProfileBasic) async -> Bool {
        guard let listURI else { return false }
        guard let viewerDID = await mutationViewerDID() else { return false }
        // `listitem` records must live in the same repo as the list they
        // reference — the AppView ignores them otherwise — so only the list
        // owner can add members. RN gates the dialog on ownership; the store
        // enforces it too so a non-owned list exposes no mutation.
        guard listURI.repo == viewerDID.rawValue else {
            self.error = "Only the list owner can add members"
            return false
        }
        // Already a member — nothing to write (RN's dialog shows Remove).
        guard !members.contains(where: { $0.subject.did == profile.did }) else {
            return true
        }
        do {
            let record = ListItemRecord(list: listURI, subject: profile.did)
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: CreateRecordRequest(
                    repo: viewerDID.rawValue,
                    collection: "app.bsky.graph.listitem",
                    record: record
                )
            )
            // Optimistic insert (#0203 pattern): the AppView indexes the new
            // record asynchronously, so an immediate `getList` re-fetch would
            // miss it. Surface a locally-built ListItemView right away and
            // reconcile (de-dupe by URI) when the indexed copy arrives.
            let item = ListItemView(
                uri: resp.uri,
                subject: ProfileView(
                    did: profile.did,
                    handle: profile.handle,
                    displayName: profile.displayName,
                    description: nil,
                    avatar: profile.avatar,
                    labels: profile.labels,
                    indexedAt: nil,
                    viewer: nil
                )
            )
            removedItemURIs.remove(resp.uri)
            pendingAddedItems.append(item)
            members.append(item)
            adjustItemCount(by: 1)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    public func removeMember(itemURI: ATURI) async -> Bool {
        guard let rkey = itemURI.rkey else { return false }
        guard let viewerDID = await mutationViewerDID() else { return false }
        // Membership records live in the owner's repo; refuse mutations on
        // records the viewer does not own.
        guard itemURI.repo == viewerDID.rawValue else {
            self.error = "Only the list owner can remove members"
            return false
        }
        guard let index = members.firstIndex(where: { $0.uri == itemURI }) else {
            return false
        }
        // Optimistic removal, restored on failure (project pattern —
        // mirrors ListsStore.deleteList).
        let removed = members.remove(at: index)
        adjustItemCount(by: -1)
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: DeleteRecordRequest(
                    repo: viewerDID.rawValue,
                    collection: "app.bsky.graph.listitem",
                    rkey: rkey
                )
            )
            // Tombstone so a stale `getList` page (AppView not yet caught up
            // with the delete) can't resurrect the row.
            removedItemURIs.insert(itemURI)
            pendingAddedItems.removeAll { $0.uri == itemURI }
            return true
        } catch {
            members.insert(removed, at: min(index, members.count))
            adjustItemCount(by: 1)
            self.error = error.localizedDescription
            return false
        }
    }

    /// Rebuilds `list` with `listItemCount` shifted by `delta` so the header
    /// member count tracks optimistic add/remove without a refetch (RN
    /// adjusts its cached `listItemCount` the same way).
    private func adjustItemCount(by delta: Int) {
        guard let current = list else { return }
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
            listItemCount: max(0, (current.listItemCount ?? 0) + delta),
            viewer: current.viewer
        )
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
