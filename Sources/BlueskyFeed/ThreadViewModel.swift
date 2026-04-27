import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class ThreadViewModel {

    public var thread: ThreadViewPost? { store.thread }
    public var isLoading: Bool { store.isLoading }
    public var errorMessage: String? { store.errorMessage }

    private let store: any ThreadStoring
    private let uri: ATURI

    public init(network: any NetworkClient, uri: ATURI) {
        self.store = ThreadStore(network: network)
        self.uri = uri
    }

    public func load() async {
        await store.load(uri: uri)
    }
}
