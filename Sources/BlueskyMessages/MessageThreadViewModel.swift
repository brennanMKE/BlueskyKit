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

    /// ID of the first message that arrived while the user was scrolled away
    /// from the bottom of the thread. RN parity: when set, the message list
    /// renders a centered "New messages" divider above this row so the reader
    /// can see where they left off (`MessagesList.tsx` → `NewMessagesPill` +
    /// the inline divider rendered by `MessageItem`). Cleared once the user
    /// scrolls back to the bottom.
    public var firstUnreadID: String?

    /// Number of messages that have arrived since the user scrolled away from
    /// the bottom — used to optionally surface a count on the floating "Jump
    /// to newest" pill. Reset to zero when `firstUnreadID` is cleared.
    public var unreadCount: Int = 0

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
    public func sendImageAttachment(data: Data, mimeType: String = "image/jpeg") async {
        await store.sendImageAttachment(data: data, mimeType: mimeType, convoId: convoId)
    }

    /// Hide a message from the caller's view (`chat.bsky.convo.deleteMessageForSelf`).
    /// Returns `true` on success. Optimistic — restores the message locally on failure.
    @discardableResult
    public func deleteMessage(_ messageId: String) async -> Bool {
        await store.deleteMessage(messageId, convoId: convoId)
    }

    /// Add an emoji reaction to a message (`chat.bsky.convo.addReaction`). The
    /// store performs an optimistic update and rolls back on failure. Returns
    /// `true` on success.
    @discardableResult
    public func addReaction(messageID: String, emoji: String) async -> Bool {
        await store.addReaction(messageId: messageID, emoji: emoji, viewerDID: viewerDID, convoId: convoId)
    }

    /// Remove the caller's own emoji reaction from a message
    /// (`chat.bsky.convo.removeReaction`). Optimistic, with rollback on failure.
    @discardableResult
    public func removeReaction(messageID: String, emoji: String) async -> Bool {
        await store.removeReaction(messageId: messageID, emoji: emoji, viewerDID: viewerDID, convoId: convoId)
    }

    /// Caller's DID — exposed so the UI can mark "your" reaction in the
    /// reaction strip without re-deriving it from `isOwn(_:)`. Optional because
    /// preview/no-session contexts may construct the view model without one.
    public var viewerDIDPublic: DID? { viewerDID }

    /// Mark the unread-state cleared. Called when the user scrolls back to the
    /// bottom of the thread or taps the "Jump to newest" pill.
    public func clearUnread() {
        firstUnreadID = nil
        unreadCount = 0
    }

    /// Note that a new message arrived while the reader was scrolled up. If
    /// no `firstUnreadID` is set yet (i.e. this is the first new message of
    /// the run) we anchor the divider here. Subsequent calls just bump the
    /// counter so the FAB can show how many messages are queued up.
    public func noteNewUnread(messageID: String) {
        if firstUnreadID == nil {
            firstUnreadID = messageID
        }
        unreadCount += 1
    }
}
