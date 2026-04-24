import Foundation

// MARK: - chat.bsky.convo.defs

/// A conversation view returned by `chat.bsky.convo.listConvos` and `chat.bsky.convo.getConvo`.
public struct ConvoView: Codable, Sendable {
    public let id: String
    public let rev: String
    public let members: [ProfileBasic]
    public let lastMessage: MessageView?
    public let unreadCount: Int
    public let muted: Bool

    public init(
        id: String,
        rev: String,
        members: [ProfileBasic],
        lastMessage: MessageView?,
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
