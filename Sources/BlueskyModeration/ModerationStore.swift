import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "ModerationStore")

// MARK: - ModerationStoring

public protocol ModerationStoring: AnyObject, Observable, Sendable {
    var mutes: [ProfileView] { get }
    var blocks: [ProfileView] { get }
    var modLists: [ListView] { get }
    /// Mod lists the viewer subscribed to via `muteActorList` or a
    /// `listblock` record. Populated by `loadModLists` from `getListMutes`
    /// and `getListBlocks` and filtered against the viewer's own DID so we
    /// don't double-count owned lists the viewer also muted.
    var subscribedModLists: [ListView] { get }
    var adultContentEnabled: Bool { get set }
    var contentLabels: [ContentLabelPref] { get }
    var subscribedLabelerDIDs: [DID] { get }
    var subscribedLabelers: [LabelerView] { get }
    var unavailableLabelerDIDs: [DID] { get }
    var isLoadingLabelers: Bool { get }
    var hasMoreMutes: Bool { get }
    var hasMoreBlocks: Bool { get }
    var hasMoreModLists: Bool { get }
    var hasMoreSubscribedMutes: Bool { get }
    var hasMoreSubscribedBlocks: Bool { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func loadMutes() async
    func loadMoreMutes() async
    func loadBlocks() async
    func loadMoreBlocks() async
    func loadModLists() async
    func loadMoreModLists() async
    func loadMoreSubscribedModLists() async
    func loadPreferences() async
    func loadSubscribedLabelers() async
    func removeUnavailableLabelers() async
    func unmute(did: DID) async
    func unblock(profile: ProfileView) async
    func muteList(_ listURI: ATURI) async
    func unmuteList(_ listURI: ATURI) async
    func unblockList(_ list: ListView) async
    func setAdultContent(enabled: Bool) async
    func setLabelVisibility(label: String, labelerDid: DID?, visibility: String) async
    func report(subject: some Encodable & Sendable, reasonType: String, reason: String?, labelerDID: DID?) async throws
}

// MARK: - ModerationStore

@Observable
public final class ModerationStore: ModerationStoring {

    public private(set) var mutes: [ProfileView] = []
    public private(set) var blocks: [ProfileView] = []
    public private(set) var modLists: [ListView] = []
    public private(set) var subscribedModLists: [ListView] = []
    public var adultContentEnabled = false
    public private(set) var contentLabels: [ContentLabelPref] = []
    public private(set) var subscribedLabelerDIDs: [DID] = []
    public private(set) var subscribedLabelers: [LabelerView] = []
    public private(set) var unavailableLabelerDIDs: [DID] = []
    public private(set) var isLoadingLabelers = false
    public private(set) var hasMoreMutes = true
    public private(set) var hasMoreBlocks = true
    public private(set) var hasMoreModLists = true
    public private(set) var hasMoreSubscribedMutes = true
    public private(set) var hasMoreSubscribedBlocks = true
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private var mutesCursor: Cursor?
    private var blocksCursor: Cursor?
    private var modListsCursor: Cursor?
    private var subscribedMutesCursor: Cursor?
    private var subscribedBlocksCursor: Cursor?

    private let network: any NetworkClient
    private let accountStore: any AccountStore

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.network = network
        self.accountStore = accountStore
    }

    // MARK: - Mutes

    public func loadMutes() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let resp: GetMutesResponse = try await network.get(
                lexicon: "app.bsky.graph.getMutes",
                params: ["limit": "50"]
            )
            mutes = resp.mutes
            mutesCursor = resp.cursor
            hasMoreMutes = resp.cursor != nil
        } catch {
            logger.error("load mutes error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func loadMoreMutes() async {
        guard hasMoreMutes, let cursor = mutesCursor else { return }
        do {
            let resp: GetMutesResponse = try await network.get(
                lexicon: "app.bsky.graph.getMutes",
                params: ["limit": "50", "cursor": cursor]
            )
            mutes.append(contentsOf: resp.mutes)
            mutesCursor = resp.cursor
            hasMoreMutes = resp.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Blocks

    public func loadBlocks() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let resp: GetBlocksResponse = try await network.get(
                lexicon: "app.bsky.graph.getBlocks",
                params: ["limit": "50"]
            )
            blocks = resp.blocks
            blocksCursor = resp.cursor
            hasMoreBlocks = resp.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadMoreBlocks() async {
        guard hasMoreBlocks, let cursor = blocksCursor else { return }
        do {
            let resp: GetBlocksResponse = try await network.get(
                lexicon: "app.bsky.graph.getBlocks",
                params: ["limit": "50", "cursor": cursor]
            )
            blocks.append(contentsOf: resp.blocks)
            blocksCursor = resp.cursor
            hasMoreBlocks = resp.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Moderation lists

    /// Loads both the viewer's authored mod lists (from `getLists`) and the
    /// mod lists they've subscribed to (from `getListMutes` / `getListBlocks`).
    /// Mirrors RN's `useMyListsQuery(filter: 'mod')` — the RN query accumulates
    /// all three endpoints and de-dupes by URI. The split is held in two
    /// arrays here so the screen can render two sections with different
    /// per-row affordances (edit/delete vs unsubscribe).
    public func loadModLists() async {
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("loadModLists: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }
        guard let viewerDID else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            // Owned mod lists (`getLists` filtered by purpose).
            let owned: GetListsResponse = try await network.get(
                lexicon: "app.bsky.graph.getLists",
                params: ["actor": viewerDID.rawValue, "limit": "50"]
            )
            modLists = owned.lists.filter { $0.purpose == "app.bsky.graph.defs#modlist" }
            modListsCursor = owned.cursor
            hasMoreModLists = owned.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }

        // Subscribed mod lists — RN accumulates `getListMutes` and
        // `getListBlocks`, filters to `modlist` purpose, and drops anything
        // the viewer also owns (already in `modLists`).
        var subscribed: [ListView] = []
        var seen: Set<String> = Set(modLists.map { $0.uri.rawValue })

        do {
            let muted: GetListMutesResponse = try await network.get(
                lexicon: "app.bsky.graph.getListMutes",
                params: ["limit": "50"]
            )
            for list in muted.lists {
                guard list.purpose == "app.bsky.graph.defs#modlist" else { continue }
                guard list.creator.did != viewerDID else { continue }
                guard !seen.contains(list.uri.rawValue) else { continue }
                subscribed.append(list)
                seen.insert(list.uri.rawValue)
            }
            subscribedMutesCursor = muted.cursor
            hasMoreSubscribedMutes = muted.cursor != nil
        } catch {
            // A failed subscribed-mutes fetch shouldn't blow away the owned
            // section — surface the error and continue with blocks.
            logger.error("loadModLists: getListMutes failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }

        do {
            let blocked: GetListBlocksResponse = try await network.get(
                lexicon: "app.bsky.graph.getListBlocks",
                params: ["limit": "50"]
            )
            for list in blocked.lists {
                guard list.purpose == "app.bsky.graph.defs#modlist" else { continue }
                guard list.creator.did != viewerDID else { continue }
                guard !seen.contains(list.uri.rawValue) else { continue }
                subscribed.append(list)
                seen.insert(list.uri.rawValue)
            }
            subscribedBlocksCursor = blocked.cursor
            hasMoreSubscribedBlocks = blocked.cursor != nil
        } catch {
            logger.error("loadModLists: getListBlocks failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }

        subscribedModLists = subscribed
    }

    public func loadMoreModLists() async {
        guard hasMoreModLists, let cursor = modListsCursor else { return }
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("loadMoreModLists: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }
        guard let viewerDID else { return }
        do {
            let resp: GetListsResponse = try await network.get(
                lexicon: "app.bsky.graph.getLists",
                params: ["actor": viewerDID.rawValue, "limit": "50", "cursor": cursor]
            )
            modLists.append(contentsOf: resp.lists.filter { $0.purpose == "app.bsky.graph.defs#modlist" })
            modListsCursor = resp.cursor
            hasMoreModLists = resp.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Paginate the subscribed-mod-lists section. Mirrors RN's accumulator
    /// over `getListMutes` / `getListBlocks`: each endpoint is paged until
    /// its cursor runs out. We track separate cursors and chain mutes
    /// before blocks (matching RN's promise array order).
    public func loadMoreSubscribedModLists() async {
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("loadMoreSubscribedModLists: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }
        guard let viewerDID else { return }
        var seen: Set<String> = Set(modLists.map { $0.uri.rawValue })
        seen.formUnion(subscribedModLists.map { $0.uri.rawValue })

        if hasMoreSubscribedMutes, let cursor = subscribedMutesCursor {
            do {
                let muted: GetListMutesResponse = try await network.get(
                    lexicon: "app.bsky.graph.getListMutes",
                    params: ["limit": "50", "cursor": cursor]
                )
                for list in muted.lists {
                    guard list.purpose == "app.bsky.graph.defs#modlist" else { continue }
                    guard list.creator.did != viewerDID else { continue }
                    guard !seen.contains(list.uri.rawValue) else { continue }
                    subscribedModLists.append(list)
                    seen.insert(list.uri.rawValue)
                }
                subscribedMutesCursor = muted.cursor
                hasMoreSubscribedMutes = muted.cursor != nil
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        if hasMoreSubscribedBlocks, let cursor = subscribedBlocksCursor {
            do {
                let blocked: GetListBlocksResponse = try await network.get(
                    lexicon: "app.bsky.graph.getListBlocks",
                    params: ["limit": "50", "cursor": cursor]
                )
                for list in blocked.lists {
                    guard list.purpose == "app.bsky.graph.defs#modlist" else { continue }
                    guard list.creator.did != viewerDID else { continue }
                    guard !seen.contains(list.uri.rawValue) else { continue }
                    subscribedModLists.append(list)
                    seen.insert(list.uri.rawValue)
                }
                subscribedBlocksCursor = blocked.cursor
                hasMoreSubscribedBlocks = blocked.cursor != nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Preferences

    public func loadPreferences() async {
        do {
            let resp: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            adultContentEnabled = resp.adultContentEnabled
            contentLabels = resp.contentLabels
            subscribedLabelerDIDs = resp.subscribedLabelerDIDs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Subscribed labelers

    /// Resolves the viewer's labeler set into full `LabelerView`s
    /// (display name, avatar, like count) via `app.bsky.labeler.getServices`.
    /// Mirrors RN's `useMyLabelersQuery` flow: the resolved set is
    /// `AppLabelers.dids` (the always-on Bluesky Moderation Service, which is
    /// never stored in `labelersPref`) prepended to the user's `labelersPref`
    /// DIDs — `BskyAgent.appLabelers.concat(moderationPrefs.labelers)` — then
    /// the returned set is diffed against the requested `labelersPref` DIDs
    /// to flag unavailable services.
    public func loadSubscribedLabelers() async {
        isLoadingLabelers = true
        defer { isLoadingLabelers = false }
        do {
            let prefs: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            subscribedLabelerDIDs = prefs.subscribedLabelerDIDs

            // App labelers first, deduped — RN's `Array.from(new Set(...))`.
            var resolveDIDs = AppLabelers.dids
            resolveDIDs.append(contentsOf: subscribedLabelerDIDs.filter { !AppLabelers.contains($0) })

            // `dids` is an *array* query parameter: the appview only accepts
            // the repeated-key form (`dids=a&dids=b`) — a comma-joined single
            // value is rejected with `InvalidRequest: Invalid DID` (verified
            // live, #0202). `NetworkClient.get` takes a flat
            // `[String: String]`, so resolve one DID per request and
            // aggregate; the result set is identical to RN's batched call.
            // `detailed=true` returns `subjectTypes`, `subjectCollections`,
            // and `reasonTypes` on each labeler — needed by the Report
            // dialog to filter candidate labelers per subject + reason
            // (matches RN's `useMyLabelersQuery` which always asks for the
            // detailed view).
            var views: [LabelerView] = []
            for did in resolveDIDs {
                let resp: GetLabelerServicesResponse = try await network.get(
                    lexicon: "app.bsky.labeler.getServices",
                    params: ["dids": did.rawValue, "detailed": "true"]
                )
                views.append(contentsOf: resp.views)
            }
            subscribedLabelers = views
            let returned = Set(views.map { $0.creator.did })
            unavailableLabelerDIDs = subscribedLabelerDIDs.filter { !returned.contains($0) }
        } catch {
            logger.error("loadSubscribedLabelers error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Drops `unavailableLabelerDIDs` from the user's `labelersPref` and
    /// writes the trimmed list back via `putPreferences`. Mirrors RN's
    /// `useRemoveLabelersMutation` cleanup path.
    public func removeUnavailableLabelers() async {
        guard !unavailableLabelerDIDs.isEmpty else { return }
        let surviving = subscribedLabelerDIDs.filter { !unavailableLabelerDIDs.contains($0) }
        do {
            // Read-modify-write (#0201): merge into the full preferences array.
            try await PreferencesWriter.shared.update(network: network, .labelers(dids: surviving))
            subscribedLabelerDIDs = surviving
            unavailableLabelerDIDs = []
        } catch {
            logger.error("removeUnavailableLabelers error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Unmute

    public func unmute(did: DID) async {
        let removed = mutes.first { $0.did == did }
        mutes.removeAll { $0.did == did }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.graph.unmuteActor",
                body: MuteActorRequest(actor: did)
            )
        } catch {
            if let removed { mutes.insert(removed, at: 0) }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Unblock

    public func unblock(profile: ProfileView) async {
        guard let blockURI = profile.viewer?.blocking,
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
        let removed = profile
        blocks.removeAll { $0.did == profile.did }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: DeleteRecordRequest(repo: viewerDID.rawValue, collection: "app.bsky.graph.block", rkey: rkey)
            )
        } catch {
            blocks.insert(removed, at: 0)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mute / unmute list

    public func muteList(_ listURI: ATURI) async {
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.graph.muteActorList",
                body: ListMuteRequest(list: listURI)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func unmuteList(_ listURI: ATURI) async {
        // Optimistically drop the row so the Moderation Lists screen reflects
        // the unsubscribe immediately; restore it if the call fails (#0215).
        let previous = subscribedModLists
        subscribedModLists.removeAll { $0.uri == listURI }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.graph.unmuteActorList",
                body: ListMuteRequest(list: listURI)
            )
        } catch {
            subscribedModLists = previous
            errorMessage = error.localizedDescription
        }
    }

    /// Unblock a mod list by deleting the viewer's `app.bsky.graph.listblock`
    /// record. The block-record AT-URI rides on `list.viewer.blocked` (the
    /// appview surfaces it specifically so clients can drop the record
    /// without having to re-discover the rkey). Mirrors RN's
    /// `agent.unblockModList(uri)` which performs a `deleteRecord` against
    /// the matching listblock record.
    public func unblockList(_ list: ListView) async {
        guard let blockURI = list.viewer?.blocked, let rkey = blockURI.rkey else { return }
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("unblockList: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }
        guard let viewerDID else { return }
        // Optimistically drop the row; restore on failure (#0215).
        let previous = subscribedModLists
        subscribedModLists.removeAll { $0.uri == list.uri }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: DeleteRecordRequest(
                    repo: viewerDID.rawValue,
                    collection: "app.bsky.graph.listblock",
                    rkey: rkey
                )
            )
        } catch {
            subscribedModLists = previous
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Preferences mutations

    public func setAdultContent(enabled: Bool) async {
        adultContentEnabled = enabled
        await savePreferences()
    }

    public func setLabelVisibility(label: String, labelerDid: DID?, visibility: String) async {
        if let idx = contentLabels.firstIndex(where: { $0.label == label && $0.labelerDid == labelerDid }) {
            contentLabels[idx] = ContentLabelPref(label: label, visibility: visibility, labelerDid: labelerDid)
        } else {
            contentLabels.append(ContentLabelPref(label: label, visibility: visibility, labelerDid: labelerDid))
        }
        await savePreferences()
    }

    private func savePreferences() async {
        do {
            // Read-modify-write (#0201): replaces only the adultContentPref +
            // contentLabelPref entries inside the full preferences array.
            try await PreferencesWriter.shared.update(
                network: network,
                .adultContentAndLabels(enabled: adultContentEnabled, contentLabels: contentLabels)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Report

    public func report(
        subject: some Encodable & Sendable,
        reasonType: String,
        reason: String?,
        labelerDID: DID?
    ) async throws {
        let req = CreateReportRequest(reasonType: reasonType, reason: reason, subject: subject)
        let _: CreateReportResponse = try await network.post(
            lexicon: "com.atproto.moderation.createReport",
            body: req,
            proxyDID: labelerDID
        )
    }
}
