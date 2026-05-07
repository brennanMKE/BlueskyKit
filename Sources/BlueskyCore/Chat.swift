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
/// inside `convoView.lastMessage`. Mirrors `ConvoMessage` (the in-thread
/// variant) but with its own decoder so the conversation-list row can render
/// a sensible preview for every shape the server may serve as the most-recent
/// item — including system events (members added, group renamed, etc.).
public enum ConvoLastMessage: Codable, Sendable {
    case message(MessageView)
    case deleted(DeletedMessageView)
    case system(SystemMessageView)

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
        case "chat.bsky.convo.defs#systemMessageView":
            self = .system(try single.decode(SystemMessageView.self))
        case "chat.bsky.convo.defs#messageView", nil, "":
            // Default to message variant when the server omits `$type`.
            self = .message(try single.decode(MessageView.self))
        default:
            // Unknown variant — try message decode as a best-effort fallback,
            // otherwise treat as deleted so the UI can render a placeholder.
            if let msg = try? single.decode(MessageView.self) {
                self = .message(msg)
            } else if let sys = try? single.decode(SystemMessageView.self) {
                self = .system(sys)
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
        case .system(let s): try single.encode(s)
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

    /// Returns the system-message variant if this is a group/system event,
    /// otherwise `nil`.
    public var systemView: SystemMessageView? {
        if case .system(let s) = self { return s }
        return nil
    }

    /// Convenience for sorting / time display — the timestamp of any variant.
    public var sentAt: Date {
        switch self {
        case .message(let m): return m.sentAt
        case .deleted(let d): return d.sentAt
        case .system(let s): return s.sentAt
        }
    }

    /// The sender of any variant. For system messages this is the actor that
    /// performed the action (e.g. the user who added a member).
    public var sender: MessageSender {
        switch self {
        case .message(let m): return m.sender
        case .deleted(let d): return d.sender
        case .system(let s): return s.sender
        }
    }
}

// MARK: - chat.bsky.convo.defs#messageView (in-thread union)

/// Discriminated union covering everything the `chat.bsky.convo.getMessages`
/// endpoint may return in the `messages` array, plus everything the firehose
/// streams into a thread. RN parity: `state/messages/convo/agent.ts` walks the
/// equivalent union of `MessageView | DeletedMessageView | SystemMessageView`
/// and the chat list itemizer renders a different cell for each variant.
public enum ConvoMessage: Codable, Sendable, Identifiable {
    case message(MessageView)
    case deleted(DeletedMessageView)
    case system(SystemMessageView)

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
        case "chat.bsky.convo.defs#systemMessageView":
            self = .system(try single.decode(SystemMessageView.self))
        case "chat.bsky.convo.defs#messageView", nil, "":
            self = .message(try single.decode(MessageView.self))
        default:
            // Unknown variant — best-effort fallback in this order so any
            // message-ish payload still renders a bubble before falling back
            // to a system row, then a tombstone.
            if let msg = try? single.decode(MessageView.self) {
                self = .message(msg)
            } else if let sys = try? single.decode(SystemMessageView.self) {
                self = .system(sys)
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
        case .system(let s): try single.encode(s)
        }
    }

    /// Stable identifier — each variant carries its own `id` field.
    public var id: String {
        switch self {
        case .message(let m): return m.id
        case .deleted(let d): return d.id
        case .system(let s): return s.id
        }
    }

    /// Server-issued sort timestamp. All three variants carry one.
    public var sentAt: Date {
        switch self {
        case .message(let m): return m.sentAt
        case .deleted(let d): return d.sentAt
        case .system(let s): return s.sentAt
        }
    }

    /// The actor associated with the row. For system events this is the user
    /// who performed the action (e.g. the member who renamed the group).
    public var sender: MessageSender {
        switch self {
        case .message(let m): return m.sender
        case .deleted(let d): return d.sender
        case .system(let s): return s.sender
        }
    }

    /// Returns the underlying `MessageView` only when this is a real message —
    /// callers that want to act on a bubble (delete, react, copy) should drill
    /// in via this accessor and no-op on the other variants.
    public var messageView: MessageView? {
        if case .message(let m) = self { return m }
        return nil
    }

    /// Returns the system-event payload, or `nil` for message / deleted rows.
    public var systemView: SystemMessageView? {
        if case .system(let s) = self { return s }
        return nil
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

// MARK: - chat.bsky.convo.defs#systemMessageView

/// A non-authored system event interleaved with messages in a conversation
/// (`chat.bsky.convo.defs#systemMessageView`). Examples include "alice added
/// bob to the group", "alice left the group", "chat title changed", and
/// invite-link / lock changes. Renders as a centered italic line in the
/// thread, not as a bubble.
///
/// `sender` is the actor who performed the action (RN reads it via the
/// existing `MessageSender` shape, even when the action is purely
/// administrative). `data` is the discriminated union describing what
/// happened — see `SystemMessageData` for the shipped variants.
public struct SystemMessageView: Codable, Sendable {
    public let id: String
    public let rev: String
    public let sender: MessageSender
    public let sentAt: Date
    public let data: SystemMessageData

    public init(
        id: String,
        rev: String,
        sender: MessageSender,
        sentAt: Date,
        data: SystemMessageData
    ) {
        self.id = id
        self.rev = rev
        self.sender = sender
        self.sentAt = sentAt
        self.data = data
    }
}

/// The actor referenced by a system message (e.g. the user who was added,
/// removed, or otherwise mentioned). Mirrors
/// `chat.bsky.convo.defs#systemMessageReferredUser` — the server only
/// guarantees the DID; the UI resolves it to a profile via `relatedProfiles`
/// or the convo member list.
public struct SystemMessageReferredUser: Codable, Sendable, Hashable {
    public let did: DID

    public init(did: DID) {
        self.did = did
    }
}

/// The discriminated union under `SystemMessageView.data`. Each variant
/// corresponds to a `chat.bsky.convo.defs#systemMessageData…` lexicon. RN
/// dispatches on these in `getSystemMessageInfo.ts` to render the appropriate
/// localized line — Swift mirrors the same set so the parity is 1:1. Any
/// future variants the server adds fall through to `.unknown` so the UI can
/// render a generic placeholder instead of dropping the row.
public enum SystemMessageData: Codable, Sendable {
    case addMember(member: SystemMessageReferredUser)
    case removeMember(member: SystemMessageReferredUser)
    case memberJoin(member: SystemMessageReferredUser)
    case memberLeave(member: SystemMessageReferredUser)
    case lockConvo
    case unlockConvo
    case lockConvoPermanently
    case editGroup(newName: String?)
    case createJoinLink
    case editJoinLink
    case enableJoinLink
    case disableJoinLink
    case unknown(type: String?)

    private enum DiscriminatorKeys: String, CodingKey {
        case type = "$type"
    }

    private enum AddRemovePayloadKeys: String, CodingKey {
        case member
    }

    private enum EditGroupPayloadKeys: String, CodingKey {
        case newName
    }

    public init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let type = try typeContainer.decodeIfPresent(String.self, forKey: .type)
        switch type {
        case "chat.bsky.convo.defs#systemMessageDataAddMember":
            let c = try decoder.container(keyedBy: AddRemovePayloadKeys.self)
            self = .addMember(member: try c.decode(SystemMessageReferredUser.self, forKey: .member))
        case "chat.bsky.convo.defs#systemMessageDataRemoveMember":
            let c = try decoder.container(keyedBy: AddRemovePayloadKeys.self)
            self = .removeMember(member: try c.decode(SystemMessageReferredUser.self, forKey: .member))
        case "chat.bsky.convo.defs#systemMessageDataMemberJoin":
            let c = try decoder.container(keyedBy: AddRemovePayloadKeys.self)
            self = .memberJoin(member: try c.decode(SystemMessageReferredUser.self, forKey: .member))
        case "chat.bsky.convo.defs#systemMessageDataMemberLeave":
            let c = try decoder.container(keyedBy: AddRemovePayloadKeys.self)
            self = .memberLeave(member: try c.decode(SystemMessageReferredUser.self, forKey: .member))
        case "chat.bsky.convo.defs#systemMessageDataLockConvo":
            self = .lockConvo
        case "chat.bsky.convo.defs#systemMessageDataUnlockConvo":
            self = .unlockConvo
        case "chat.bsky.convo.defs#systemMessageDataLockConvoPermanently":
            self = .lockConvoPermanently
        case "chat.bsky.convo.defs#systemMessageDataEditGroup":
            let c = try decoder.container(keyedBy: EditGroupPayloadKeys.self)
            let name = try c.decodeIfPresent(String.self, forKey: .newName)
            self = .editGroup(newName: name)
        case "chat.bsky.convo.defs#systemMessageDataCreateJoinLink":
            self = .createJoinLink
        case "chat.bsky.convo.defs#systemMessageDataEditJoinLink":
            self = .editJoinLink
        case "chat.bsky.convo.defs#systemMessageDataEnableJoinLink":
            self = .enableJoinLink
        case "chat.bsky.convo.defs#systemMessageDataDisableJoinLink":
            self = .disableJoinLink
        default:
            self = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var typeContainer = encoder.container(keyedBy: DiscriminatorKeys.self)
        switch self {
        case .addMember(let member):
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataAddMember", forKey: .type)
            var c = encoder.container(keyedBy: AddRemovePayloadKeys.self)
            try c.encode(member, forKey: .member)
        case .removeMember(let member):
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataRemoveMember", forKey: .type)
            var c = encoder.container(keyedBy: AddRemovePayloadKeys.self)
            try c.encode(member, forKey: .member)
        case .memberJoin(let member):
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataMemberJoin", forKey: .type)
            var c = encoder.container(keyedBy: AddRemovePayloadKeys.self)
            try c.encode(member, forKey: .member)
        case .memberLeave(let member):
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataMemberLeave", forKey: .type)
            var c = encoder.container(keyedBy: AddRemovePayloadKeys.self)
            try c.encode(member, forKey: .member)
        case .lockConvo:
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataLockConvo", forKey: .type)
        case .unlockConvo:
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataUnlockConvo", forKey: .type)
        case .lockConvoPermanently:
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataLockConvoPermanently", forKey: .type)
        case .editGroup(let newName):
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataEditGroup", forKey: .type)
            var c = encoder.container(keyedBy: EditGroupPayloadKeys.self)
            try c.encodeIfPresent(newName, forKey: .newName)
        case .createJoinLink:
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataCreateJoinLink", forKey: .type)
        case .editJoinLink:
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataEditJoinLink", forKey: .type)
        case .enableJoinLink:
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataEnableJoinLink", forKey: .type)
        case .disableJoinLink:
            try typeContainer.encode("chat.bsky.convo.defs#systemMessageDataDisableJoinLink", forKey: .type)
        case .unknown(let type):
            if let type {
                try typeContainer.encode(type, forKey: .type)
            }
        }
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

/// Response shape for `chat.bsky.convo.getMessages`. The server interleaves
/// regular `messageView`, `deletedMessageView` tombstones, and
/// `systemMessageView` events into a single `messages` array — `ConvoMessage`
/// preserves the discrimination so the thread UI can render the right cell
/// for each row. RN reference: `state/messages/convo/agent.ts` walks the same
/// union when building the `ConvoItem` list.
public struct GetMessagesResponse: Codable, Sendable {
    public let messages: [ConvoMessage]
    public let cursor: Cursor?

    public init(messages: [ConvoMessage], cursor: Cursor?) {
        self.messages = messages
        self.cursor = cursor
    }
}

// MARK: - chat.bsky.convo.sendMessage

public struct MessageInput: Encodable, Sendable {
    public let text: String
    public let embed: Embed?
    /// Byte-range annotations (mentions, links, hashtags) over `text`.
    /// Mirrors `chat.bsky.convo.defs#messageInput.facets` in the lexicon.
    /// Encoded only when non-empty so a plain-text DM still serializes
    /// without an empty `facets` array.
    public let facets: [RichTextFacet]?

    public init(text: String, embed: Embed? = nil, facets: [RichTextFacet]? = nil) {
        self.text = text
        self.embed = embed
        self.facets = (facets?.isEmpty == true) ? nil : facets
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
