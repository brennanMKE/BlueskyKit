import Testing
import Foundation
@testable import BlueskyCore

// MARK: - Shared test helpers

private let iso8601: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

private let iso8601Encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
}()

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try iso8601Encoder.encode(value)
    return try iso8601.decode(T.self, from: data)
}

// MARK: - Notification

@Suite("Notification lexicon")
struct NotificationCodableTests {
    private static let sampleJSON = """
    {
        "uri": "at://did:plc:abc/app.bsky.feed.post/rkey1",
        "cid": "bafy123",
        "author": {
            "did": "did:plc:abc",
            "handle": "alice.bsky.social",
            "labels": []
        },
        "reason": "like",
        "isRead": false,
        "indexedAt": "2026-04-24T12:00:00Z",
        "labels": []
    }
    """.data(using: .utf8)!

    @Test("NotificationView decodes from JSON")
    func decodeNotificationView() throws {
        let view = try iso8601.decode(NotificationView.self, from: Self.sampleJSON)
        #expect(view.reason == "like")
        #expect(view.isRead == false)
        #expect(view.author.did.rawValue == "did:plc:abc")
    }

    @Test("ListNotificationsResponse decodes from JSON")
    func decodeListNotificationsResponse() throws {
        let json = """
        {
            "notifications": [],
            "cursor": "next-page",
            "priority": false
        }
        """.data(using: .utf8)!
        let resp = try iso8601.decode(ListNotificationsResponse.self, from: json)
        #expect(resp.cursor == "next-page")
        #expect(resp.notifications.isEmpty)
    }

    @Test("UpdateSeenRequest encodes seenAt")
    func encodeUpdateSeen() throws {
        let req = UpdateSeenRequest(seenAt: Date(timeIntervalSince1970: 0))
        let data = try iso8601Encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["seenAt"] as? String == "1970-01-01T00:00:00Z")
    }
}

// MARK: - Graph

@Suite("Graph lexicon")
struct GraphCodableTests {
    private static let profileViewJSON = """
    {
        "did": "did:plc:xyz",
        "handle": "bob.bsky.social",
        "labels": []
    }
    """.data(using: .utf8)!

    @Test("GetFollowersResponse decodes correctly")
    func decodeGetFollowersResponse() throws {
        let json = """
        {
            "subject": { "did": "did:plc:me", "handle": "me.bsky.social", "labels": [] },
            "followers": [],
            "cursor": null
        }
        """.data(using: .utf8)!
        let resp = try iso8601.decode(GetFollowersResponse.self, from: json)
        #expect(resp.subject.did.rawValue == "did:plc:me")
        #expect(resp.followers.isEmpty)
        #expect(resp.cursor == nil)
    }

    @Test("GetMutesResponse decodes correctly")
    func decodeGetMutesResponse() throws {
        let json = """
        { "mutes": [], "cursor": "abc" }
        """.data(using: .utf8)!
        let resp = try iso8601.decode(GetMutesResponse.self, from: json)
        #expect(resp.cursor == "abc")
    }

    @Test("ListView decodes correctly")
    func decodeListView() throws {
        let json = """
        {
            "uri": "at://did:plc:x/app.bsky.graph.list/rkey",
            "cid": "bafyabc",
            "creator": { "did": "did:plc:x", "handle": "x.bsky.social", "labels": [] },
            "name": "My list",
            "purpose": "app.bsky.graph.defs#modlist",
            "labels": []
        }
        """.data(using: .utf8)!
        let list = try iso8601.decode(ListView.self, from: json)
        #expect(list.name == "My list")
        #expect(list.purpose == "app.bsky.graph.defs#modlist")
    }
}

// MARK: - Repo

@Suite("Repo lexicon")
struct RepoCodableTests {
    @Test("WriteCreate encodes with $type")
    func encodeWriteCreate() throws {
        struct SimpleRecord: Encodable, Sendable { let text: String }
        let op = WriteCreate(collection: "app.bsky.feed.post", rkey: "abc", value: SimpleRecord(text: "hi"))
        let data = try JSONEncoder().encode(op)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["$type"] as? String == "com.atproto.repo.applyWrites#create")
        #expect(json["collection"] as? String == "app.bsky.feed.post")
        #expect(json["rkey"] as? String == "abc")
    }

    @Test("WriteDelete encodes with $type")
    func encodeWriteDelete() throws {
        let op = WriteDelete(collection: "app.bsky.feed.like", rkey: "xyz")
        let data = try JSONEncoder().encode(op)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["$type"] as? String == "com.atproto.repo.applyWrites#delete")
        #expect(json["rkey"] as? String == "xyz")
    }

    @Test("ApplyWritesResponse decodes commit")
    func decodeApplyWritesResponse() throws {
        let json = """
        { "commit": { "cid": "bafyabc", "rev": "1" } }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(ApplyWritesResponse.self, from: json)
        #expect(resp.commit?.rev == "1")
    }
}

// MARK: - Chat

@Suite("Chat lexicon")
struct ChatCodableTests {
    @Test("MessageView decodes correctly")
    func decodeMessageView() throws {
        let json = """
        {
            "id": "msg1",
            "rev": "rev1",
            "text": "Hello!",
            "sender": { "did": "did:plc:sender" },
            "sentAt": "2026-04-24T10:00:00Z"
        }
        """.data(using: .utf8)!
        let msg = try iso8601.decode(MessageView.self, from: json)
        #expect(msg.text == "Hello!")
        #expect(msg.sender.did.rawValue == "did:plc:sender")
    }

    @Test("MessageInput encodes text")
    func encodeMessageInput() throws {
        let input = MessageInput(text: "hey")
        let data = try JSONEncoder().encode(input)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["text"] as? String == "hey")
    }

    @Test("ListConvosResponse decodes with cursor")
    func decodeListConvosResponse() throws {
        let json = """
        { "convos": [], "cursor": "tok" }
        """.data(using: .utf8)!
        let resp = try iso8601.decode(ListConvosResponse.self, from: json)
        #expect(resp.cursor == "tok")
    }
}

// MARK: - Moderation

@Suite("Moderation lexicon")
struct ModerationCodableTests {
    @Test("ReportSubjectRepo encodes with $type")
    func encodeReportSubjectRepo() throws {
        let subj = ReportSubjectRepo(did: DID(rawValue: "did:plc:abc"))
        let data = try JSONEncoder().encode(subj)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["$type"] as? String == "com.atproto.admin.defs#repoRef")
        #expect(json["did"] as? String == "did:plc:abc")
    }

    @Test("ReportSubjectRecord encodes with $type")
    func encodeReportSubjectRecord() throws {
        let subj = ReportSubjectRecord(
            uri: ATURI(rawValue: "at://did:plc:x/app.bsky.feed.post/rkey"),
            cid: "bafyabc"
        )
        let data = try JSONEncoder().encode(subj)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["$type"] as? String == "com.atproto.repo.strongRef")
    }

    @Test("CreateReportResponse round-trips")
    func decodeCreateReportResponse() throws {
        let json = """
        {
            "id": 42,
            "reasonType": "com.atproto.moderation.defs#reasonSpam",
            "reportedBy": "did:plc:reporter",
            "createdAt": "2026-04-24T00:00:00Z"
        }
        """.data(using: .utf8)!
        let resp = try iso8601.decode(CreateReportResponse.self, from: json)
        #expect(resp.id == 42)
        #expect(resp.reportedBy.rawValue == "did:plc:reporter")
    }
}
