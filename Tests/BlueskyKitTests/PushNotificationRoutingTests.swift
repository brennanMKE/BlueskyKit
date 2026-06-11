import Testing
import Foundation
import Synchronization
import BlueskyCore
@testable import BlueskyNotifications

/// Verifies the APNs payload → in-app route mapping matches the RN reference
/// (`notificationToURL` in `src/lib/hooks/useNotificationHandler.ts`). #0030.
@Suite("Push notification routing")
struct PushNotificationRoutingTests {

    private let postURI = "at://did:plc:author/app.bsky.feed.post/3kabc"
    private let likeRecordURI = "at://did:plc:liker/app.bsky.feed.like/3kdef"
    private let followRecordURI = "at://did:plc:follower/app.bsky.graph.follow/3kghi"
    private let feedGenURI = "at://did:plc:author/app.bsky.feed.generator/cool-feed"

    // MARK: - subject-routed reasons (like / repost families)

    @Test("like routes to the thread of the subject post", arguments: [
        "like", "repost", "like-via-repost", "repost-via-repost",
    ])
    func likeFamilyRoutesToSubjectThread(reason: String) {
        let payload = PushNotificationPayload(reason: reason, uri: "at://did:plc:liker/app.bsky.feed.like/3kdef", subject: postURI)
        #expect(payload.route == .postThread(ATURI(rawValue: postURI)))
    }

    @Test("like with a non-post subject falls back to notifications")
    func likeOfFeedGeneratorFallsBack() {
        let payload = PushNotificationPayload(reason: "like", uri: likeRecordURI, subject: feedGenURI)
        #expect(payload.route == .notificationsTab)
    }

    @Test("like with a missing subject falls back to notifications")
    func likeWithoutSubjectFallsBack() {
        let payload = PushNotificationPayload(reason: "like", uri: likeRecordURI)
        #expect(payload.route == .notificationsTab)
    }

    // MARK: - uri-routed reasons (reply / quote / mention / subscribed-post)

    @Test("reply routes to the thread of the uri post", arguments: [
        "reply", "quote", "mention", "subscribed-post",
    ])
    func replyFamilyRoutesToURIThread(reason: String) {
        let payload = PushNotificationPayload(reason: reason, uri: postURI)
        #expect(payload.route == .postThread(ATURI(rawValue: postURI)))
    }

    @Test("reply uses uri even when a subject is also present")
    func replyPrefersURIOverSubject() {
        let replyURI = "at://did:plc:replier/app.bsky.feed.post/3kreply"
        let payload = PushNotificationPayload(reason: "reply", uri: replyURI, subject: postURI)
        #expect(payload.route == .postThread(ATURI(rawValue: replyURI)))
    }

    @Test("reply with a missing uri falls back to notifications")
    func replyWithoutURIFallsBack() {
        let payload = PushNotificationPayload(reason: "reply", subject: postURI)
        #expect(payload.route == .notificationsTab)
    }

    // MARK: - profile-routed reasons (follow / starterpack-joined)

    @Test("follow routes to the follower's profile", arguments: [
        "follow", "starterpack-joined",
    ])
    func followRoutesToProfile(reason: String) {
        let payload = PushNotificationPayload(reason: reason, uri: followRecordURI)
        #expect(payload.route == .profile(did: DID(rawValue: "did:plc:follower")))
    }

    @Test("follow with a missing uri falls back to notifications")
    func followWithoutURIFallsBack() {
        let payload = PushNotificationPayload(reason: "follow")
        #expect(payload.route == .notificationsTab)
    }

    // MARK: - chat reasons

    @Test("chat reasons with a convoId open the conversation", arguments: [
        "chat-message", "chat-reaction", "chat-added-to-group",
    ])
    func chatRoutesToConversation(reason: String) {
        let payload = PushNotificationPayload(reason: reason, convoID: "convo123")
        #expect(payload.route == .conversation(convoID: "convo123"))
    }

    @Test("chat-message without a convoId opens the inbox")
    func chatWithoutConvoIDOpensInbox() {
        let payload = PushNotificationPayload(reason: "chat-message")
        #expect(payload.route == .messagesInbox)
    }

    @Test("group removal / rejection open the inbox", arguments: [
        "chat-removed-from-group", "chat-join-request-rejected",
    ])
    func groupRemovalOpensInbox(reason: String) {
        let payload = PushNotificationPayload(reason: reason, convoID: "convo123")
        #expect(payload.route == .messagesInbox)
    }

    // MARK: - notifications-tab reasons

    @Test("verified / unverified land on the notifications tab", arguments: [
        "verified", "unverified",
    ])
    func verificationLandsOnNotifications(reason: String) {
        let payload = PushNotificationPayload(reason: reason, uri: postURI)
        #expect(payload.route == .notificationsTab)
    }

    @Test("an unknown reason lands on the notifications tab")
    func unknownReasonLandsOnNotifications() {
        let payload = PushNotificationPayload(reason: "some-future-reason", uri: postURI)
        #expect(payload.route == .notificationsTab)
    }

    // MARK: - userInfo parsing

    @Test("userInfo init parses all RN payload fields")
    func userInfoParsesAllFields() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Alice liked your post"]],
            "reason": "like",
            "uri": likeRecordURI,
            "subject": postURI,
            "convoId": "convo123",
            "recipientDid": "did:plc:recipient",
        ]
        let payload = try #require(PushNotificationPayload(userInfo: userInfo))
        #expect(payload.reason == "like")
        #expect(payload.uri == likeRecordURI)
        #expect(payload.subject == postURI)
        #expect(payload.convoID == "convo123")
        #expect(payload.recipientDID == "did:plc:recipient")
        #expect(payload.route == .postThread(ATURI(rawValue: postURI)))
    }

    @Test("userInfo without a reason is rejected")
    func userInfoWithoutReasonIsRejected() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": "hi"],
            "subject": postURI,
        ]
        #expect(PushNotificationPayload(userInfo: userInfo) == nil)
    }

    @Test("userInfo with an empty reason is rejected")
    func userInfoWithEmptyReasonIsRejected() {
        #expect(PushNotificationPayload(userInfo: ["reason": ""]) == nil)
    }

    // MARK: - registration helpers

    @Test("APNs device token renders as lowercase hex")
    func tokenHexString() {
        let token = Data([0x00, 0x1f, 0xab, 0xff])
        #expect(PushRegistrationService.tokenHexString(token) == "001fabff")
    }

    @Test("registerPush posts the RN-shaped body to the right lexicon")
    func registerPushPostsExpectedBody() async throws {
        let network = CapturingNetworkClient()
        try await PushRegistrationService.register(
            deviceToken: Data([0xde, 0xad, 0xbe, 0xef]),
            appID: "co.sstools.Bluesky.beta",
            network: network
        )
        let captured = network.captured.withLock { $0 }
        #expect(captured?.lexicon == "app.bsky.notification.registerPush")
        let body = try #require(captured?.body as? RegisterPushRequest)
        #expect(body.serviceDid == DID(rawValue: "did:web:api.bsky.app"))
        #expect(body.token == "deadbeef")
        #expect(body.platform == "ios")
        #expect(body.appId == "co.sstools.Bluesky.beta")
    }
}

// MARK: - Test double

import BlueskyKit

/// Minimal `NetworkClient` that records the last POST and returns `{}`.
private final class CapturingNetworkClient: NetworkClient, Sendable {
    let captured = Mutex<(lexicon: String, body: any Sendable)?>(nil)

    nonisolated func get<Response: Decodable & Sendable>(
        lexicon: String, params: [String: String]
    ) async throws -> Response {
        throw ATError.unknown("unexpected GET in test")
    }

    nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String, body: Body
    ) async throws -> Response {
        captured.withLock { $0 = (lexicon, body) }
        let data = Data("{}".utf8)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    nonisolated func upload<Response: Decodable & Sendable>(
        lexicon: String, data: Data, mimeType: String
    ) async throws -> Response {
        throw ATError.unknown("unexpected upload in test")
    }
}
