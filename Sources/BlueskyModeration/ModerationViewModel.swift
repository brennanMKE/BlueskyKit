import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class ModerationViewModel {

    public var mutes: [ProfileView] { store.mutes }
    public var blocks: [ProfileView] { store.blocks }
    public var modLists: [ListView] { store.modLists }
    public var adultContentEnabled: Bool {
        get { store.adultContentEnabled }
        set { store.adultContentEnabled = newValue }
    }
    public var contentLabels: [ContentLabelPref] { store.contentLabels }
    public var hasMoreMutes: Bool { store.hasMoreMutes }
    public var hasMoreBlocks: Bool { store.hasMoreBlocks }
    public var hasMoreModLists: Bool { store.hasMoreModLists }
    public var isLoading: Bool { store.isLoading }
    public var errorMessage: String? { store.errorMessage }

    private let store: any ModerationStoring

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.store = ModerationStore(network: network, accountStore: accountStore)
    }

    public func loadMutes() async { await store.loadMutes() }
    public func loadMoreMutes() async { await store.loadMoreMutes() }
    public func loadBlocks() async { await store.loadBlocks() }
    public func loadMoreBlocks() async { await store.loadMoreBlocks() }
    public func loadModLists() async { await store.loadModLists() }
    public func loadMoreModLists() async { await store.loadMoreModLists() }
    public func loadPreferences() async { await store.loadPreferences() }
    public func unmute(did: DID) async { await store.unmute(did: did) }
    public func unblock(profile: ProfileView) async { await store.unblock(profile: profile) }
    public func muteList(_ listURI: ATURI) async { await store.muteList(listURI) }
    public func unmuteList(_ listURI: ATURI) async { await store.unmuteList(listURI) }
    public func setAdultContent(enabled: Bool) async { await store.setAdultContent(enabled: enabled) }
    public func setLabelVisibility(label: String, labelerDid: DID?, visibility: String) async {
        await store.setLabelVisibility(label: label, labelerDid: labelerDid, visibility: visibility)
    }
    public func report(subject: some Encodable & Sendable, reasonType: String, reason: String?) async throws {
        try await store.report(subject: subject, reasonType: reasonType, reason: reason)
    }
}
