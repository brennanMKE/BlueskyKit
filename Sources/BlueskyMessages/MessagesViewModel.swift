import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class MessagesViewModel {

    public var convos: [ConvoView] { store.convos }
    public var isLoading: Bool { store.isLoading }
    public var errorMessage: String? { store.errorMessage }

    private let store: any ConversationStoring

    public init(network: any NetworkClient) {
        self.store = ConversationStore(network: network)
    }

    public func loadInitial() async { await store.loadInitial() }
    public func loadMore() async { await store.loadMore() }
    public func refresh() async { await store.refresh() }
    public func leaveConvo(_ convoId: String) async { await store.leaveConvo(convoId) }
    public func muteConvo(_ convoId: String, muted: Bool) async { await store.muteConvo(convoId, muted: muted) }
}
