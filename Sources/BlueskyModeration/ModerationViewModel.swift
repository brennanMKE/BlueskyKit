import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class ModerationViewModel {

    // MARK: - Mutes

    public var mutes: [ProfileView] = []
    private var mutesCursor: Cursor?
    public var hasMoreMutes = true

    // MARK: - Blocks

    public var blocks: [ProfileView] = []
    private var blocksCursor: Cursor?
    public var hasMoreBlocks = true

    // MARK: - Moderation lists

    public var modLists: [ListView] = []
    private var modListsCursor: Cursor?
    public var hasMoreModLists = true

    // MARK: - Content filter preferences

    public var adultContentEnabled = false
    public var contentLabels: [ContentLabelPref] = []

    // MARK: - State

    public var isLoading = false
    public var errorMessage: String?

    // MARK: - Dependencies

    private let network: any NetworkClient
    private let accountStore: any AccountStore

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.network = network
        self.accountStore = accountStore
    }

    // MARK: - Load mutes

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

    // MARK: - Load blocks

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

    // MARK: - Load moderation lists

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

    // MARK: - Load preferences

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
            let req = MuteActorRequest(actor: did)
            let _: EmptyResponse = try await network.post(lexicon: "app.bsky.graph.unmuteActor", body: req)
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
            let req = DeleteRecordRequest(
                repo: viewerDID.rawValue,
                collection: "app.bsky.graph.block",
                rkey: rkey
            )
            let _: EmptyResponse = try await network.post(lexicon: "com.atproto.repo.deleteRecord", body: req)
        } catch {
            blocks.insert(removed, at: 0)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mute / unmute list

    public func muteList(_ listURI: ATURI) async {
        do {
            let req = ListMuteRequest(list: listURI)
            let _: EmptyResponse = try await network.post(lexicon: "app.bsky.graph.muteActorList", body: req)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func unmuteList(_ listURI: ATURI) async {
        do {
            let req = ListMuteRequest(list: listURI)
            let _: EmptyResponse = try await network.post(lexicon: "app.bsky.graph.unmuteActorList", body: req)
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
            let _: EmptyResponse = try await network.post(lexicon: "app.bsky.actor.putPreferences", body: req)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Report

    public func report(
        subject: some Encodable & Sendable,
        reasonType: String,
        reason: String?
    ) async throws {
        let req = CreateReportRequest(reasonType: reasonType, reason: reason, subject: subject)
        let _: CreateReportResponse = try await network.post(
            lexicon: "com.atproto.moderation.createReport",
            body: req
        )
    }
}
