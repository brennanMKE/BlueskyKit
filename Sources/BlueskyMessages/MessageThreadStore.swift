import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "MessageThreadStore")

// MARK: - MessageThreadStoring

public protocol MessageThreadStoring: AnyObject, Observable, Sendable {
    /// Discriminated stream of every row the thread should render — real
    /// messages (`MessageView`), tombstones (`DeletedMessageView`), and system
    /// events (`SystemMessageView`). RN parity: `state/messages/convo/agent.ts`
    /// itemizes the same union into its `ConvoItem[]`.
    var messages: [ConvoMessage] { get }
    var isLoading: Bool { get }
    var isSending: Bool { get }
    var errorMessage: String? { get }
    var convo: ConvoView? { get }
    var hasOlderMessages: Bool { get }

    func load(convoId: String) async
    func loadOlder(convoId: String) async
    func sendMessage(_ text: String, convoId: String) async
    func sendImageAttachment(data: Data, mimeType: String, convoId: String) async
    /// Hide a message from the caller's view via `chat.bsky.convo.deleteMessageForSelf`.
    /// Optimistically removes the message from `messages`; on failure the
    /// message is restored at its original index and `errorMessage` is set.
    /// No-op (returns `false`) if the targeted ID does not refer to a real
    /// `.message(_)` row.
    @discardableResult
    func deleteMessage(_ messageId: String, convoId: String) async -> Bool

    /// Add an emoji reaction to a message (`chat.bsky.convo.addReaction`).
    /// `viewerDID` is the caller's DID, used to construct the optimistic
    /// `ReactionView` so the strip updates immediately. Returns `true` on
    /// success; on failure the optimistic reaction is rolled back and
    /// `errorMessage` is set. RN reference: agent.ts#addReaction. No-op on
    /// non-message rows.
    @discardableResult
    func addReaction(messageId: String, emoji: String, viewerDID: DID?, convoId: String) async -> Bool

    /// Remove the caller's emoji reaction from a message
    /// (`chat.bsky.convo.removeReaction`). Optimistically drops the matching
    /// `(value, sender == viewerDID)` reaction; restored on failure. No-op on
    /// non-message rows.
    @discardableResult
    func removeReaction(messageId: String, emoji: String, viewerDID: DID?, convoId: String) async -> Bool
}

// MARK: - MessageThreadStore

@Observable
public final class MessageThreadStore: MessageThreadStoring {

    public private(set) var messages: [ConvoMessage] = []
    public private(set) var isLoading = false
    public private(set) var isSending = false
    public private(set) var errorMessage: String?
    public private(set) var convo: ConvoView?
    public var hasOlderMessages: Bool { cursor != nil }

    private var cursor: String?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    public func load(convoId: String) async {
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
            await markRead(convoId: convoId)
        } catch {
            logger.error("messages fetch error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func loadOlder(convoId: String) async {
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

    public func sendMessage(_ text: String, convoId: String) async {
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
            messages.append(.message(sent))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func sendImageAttachment(data: Data, mimeType: String, convoId: String) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let uploadResp: UploadBlobResponse = try await network.upload(
                lexicon: "com.atproto.repo.uploadBlob",
                data: data,
                mimeType: mimeType
            )
            let blobRef = uploadResp.blob
            let embed = Embed.images([EmbedImage(image: blobRef, alt: "", aspectRatio: nil)])
            let req = SendMessageRequest(
                convoId: convoId,
                message: MessageInput(text: "", embed: embed)
            )
            let sent: MessageView = try await network.post(
                lexicon: "chat.bsky.convo.sendMessage", body: req
            )
            messages.append(.message(sent))
        } catch {
            logger.error("image attachment send error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func deleteMessage(_ messageId: String, convoId: String) async -> Bool {
        guard let index = messageIndex(of: messageId) else {
            return false
        }
        // Optimistic removal — restore on failure.
        let removed = messages.remove(at: index)
        do {
            let _: DeleteMessageForSelfResponse = try await network.post(
                lexicon: "chat.bsky.convo.deleteMessageForSelf",
                body: DeleteMessageForSelfRequest(convoId: convoId, messageId: messageId)
            )
            return true
        } catch {
            logger.error("delete message failed: \(error, privacy: .public)")
            // Re-insert at original position so ordering is preserved.
            let insertAt = min(index, messages.count)
            messages.insert(removed, at: insertAt)
            errorMessage = "Failed to delete message"
            return false
        }
    }

    @discardableResult
    public func addReaction(messageId: String, emoji: String, viewerDID: DID?, convoId: String) async -> Bool {
        guard let index = messageIndex(of: messageId),
              case .message(let original) = messages[index] else { return false }
        // Optimistic insertion. Skip if the caller already reacted with this
        // emoji — RN agent.ts mirrors this guard so a duplicate tap is a no-op
        // rather than a server round trip.
        if let viewerDID, let existing = original.reactions,
           existing.contains(where: { $0.value == emoji && $0.sender.did == viewerDID }) {
            return true
        }
        if let viewerDID {
            let optimistic = ReactionView(
                value: emoji,
                sender: ReactionSender(did: viewerDID),
                createdAt: Date()
            )
            var newReactions = original.reactions ?? []
            newReactions.append(optimistic)
            messages[index] = .message(MessageView(
                id: original.id,
                rev: original.rev,
                text: original.text,
                embed: original.embed,
                sender: original.sender,
                sentAt: original.sentAt,
                reactions: newReactions
            ))
        }
        do {
            let resp: ReactionResponse = try await network.post(
                lexicon: "chat.bsky.convo.addReaction",
                body: AddReactionRequest(convoId: convoId, messageId: messageId, value: emoji)
            )
            if let i = messageIndex(of: messageId) {
                messages[i] = .message(resp.message)
            }
            return true
        } catch {
            logger.error("addReaction failed: \(error, privacy: .public)")
            // Roll back optimistic update.
            if let i = messageIndex(of: messageId) {
                messages[i] = .message(original)
            }
            errorMessage = "Failed to add reaction"
            return false
        }
    }

    @discardableResult
    public func removeReaction(messageId: String, emoji: String, viewerDID: DID?, convoId: String) async -> Bool {
        guard let index = messageIndex(of: messageId),
              case .message(let original) = messages[index] else { return false }
        // Optimistic removal of the caller's matching reaction.
        if let viewerDID, let existing = original.reactions {
            let trimmed = existing.filter { !($0.value == emoji && $0.sender.did == viewerDID) }
            messages[index] = .message(MessageView(
                id: original.id,
                rev: original.rev,
                text: original.text,
                embed: original.embed,
                sender: original.sender,
                sentAt: original.sentAt,
                reactions: trimmed.isEmpty ? nil : trimmed
            ))
        }
        do {
            let resp: ReactionResponse = try await network.post(
                lexicon: "chat.bsky.convo.removeReaction",
                body: RemoveReactionRequest(convoId: convoId, messageId: messageId, value: emoji)
            )
            if let i = messageIndex(of: messageId) {
                messages[i] = .message(resp.message)
            }
            return true
        } catch {
            logger.error("removeReaction failed: \(error, privacy: .public)")
            if let i = messageIndex(of: messageId) {
                messages[i] = .message(original)
            }
            errorMessage = "Failed to remove reaction"
            return false
        }
    }

    /// Look up the row index for a given message ID across all variants. The
    /// reaction / delete mutators short-circuit on non-message rows once they
    /// have the index in hand, so a single shared lookup keeps the code paths
    /// honest.
    private func messageIndex(of messageId: String) -> Int? {
        messages.firstIndex(where: { $0.id == messageId })
    }

    private func markRead(convoId: String) async {
        do {
            let _: ConvoResponse = try await network.post(
                lexicon: "chat.bsky.convo.updateRead",
                body: UpdateReadRequest(convoId: convoId)
            )
        } catch {}
    }
}
