import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class MessageThreadViewModel {

    public var messages: [MessageView] = []
    public var cursor: String?
    public var isLoading = false
    public var isSending = false
    public var errorMessage: String?
    public var convo: ConvoView?

    public let convoId: String
    private let viewerDID: DID?
    private let network: any NetworkClient

    public init(convoId: String, viewerDID: DID? = nil, network: any NetworkClient) {
        self.convoId = convoId
        self.viewerDID = viewerDID
        self.network = network
    }

    public func isOwn(_ message: MessageView) -> Bool {
        guard let viewerDID else { return false }
        return message.sender.did == viewerDID
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let resp: GetMessagesResponse = try await network.get(
                lexicon: "chat.bsky.convo.getMessages",
                params: ["convoId": convoId, "limit": "50"]
            )
            messages = resp.messages.reversed()
            cursor = resp.cursor
            await markRead()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadOlder() async {
        guard !isLoading, let cursor else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: GetMessagesResponse = try await network.get(
                lexicon: "chat.bsky.convo.getMessages",
                params: ["convoId": convoId, "limit": "50", "cursor": cursor]
            )
            messages.insert(contentsOf: resp.messages.reversed(), at: 0)
            self.cursor = resp.cursor
        } catch {}
    }

    public func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let req = SendMessageRequest(
                convoId: convoId,
                message: MessageInput(text: trimmed)
            )
            let sent: MessageView = try await network.post(
                lexicon: "chat.bsky.convo.sendMessage", body: req
            )
            messages.append(sent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markRead() async {
        do {
            let _: ConvoResponse = try await network.post(
                lexicon: "chat.bsky.convo.updateRead",
                body: UpdateReadRequest(convoId: convoId)
            )
        } catch {}
    }
}
