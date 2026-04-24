import Foundation

// MARK: - app.bsky.notification.listNotifications

/// A single notification entry returned by `app.bsky.notification.listNotifications`.
public struct NotificationView: Codable, Sendable {
    public let uri: ATURI
    public let cid: CID
    public let author: ProfileBasic
    /// Notification kind: `like`, `repost`, `follow`, `mention`, `reply`, `quote`,
    /// `starterpack-joined`, `verified`, `unverified`, etc.
    public let reason: String
    /// AT-URI of the subject that triggered the notification (e.g. the liked post).
    public let reasonSubject: ATURI?
    public let isRead: Bool
    public let indexedAt: Date
    public let labels: [Label]

    public init(
        uri: ATURI,
        cid: CID,
        author: ProfileBasic,
        reason: String,
        reasonSubject: ATURI?,
        isRead: Bool,
        indexedAt: Date,
        labels: [Label] = []
    ) {
        self.uri = uri
        self.cid = cid
        self.author = author
        self.reason = reason
        self.reasonSubject = reasonSubject
        self.isRead = isRead
        self.indexedAt = indexedAt
        self.labels = labels
    }
}

public struct ListNotificationsResponse: Codable, Sendable {
    public let notifications: [NotificationView]
    public let cursor: Cursor?
    public let seenAt: Date?
    public let priority: Bool?

    public init(
        notifications: [NotificationView],
        cursor: Cursor?,
        seenAt: Date?,
        priority: Bool?
    ) {
        self.notifications = notifications
        self.cursor = cursor
        self.seenAt = seenAt
        self.priority = priority
    }
}

// MARK: - app.bsky.notification.updateSeen

public struct UpdateSeenRequest: Encodable, Sendable {
    public let seenAt: Date

    public init(seenAt: Date = .now) {
        self.seenAt = seenAt
    }
}

// MARK: - app.bsky.notification.getUnreadCount

public struct GetUnreadCountResponse: Decodable, Sendable {
    public let count: Int
}

// MARK: - app.bsky.notification.registerPush

public struct RegisterPushRequest: Encodable, Sendable {
    public let serviceDid: DID
    public let token: String
    /// `"ios"` or `"android"`.
    public let platform: String
    public let appId: String

    public init(serviceDid: DID, token: String, platform: String, appId: String) {
        self.serviceDid = serviceDid
        self.token = token
        self.platform = platform
        self.appId = appId
    }
}
