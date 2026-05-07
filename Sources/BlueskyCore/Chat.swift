import Foundation

// MARK: - chat.bsky.convo.defs

/// A conversation view returned by `chat.bsky.convo.listConvos` and `chat.bsky.convo.getConvo`.
public struct ConvoView: Codable, Sendable {
    public let id: String
    public let rev: String
    public let members: [ProfileBasic]
    /// Discriminated union — either a real message or a system "deleted message" placeholder.
    /// See `chat.bsky.convo.defs#messageView` and `#deletedMessageView`.
    public let lastMessage: ConvoLastMessage?
    public let unreadCount: Int
    public let muted: Bool

    public init(
        id: String,
        rev: String,
        members: [ProfileBasic],
        lastMessage: ConvoLastMessage?,
        unreadCount: Int,
        muted: Bool
    ) {
        self.id = id
        self.rev = rev
        self.members = members
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.muted = muted
    }
}

/// Discriminated union covering the variants `chat.bsky.convo.defs` may emit
/// inside `convoView.lastMessage`.
public enum ConvoLastMessage: Codable, Sendable {
    case message(MessageView)
    case deleted(DeletedMessageView)

    private enum DiscriminatorKeys: String, CodingKey {
        case type = "$type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        let single = try decoder.singleValueContainer()
        switch type {
        case "chat.bsky.convo.defs#deletedMessageView":
            self = .deleted(try single.decode(DeletedMessageView.self))
        case "chat.bsky.convo.defs#messageView", nil, "":
            // Default to message variant when the server omits `$type`.
            self = .message(try single.decode(MessageView.self))
        default:
            // Unknown variant — try message decode as a best-effort fallback,
            // otherwise treat as deleted so the UI can render a placeholder.
            if let msg = try? single.decode(MessageView.self) {
                self = .message(msg)
            } else {
                self = .deleted(try single.decode(DeletedMessageView.self))
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .message(let m): try single.encode(m)
        case .deleted(let d): try single.encode(d)
        }
    }

    /// Returns the underlying `MessageView` if this is a real message, otherwise `nil`.
    public var messageView: MessageView? {
        if case .message(let m) = self { return m }
        return nil
    }

    /// Returns the deleted-message placeholder if this is a deleted variant, otherwise `nil`.
    public var deletedView: DeletedMessageView? {
        if case .deleted(let d) = self { return d }
        return nil
    }

    /// Convenience for sorting / time display — the timestamp of either variant.
    public var sentAt: Date {
        switch self {
        case .message(let m): return m.sentAt
        case .deleted(let d): return d.sentAt
        }
    }

    /// The sender of either variant.
    public var sender: MessageSender {
        switch self {
        case .message(let m): return m.sender
        case .deleted(let d): return d.sender
        }
    }
}

/// A "tombstone" placeholder returned in place of a deleted message
/// (`chat.bsky.convo.defs#deletedMessageView`).
public struct DeletedMessageView: Codable, Sendable {
    public let id: String
    public let rev: String
    public let sender: MessageSender
    public let sentAt: Date

    public init(id: String, rev: String, sender: MessageSender, sentAt: Date) {
        self.id = id
        self.rev = rev
        self.sender = sender
        self.sentAt = sentAt
    }
}

/// A message as returned in convo views and message lists.
public struct MessageView: Codable, Sendable {
    public let id: String
    public let rev: String
    public let text: String
    public let embed: EmbedView?
    public let sender: MessageSender
    public let sentAt: Date
    /// Per-message emoji reactions (`chat.bsky.convo.defs#messageView.reactions`).
    /// Optional — the server omits the array entirely when no one has reacted.
    /// RN reference: `state/messages/convo/agent.ts` (`addReaction` /
    /// `removeReaction`) reads and mutates `prevMessage.reactions`.
    public let reactions: [ReactionView]?

    public init(
        id: String,
        rev: String,
        text: String,
        embed: EmbedView?,
        sender: MessageSender,
        sentAt: Date,
        reactions: [ReactionView]? = nil
    ) {
        self.id = id
        self.rev = rev
        self.text = text
        self.embed = embed
        self.sender = sender
        self.sentAt = sentAt
        self.reactions = reactions
    }
}

/// The sender reference inside a `MessageView`.
public struct MessageSender: Codable, Sendable {
    public let did: DID

    public init(did: DID) {
        self.did = did
    }
}

// MARK: - chat.bsky.convo.defs#reactionView

/// A single emoji reaction on a message
/// (`chat.bsky.convo.defs#reactionView`). Multiple reactions with the same
/// `value` from different senders are kept as separate entries — the UI groups
/// them by value when rendering the strip.
public struct ReactionView: Codable, Sendable, Hashable {
    /// The emoji grapheme — RN treats this as a single grapheme; we don't
    /// validate length here so we round-trip whatever the server sent.
    public let value: String
    /// The user who reacted. Only `did` is populated by the server here; full
    /// profile resolution requires a separate lookup.
    public let sender: ReactionSender
    /// Server-issued reaction creation timestamp.
    public let createdAt: Date

    public init(value: String, sender: ReactionSender, createdAt: Date) {
        self.value = value
        self.sender = sender
        self.createdAt = createdAt
    }
}

/// The sender reference inside a `ReactionView`
/// (`chat.bsky.convo.defs#reactionViewSender`). Mirrors `MessageSender` but is
/// kept distinct so the lexicons stay 1:1 with the upstream defs in case the
/// server adds fields to either side.
public struct ReactionSender: Codable, Sendable, Hashable {
    public let did: DID

    public init(did: DID) {
        self.did = did
    }
}

// MARK: - chat.bsky.convo.addReaction / removeReaction

/// Request body for `chat.bsky.convo.addReaction`. RN reference:
/// `state/messages/convo/agent.ts#addReaction` — the agent posts
/// `{messageId, value, convoId}` and receives back the updated `MessageView`
/// (with the new reaction included) inside `data.message`.
public struct AddReactionRequest: Encodable, Sendable {
    public let convoId: String
    public let messageId: String
    public let value: String

    public init(convoId: String, messageId: String, value: String) {
        self.convoId = convoId
        self.messageId = messageId
        self.value = value
    }
}

/// Request body for `chat.bsky.convo.removeReaction`. Same shape as
/// `AddReactionRequest` — the value identifies which reaction (per
/// `(sender, value)`) to remove for the calling user. Server returns the
/// updated `MessageView`.
public struct RemoveReactionRequest: Encodable, Sendable {
    public let convoId: String
    public let messageId: String
    public let value: String

    public init(convoId: String, messageId: String, value: String) {
        self.convoId = convoId
        self.messageId = messageId
        self.value = value
    }
}

/// Response wrapper for both `addReaction` and `removeReaction` — both return
/// `{message: MessageView}` so the client can replace its local copy with the
/// server-of-record version (including the recomputed `reactions` array).
public struct ReactionResponse: Decodable, Sendable {
    public let message: MessageView

    public init(message: MessageView) {
        self.message = message
    }
}

// MARK: - chat.bsky.convo.listConvos

public struct ListConvosResponse: Codable, Sendable {
    public let convos: [ConvoView]
    public let cursor: Cursor?

    public init(convos: [ConvoView], cursor: Cursor?) {
        self.convos = convos
        self.cursor = cursor
    }
}

// MARK: - chat.bsky.convo.getMessages

public struct GetMessagesResponse: Codable, Sendable {
    public let messages: [MessageView]
    public let cursor: Cursor?

    public init(messages: [MessageView], cursor: Cursor?) {
        self.messages = messages
        self.cursor = cursor
    }
}

// MARK: - chat.bsky.convo.sendMessage

public struct MessageInput: Encodable, Sendable {
    public let text: String
    public let embed: Embed?

    public init(text: String, embed: Embed? = nil) {
        self.text = text
        self.embed = embed
    }
}

public struct SendMessageRequest: Encodable, Sendable {
    public let convoId: String
    public let message: MessageInput

    public init(convoId: String, message: MessageInput) {
        self.convoId = convoId
        self.message = message
    }
}

// MARK: - chat.bsky.convo.deleteMessageForSelf

/// Request body for `chat.bsky.convo.deleteMessageForSelf`. Hides a message
/// from the caller's view of the conversation only; other participants still
/// see it. RN reference: `state/messages/convo/agent.ts#deleteMessage`.
public struct DeleteMessageForSelfRequest: Encodable, Sendable {
    public let convoId: String
    public let messageId: String

    public init(convoId: String, messageId: String) {
        self.convoId = convoId
        self.messageId = messageId
    }
}

/// The endpoint returns a `DeletedMessageView` (a tombstone) — we reuse the
/// existing type from the convo defs.
public typealias DeleteMessageForSelfResponse = DeletedMessageView

// MARK: - chat.bsky.convo.leaveConvo / muteConvo / unmuteConvo / updateRead

public struct ConvoIDRequest: Encodable, Sendable {
    public let convoId: String
    public init(convoId: String) { self.convoId = convoId }
}

public struct ConvoResponse: Decodable, Sendable {
    public let convo: ConvoView
}

public struct UpdateReadRequest: Encodable, Sendable {
    public let convoId: String
    public let messageId: String?
    public init(convoId: String, messageId: String? = nil) {
        self.convoId = convoId
        self.messageId = messageId
    }
}
