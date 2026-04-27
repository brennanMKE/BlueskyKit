import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class StarterPackViewModel {

    public var starterPack: StarterPackView? { store.starterPack }
    public var isLoading: Bool { store.isLoading }
    public var error: String? { store.error }

    private let store: any ListsStoring

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.store = ListsStore(network: network, accountStore: accountStore)
    }

    public func load(uri: ATURI) async { await store.loadStarterPack(uri: uri) }
    public func followAll(pack: StarterPackView) async { await store.followAll(pack: pack) }
    public func clearError() { store.clearError() }
}
