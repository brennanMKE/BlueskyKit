import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class MessageThreadViewModel {

    public var messages: [MessageView] { store.messages }
    public var isLoading: Bool { store.isLoading }
    public var isSending: Bool { store.isSending }
    public var errorMessage: String? { store.errorMessage }
    public var convo: ConvoView? { store.convo }
    public var hasOlderMessages: Bool { store.hasOlderMessages }

    public let convoId: String
    private let viewerDID: DID?
    private let store: any MessageThreadStoring

    public init(convoId: String, viewerDID: DID? = nil, network: any NetworkClient) {
        self.convoId = convoId
        self.viewerDID = viewerDID
        self.store = MessageThreadStore(network: network)
    }

    public func isOwn(_ message: MessageView) -> Bool {
        guard let viewerDID else { return false }
        return message.sender.did == viewerDID
    }

    public func load() async { await store.load(convoId: convoId) }
    public func loadOlder() async { await store.loadOlder(convoId: convoId) }
    public func sendMessage(_ text: String) async { await store.sendMessage(text, convoId: convoId) }
}
