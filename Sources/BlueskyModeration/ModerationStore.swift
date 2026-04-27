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
    var adultContentEnabled: Bool { get set }
    var contentLabels: [ContentLabelPref] { get }
    var hasMoreMutes: Bool { get }
    var hasMoreBlocks: Bool { get }
    var hasMoreModLists: Bool { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func loadMutes() async
    func loadMoreMutes() async
    func loadBlocks() async
    func loadMoreBlocks() async
    func loadModLists() async
    func loadMoreModLists() async
    func loadPreferences() async
    func unmute(did: DID) async
    func unblock(profile: ProfileView) async
    func muteList(_ listURI: ATURI) async
    func unmuteList(_ listURI: ATURI) async
    func setAdultContent(enabled: Bool) async
    func setLabelVisibility(label: String, labelerDid: DID?, visibility: String) async
    func report(subject: some Encodable & Sendable, reasonType: String, reason: String?) async throws
}

// MARK: - ModerationStore

@Observable
public final class ModerationStore: ModerationStoring {

    public private(set) var mutes: [ProfileView] = []
    public private(set) var blocks: [ProfileView] = []
    public private(set) var modLists: [ListView] = []
    public var adultContentEnabled = false
    public private(set) var contentLabels: [ContentLabelPref] = []
    public private(set) var hasMoreMutes = true
    public private(set) var hasMoreBlocks = true
    public private(set) var hasMoreModLists = true
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private var mutesCursor: Cursor?
    private var blocksCursor: Cursor?
    private var modListsCursor: Cursor?

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

    public func loadModLists() async {
        guard let viewerDID = try? await accountStore.loadCurrentDID() else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let resp: GetListsResponse = try await network.get(
                lexicon: "app.bsky.graph.getLists",
                params: ["actor": viewerDID.rawValue, "limit": "50"]
            )
            modLists = resp.lists.filter { $0.purpose == "app.bsky.graph.defs#modlist" }
            modListsCursor = resp.cursor
            hasMoreModLists = resp.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadMoreModLists() async {
        guard hasMoreModLists, let cursor = modListsCursor,
              let viewerDID = try? await accountStore.loadCurrentDID() else { return }
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

    // MARK: - Preferences

    public func loadPreferences() async {
        do {
            let resp: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            adultContentEnabled = resp.adultContentEnabled
            contentLabels = resp.contentLabels
        } catch {
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
              let rkey = blockURI.rkey,
              let viewerDID = try? await accountStore.loadCurrentDID() else { return }
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
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.graph.unmuteActorList",
                body: ListMuteRequest(list: listURI)
            )
        } catch {
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
            let req = PutPreferencesRequest(adultContentEnabled: adultContentEnabled, contentLabels: contentLabels)
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.actor.putPreferences", body: req
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Report

    public func report(subject: some Encodable & Sendable, reasonType: String, reason: String?) async throws {
        let req = CreateReportRequest(reasonType: reasonType, reason: reason, subject: subject)
        let _: CreateReportResponse = try await network.post(
            lexicon: "com.atproto.moderation.createReport", body: req
        )
    }
}
