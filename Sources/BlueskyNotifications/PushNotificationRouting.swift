import Foundation
import BlueskyCore
import BlueskyKit

// MARK: - PushNotificationRoute

/// Where a tapped push notification should take the user.
///
/// Mirrors the RN reference's `notificationToURL(payload)` in
/// `src/lib/hooks/useNotificationHandler.ts`, which converts the APNs payload
/// into an in-app URL:
///
/// - `like` / `repost` / `like-via-repost` / `repost-via-repost` → the post in
///   `subject` (when it is an `app.bsky.feed.post`), else `/notifications`
/// - `reply` / `quote` / `mention` / `subscribed-post` → the post in `uri`
///   (when it is an `app.bsky.feed.post`), else `/notifications`
/// - `follow` / `starterpack-joined` → the profile of the `uri` record's repo
/// - `chat-message` / `chat-reaction` / `chat-added-to-group` → the
///   conversation in `convoId`
/// - `chat-removed-from-group` / `chat-join-request-rejected` → the messages
///   inbox
/// - `verified` / `unverified` (and any unrecognized reason) → `/notifications`
///
/// The enum is `nonisolated` so the `UNUserNotificationCenterDelegate`
/// callbacks — which are not bound to the main actor by contract — can build
/// and forward routes without hopping executors.
public nonisolated enum PushNotificationRoute: Equatable, Sendable {
    /// Open the thread for the given post AT-URI (pushed on the Home stack,
    /// matching RN's `navigate('HomeTab', …)` behavior).
    case postThread(ATURI)
    /// Open the profile of the given actor.
    case profile(did: DID)
    /// Open a specific DM conversation.
    case conversation(convoID: String)
    /// Open the Messages inbox (no specific conversation).
    case messagesInbox
    /// Land on the Notifications tab (RN's `/notifications` fallback).
    case notificationsTab
}

// MARK: - PushNotificationPayload

/// The custom keys Bluesky's notification gateway attaches to an APNs push.
///
/// Field names follow RN's `NotificationPayload` type in
/// `useNotificationHandler.ts`: `reason`, `uri`, `subject`, `recipientDid` for
/// content notifications, and `convoId` for chat notifications. iOS payloads
/// surface these at the top level of the notification `userInfo`.
public nonisolated struct PushNotificationPayload: Equatable, Sendable {
    public let reason: String
    /// AT-URI of the notification record itself (reply/quote/mention/follow…).
    public let uri: String?
    /// AT-URI of the subject the notification is about (like/repost…).
    public let subject: String?
    /// Chat conversation identifier (`chat-*` reasons).
    public let convoID: String?
    /// DID of the account that received the notification.
    public let recipientDID: String?

    public init(
        reason: String,
        uri: String? = nil,
        subject: String? = nil,
        convoID: String? = nil,
        recipientDID: String? = nil
    ) {
        self.reason = reason
        self.uri = uri
        self.subject = subject
        self.convoID = convoID
        self.recipientDID = recipientDID
    }

    /// Parses the `userInfo` dictionary of a delivered `UNNotification`.
    /// Returns `nil` when the payload carries no `reason` — i.e. it is not a
    /// Bluesky notification payload we know how to route.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let reason = userInfo["reason"] as? String, !reason.isEmpty else { return nil }
        self.reason = reason
        self.uri = userInfo["uri"] as? String
        self.subject = userInfo["subject"] as? String
        self.convoID = userInfo["convoId"] as? String
        self.recipientDID = userInfo["recipientDid"] as? String
    }

    /// The in-app destination for this payload, per the RN routing rules
    /// (see `PushNotificationRoute`). Unrecognized reasons and payloads with
    /// missing/foreign subjects degrade to the Notifications tab rather than
    /// dropping the tap on the floor.
    public var route: PushNotificationRoute {
        switch reason {
        case "like", "repost", "like-via-repost", "repost-via-repost":
            return Self.postRoute(from: subject)
        case "reply", "quote", "mention", "subscribed-post":
            return Self.postRoute(from: uri)
        case "follow", "starterpack-joined":
            // RN: `/profile/${AtUri(payload.uri).host}` — the repo of the
            // follow / starterpack record is the actor to show.
            guard let uri, let repo = ATURI(rawValue: uri).repo, !repo.isEmpty else {
                return .notificationsTab
            }
            return .profile(did: DID(rawValue: repo))
        case "chat-message", "chat-reaction", "chat-added-to-group":
            guard let convoID, !convoID.isEmpty else { return .messagesInbox }
            return .conversation(convoID: convoID)
        case "chat-removed-from-group", "chat-join-request-rejected":
            return .messagesInbox
        default:
            // "verified", "unverified", and any reason added upstream after
            // this port: RN sends these to `/notifications`.
            return .notificationsTab
        }
    }

    /// RN parity: only `app.bsky.feed.post` subjects open a thread; anything
    /// else (e.g. a feed generator) falls back to the notifications list.
    private static func postRoute(from rawURI: String?) -> PushNotificationRoute {
        guard let rawURI, !rawURI.isEmpty else { return .notificationsTab }
        let uri = ATURI(rawValue: rawURI)
        guard uri.collection == "app.bsky.feed.post" else { return .notificationsTab }
        return .postThread(uri)
    }
}

// MARK: - PushRegistrationService

/// Registers the device's APNs token with Bluesky's notification gateway via
/// `app.bsky.notification.registerPush`, mirroring RN's `registerPushToken`
/// in `src/lib/notifications/notifications.ts` (serviceDid = the public
/// AppView DID, platform = "ios", appId = the bundle identifier).
public nonisolated enum PushRegistrationService {
    /// `PUBLIC_APPVIEW_DID` in the RN reference — the service that fans
    /// notifications out to APNs.
    public static let appViewServiceDID = DID(rawValue: "did:web:api.bsky.app")

    /// APNs hands the token over as raw bytes; the gateway expects the
    /// conventional lowercase-hex rendering.
    public static func tokenHexString(_ deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    /// Sends `app.bsky.notification.registerPush` for the given device token.
    ///
    /// - Parameters:
    ///   - deviceToken: Raw APNs token from
    ///     `didRegisterForRemoteNotificationsWithDeviceToken`.
    ///   - appID: The app's bundle identifier (RN sends its own `appId`).
    ///   - platform: `"ios"` (default) or `"android"`.
    ///   - network: Authenticated XRPC client (the PDS proxies the call to
    ///     the AppView's notification service).
    public static func register(
        deviceToken: Data,
        appID: String,
        platform: String = "ios",
        network: any NetworkClient
    ) async throws {
        let body = RegisterPushRequest(
            serviceDid: appViewServiceDID,
            token: tokenHexString(deviceToken),
            platform: platform,
            appId: appID
        )
        let _: EmptyResponse = try await network.post(
            lexicon: "app.bsky.notification.registerPush",
            body: body
        )
    }
}
