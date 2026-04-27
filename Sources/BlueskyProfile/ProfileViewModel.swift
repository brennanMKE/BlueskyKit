import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class ProfileViewModel {

    public var profile: ProfileDetailed? { store.profile }
    public var isLoading: Bool { store.isLoading }
    public var errorMessage: String? { store.errorMessage }

    public func posts(for tab: ProfileTab) -> [FeedViewPost] { store.posts(for: tab) }
    public func isLoadingFeed(for tab: ProfileTab) -> Bool { store.isLoadingFeed(for: tab) }

    public let actorDID: DID
    private let store: any ProfileStoring

    public init(network: any NetworkClient, accountStore: any AccountStore, actorDID: DID) {
        self.store = ProfileStore(network: network, accountStore: accountStore)
        self.actorDID = actorDID
    }

    public func loadProfile() async { await store.loadProfile(actorDID: actorDID) }
    public func loadFeed(tab: ProfileTab) async { await store.loadFeed(tab: tab, actorDID: actorDID) }
    public func loadMoreFeed(tab: ProfileTab) async { await store.loadMoreFeed(tab: tab, actorDID: actorDID) }
    public func follow() async { await store.follow() }
    public func unfollow() async { await store.unfollow() }
    public func block() async { await store.block() }
    public func unblock() async { await store.unblock() }
    public func mute() async { await store.mute() }
    public func unmute() async { await store.unmute() }
    public func updateProfile(displayName: String?, description: String?) async throws {
        try await store.updateProfile(displayName: displayName, description: description)
    }
}
