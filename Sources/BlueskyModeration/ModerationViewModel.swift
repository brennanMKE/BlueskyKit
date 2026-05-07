import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class ModerationViewModel {

    public var mutes: [ProfileView] { store.mutes }
    public var blocks: [ProfileView] { store.blocks }
    /// Mod lists the signed-in viewer authored. The store filters the
    /// `getLists` response to `purpose == modlist` and never includes
    /// subscribed-only lists.
    public var modLists: [ListView] { store.modLists }
    /// Mod lists the viewer is subscribed to without owning. Drawn from
    /// `getListMutes` and `getListBlocks` (purpose-filtered, viewer-DID
    /// excluded). The Moderation Lists screen renders these in a
    /// "Subscribed" section with an Unsubscribe action.
    public var subscribedModLists: [ListView] { store.subscribedModLists }
    public var adultContentEnabled: Bool {
        get { store.adultContentEnabled }
        set { store.adultContentEnabled = newValue }
    }
    public var contentLabels: [ContentLabelPref] { store.contentLabels }
    public var subscribedLabelers: [LabelerView] { store.subscribedLabelers }
    public var subscribedLabelerDIDs: [DID] { store.subscribedLabelerDIDs }
    public var unavailableLabelerDIDs: [DID] { store.unavailableLabelerDIDs }
    public var isLoadingLabelers: Bool { store.isLoadingLabelers }
    public var hasMoreMutes: Bool { store.hasMoreMutes }
    public var hasMoreBlocks: Bool { store.hasMoreBlocks }
    public var hasMoreModLists: Bool { store.hasMoreModLists }
    /// `true` while either the subscribed-mutes or subscribed-blocks
    /// pagination still has a cursor. Used by the Moderation Lists screen's
    /// tail-of-section trigger.
    public var hasMoreSubscribedModLists: Bool {
        store.hasMoreSubscribedMutes || store.hasMoreSubscribedBlocks
    }
    public var isLoading: Bool { store.isLoading }
    public var errorMessage: String? { store.errorMessage }

    /// Resolved on first appearance via `accountStore.loadCurrentDID()`. The
    /// Moderation Lists screen consults this to drive owner-only edit /
    /// delete affordances, mirroring the pattern from #0131. `nil` when
    /// logged out — affordances stay hidden in that case.
    public private(set) var viewerDID: DID?

    private let store: any ModerationStoring
    private let accountStore: any AccountStore

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.store = ModerationStore(network: network, accountStore: accountStore)
        self.accountStore = accountStore
    }

    /// Resolves the signed-in viewer DID and caches it on the view model.
    /// Failures leave `viewerDID == nil` (the logged-out path), which the
    /// screen handles by hiding owner-only affordances.
    public func resolveViewerDID() async {
        if viewerDID == nil {
            viewerDID = try? await accountStore.loadCurrentDID()
        }
    }

    public func loadMutes() async { await store.loadMutes() }
    public func loadMoreMutes() async { await store.loadMoreMutes() }
    public func loadBlocks() async { await store.loadBlocks() }
    public func loadMoreBlocks() async { await store.loadMoreBlocks() }
    public func loadModLists() async { await store.loadModLists() }
    public func loadMoreModLists() async { await store.loadMoreModLists() }
    public func loadMoreSubscribedModLists() async { await store.loadMoreSubscribedModLists() }
    public func loadPreferences() async { await store.loadPreferences() }
    public func loadSubscribedLabelers() async { await store.loadSubscribedLabelers() }
    public func removeUnavailableLabelers() async { await store.removeUnavailableLabelers() }
    public func unmute(did: DID) async { await store.unmute(did: did) }
    public func unblock(profile: ProfileView) async { await store.unblock(profile: profile) }
    public func muteList(_ listURI: ATURI) async { await store.muteList(listURI) }
    public func unmuteList(_ listURI: ATURI) async { await store.unmuteList(listURI) }
    /// Unsubscribe from a mod list the viewer doesn't own. Picks the right
    /// XRPC call based on the list's `viewer` state — muted lists call
    /// `unmuteActorList`; blocked lists delete the matching `listblock`
    /// record via `deleteRecord`. Mirrors RN's
    /// `useListMuteMutation` / `useListBlockMutation` split.
    public func unsubscribe(from list: ListView) async {
        if list.viewer?.muted == true {
            await store.unmuteList(list.uri)
        }
        if list.viewer?.blocked != nil {
            await store.unblockList(list)
        }
    }
    public func setAdultContent(enabled: Bool) async { await store.setAdultContent(enabled: enabled) }
    public func setLabelVisibility(label: String, labelerDid: DID?, visibility: String) async {
        await store.setLabelVisibility(label: label, labelerDid: labelerDid, visibility: visibility)
    }
    public func report(
        subject: some Encodable & Sendable,
        reasonType: String,
        reason: String?,
        labelerDID: DID? = nil
    ) async throws {
        try await store.report(
            subject: subject,
            reasonType: reasonType,
            reason: reason,
            labelerDID: labelerDID
        )
    }
}
