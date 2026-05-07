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

    public init(
        id: String,
        rev: String,
        text: String,
        embed: EmbedView?,
        sender: MessageSender,
        sentAt: Date
    ) {
        self.id = id
        self.rev = rev
        self.text = text
        self.embed = embed
        self.sender = sender
        self.sentAt = sentAt
    }
}

/// The sender reference inside a `MessageView`.
public struct MessageSender: Codable, Sendable {
    public let did: DID

    public init(did: DID) {
        self.did = did
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
