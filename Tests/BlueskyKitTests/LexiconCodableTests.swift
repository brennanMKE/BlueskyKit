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

// MARK: - Post

@Suite("Post lexicon")
struct PostCodableTests {
    @Test("SelfLabels encodes with $type discriminator")
    func encodeSelfLabels() throws {
        let labels = SelfLabels(values: [SelfLabelValue(val: "porn")])
        let data = try JSONEncoder().encode(labels)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["$type"] as? String == "com.atproto.label.defs#selfLabels")
        let values = json["values"] as! [[String: Any]]
        #expect(values.count == 1)
        #expect(values.first?["val"] as? String == "porn")
    }

    @Test("PostRecord with labels encodes selfLabels payload")
    func encodePostRecordWithLabels() throws {
        let record = PostRecord(
            text: "hi",
            labels: SelfLabels(values: [SelfLabelValue(val: "graphic-media")])
        )
        let data = try iso8601Encoder.encode(record)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let labels = json["labels"] as! [String: Any]
        #expect(labels["$type"] as? String == "com.atproto.label.defs#selfLabels")
        let values = labels["values"] as! [[String: Any]]
        #expect(values.first?["val"] as? String == "graphic-media")
    }

    @Test("PostRecord without labels omits the field")
    func encodePostRecordWithoutLabels() throws {
        let record = PostRecord(text: "hi")
        let data = try iso8601Encoder.encode(record)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["labels"] == nil)
    }

    @Test("PostRecord with labels round-trips")
    func roundTripPostRecordLabels() throws {
        let json = """
        {
            "text": "hello",
            "createdAt": "2026-05-06T00:00:00Z",
            "labels": {
                "$type": "com.atproto.label.defs#selfLabels",
                "values": [{"val": "sexual"}]
            }
        }
        """.data(using: .utf8)!
        let record = try iso8601.decode(PostRecord.self, from: json)
        #expect(record.labels?.values.map(\.val) == ["sexual"])
    }
}

// MARK: - Threadgate / postgate

@Suite("Threadgate lexicon")
struct ThreadgateCodableTests {
    @Test("Allow=nil omits the field — everyone can reply")
    func encodeEveryone() throws {
        let r = ThreadgateRecord(
            post: ATURI(rawValue: "at://did:plc:abc/app.bsky.feed.post/rkey1"),
            allow: nil
        )
        let data = try iso8601Encoder.encode(r)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["$type"] as? String == "app.bsky.feed.threadgate")
        #expect(json["allow"] == nil)
    }

    @Test("Allow=[] keeps the field as empty array — nobody can reply")
    func encodeNobody() throws {
        let r = ThreadgateRecord(
            post: ATURI(rawValue: "at://did:plc:abc/app.bsky.feed.post/rkey1"),
            allow: []
        )
        let data = try iso8601Encoder.encode(r)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let allow = json["allow"] as? [Any]
        #expect(allow != nil)
        #expect(allow?.count == 0)
    }

    @Test("Granular allow round-trips with $type discriminators")
    func roundTripGranular() throws {
        let r = ThreadgateRecord(
            post: ATURI(rawValue: "at://did:plc:abc/app.bsky.feed.post/rkey1"),
            allow: [
                .mention,
                .following,
                .follower,
                .list(ATURI(rawValue: "at://did:plc:abc/app.bsky.graph.list/list1")),
            ]
        )
        let data = try iso8601Encoder.encode(r)
        let decoded = try iso8601.decode(ThreadgateRecord.self, from: data)
        #expect(decoded.allow?.count == 4)
        #expect(decoded.allow?[0] == .mention)
        #expect(decoded.allow?[1] == .following)
        #expect(decoded.allow?[2] == .follower)
        if case .list(let uri) = decoded.allow?[3] {
            #expect(uri.rawValue == "at://did:plc:abc/app.bsky.graph.list/list1")
        } else {
            Issue.record("expected list rule")
        }
    }

    @Test("Decoding distinguishes omitted vs empty allow")
    func decodeOmittedVsEmpty() throws {
        let omitted = """
        {
            "post": "at://did:plc:abc/app.bsky.feed.post/rkey1",
            "createdAt": "2026-05-06T00:00:00Z"
        }
        """.data(using: .utf8)!
        let empty = """
        {
            "post": "at://did:plc:abc/app.bsky.feed.post/rkey1",
            "createdAt": "2026-05-06T00:00:00Z",
            "allow": []
        }
        """.data(using: .utf8)!
        let r1 = try iso8601.decode(ThreadgateRecord.self, from: omitted)
        let r2 = try iso8601.decode(ThreadgateRecord.self, from: empty)
        #expect(r1.allow == nil)
        #expect(r2.allow != nil)
        #expect(r2.allow?.count == 0)
    }
}

@Suite("Postgate lexicon")
struct PostgateCodableTests {
    @Test("Disable rule encodes with $type discriminator")
    func encodeDisable() throws {
        let r = PostgateRecord(
            post: ATURI(rawValue: "at://did:plc:abc/app.bsky.feed.post/rkey1"),
            embeddingRules: [.disable]
        )
        let data = try iso8601Encoder.encode(r)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["$type"] as? String == "app.bsky.feed.postgate")
        let rules = json["embeddingRules"] as! [[String: Any]]
        #expect(rules.first?["$type"] as? String == "app.bsky.feed.postgate#disableRule")
    }

    @Test("PostgateRecord round-trips")
    func roundTripPostgate() throws {
        let r = PostgateRecord(
            post: ATURI(rawValue: "at://did:plc:abc/app.bsky.feed.post/rkey1"),
            embeddingRules: [.disable]
        )
        let data = try iso8601Encoder.encode(r)
        let decoded = try iso8601.decode(PostgateRecord.self, from: data)
        #expect(decoded.embeddingRules == [.disable])
        #expect(decoded.post.rawValue == "at://did:plc:abc/app.bsky.feed.post/rkey1")
    }
}

// MARK: - Bookmark

@Suite("Bookmark lexicon")
struct BookmarkCodableTests {
    /// Wire shape captured from `app.bsky.bookmark.getBookmarks` and confirmed
    /// against `Bluesky-ReactNative/src/state/queries/bookmarks/useBookmarksQuery.ts`.
    /// The bookmarked post URI lives under `subject.uri` — never at the
    /// top level. (Issue #0152.)
    private static let sampleJSON = """
    {
        "bookmarks": [
            {
                "subject": {
                    "uri": "at://did:plc:abc/app.bsky.feed.post/rkey1",
                    "cid": "bafy123"
                },
                "createdAt": "2026-05-07T12:00:00Z"
            }
        ],
        "cursor": "next-cursor"
    }
    """.data(using: .utf8)!

    @Test("GetBookmarksResponse decodes nested subject.uri (issue #0152)")
    func decodeGetBookmarksResponse() throws {
        let response = try iso8601.decode(GetBookmarksResponse.self, from: Self.sampleJSON)
        #expect(response.bookmarks.count == 1)
        let b = response.bookmarks[0]
        #expect(b.subject.uri.rawValue == "at://did:plc:abc/app.bsky.feed.post/rkey1")
        #expect(b.subject.cid == "bafy123")
        // Convenience accessors mirror the nested ref.
        #expect(b.uri == b.subject.uri)
        #expect(b.cid == b.subject.cid)
        #expect(b.item == nil)
        #expect(response.cursor == "next-cursor")
    }

    @Test("Top-level uri/cid (the broken pre-#0152 shape) is skipped, not fatal")
    func skipsLegacyFlatShape() throws {
        // #0154 made GetBookmarksResponse tolerant: a malformed bookmark
        // envelope is dropped instead of aborting the whole page (mirroring
        // RN's per-item leniency). The legacy flat shape therefore decodes to
        // an empty page rather than throwing.
        let badJSON = """
        {
            "bookmarks": [
                {"uri": "at://did:plc:abc/app.bsky.feed.post/rkey1", "cid": "bafy123"}
            ]
        }
        """.data(using: .utf8)!
        let response = try iso8601.decode(GetBookmarksResponse.self, from: badJSON)
        #expect(response.bookmarks.isEmpty)
    }

    @Test("BookmarkView round-trips through Codable")
    func roundTripBookmarkView() throws {
        let original = try iso8601.decode(GetBookmarksResponse.self, from: Self.sampleJSON)
        let bookmark = original.bookmarks[0]
        let data = try iso8601Encoder.encode(bookmark)
        let decoded = try iso8601.decode(BookmarkView.self, from: data)
        #expect(decoded.subject.uri == bookmark.subject.uri)
        #expect(decoded.subject.cid == bookmark.subject.cid)
        #expect(decoded.createdAt == bookmark.createdAt)
    }

    @Test("DeleteBookmarkRequest encodes the post URI as `uri`")
    func encodeDeleteBookmarkRequest() throws {
        let req = DeleteBookmarkRequest(postURI: ATURI(rawValue: "at://did:plc:abc/app.bsky.feed.post/rkey1"))
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["uri"] as? String == "at://did:plc:abc/app.bsky.feed.post/rkey1")
    }

    // MARK: - issue #0154 — bookmarkView.item is a discriminated union

    /// A canonical `app.bsky.feed.defs#postView` JSON envelope used to populate
    /// `bookmarkView.item` in mixed-variant fixtures below.
    private static let postViewJSON = """
    {
        "$type": "app.bsky.feed.defs#postView",
        "uri": "at://did:plc:author/app.bsky.feed.post/rkey-post",
        "cid": "bafyPost",
        "author": {
            "did": "did:plc:author",
            "handle": "alice.bsky.social",
            "displayName": "Alice",
            "avatar": null,
            "labels": []
        },
        "record": {
            "text": "hello bookmarks",
            "createdAt": "2026-05-07T11:30:00Z"
        },
        "replyCount": 0,
        "repostCount": 0,
        "likeCount": 0,
        "quoteCount": 0,
        "indexedAt": "2026-05-07T11:35:00Z",
        "labels": []
    }
    """

    @Test("bookmarkView.item decodes the postView variant")
    func decodeItemPostView() throws {
        let json = """
        {
            "bookmarks": [
                {
                    "subject": {"uri": "at://did:plc:author/app.bsky.feed.post/rkey-post", "cid": "bafyPost"},
                    "createdAt": "2026-05-07T12:00:00Z",
                    "item": \(Self.postViewJSON)
                }
            ]
        }
        """.data(using: .utf8)!
        let response = try iso8601.decode(GetBookmarksResponse.self, from: json)
        #expect(response.bookmarks.count == 1)
        guard case .post(let post) = response.bookmarks[0].item else {
            Issue.record("expected .post variant")
            return
        }
        #expect(post.uri.rawValue == "at://did:plc:author/app.bsky.feed.post/rkey-post")
        #expect(post.cid == "bafyPost")
    }

    @Test("bookmarkView.item decodes the notFoundPost variant (no `cid`)")
    func decodeItemNotFound() throws {
        let json = """
        {
            "bookmarks": [
                {
                    "subject": {"uri": "at://did:plc:gone/app.bsky.feed.post/rkey-x", "cid": "bafyX"},
                    "createdAt": "2026-05-07T12:00:00Z",
                    "item": {
                        "$type": "app.bsky.feed.defs#notFoundPost",
                        "uri": "at://did:plc:gone/app.bsky.feed.post/rkey-x",
                        "notFound": true
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        let response = try iso8601.decode(GetBookmarksResponse.self, from: json)
        guard case .notFound(let nf) = response.bookmarks[0].item else {
            Issue.record("expected .notFound variant")
            return
        }
        #expect(nf.uri.rawValue == "at://did:plc:gone/app.bsky.feed.post/rkey-x")
        #expect(nf.notFound == true)
    }

    @Test("bookmarkView.item decodes the blockedPost variant (no `cid`)")
    func decodeItemBlocked() throws {
        let json = """
        {
            "bookmarks": [
                {
                    "subject": {"uri": "at://did:plc:blocked/app.bsky.feed.post/rkey-y", "cid": "bafyY"},
                    "createdAt": "2026-05-07T12:00:00Z",
                    "item": {
                        "$type": "app.bsky.feed.defs#blockedPost",
                        "uri": "at://did:plc:blocked/app.bsky.feed.post/rkey-y",
                        "blocked": true,
                        "author": {
                            "did": "did:plc:blocked",
                            "handle": "blocked.bsky.social",
                            "displayName": null,
                            "avatar": null,
                            "labels": []
                        }
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        let response = try iso8601.decode(GetBookmarksResponse.self, from: json)
        guard case .blocked(let bl) = response.bookmarks[0].item else {
            Issue.record("expected .blocked variant")
            return
        }
        #expect(bl.uri.rawValue == "at://did:plc:blocked/app.bsky.feed.post/rkey-y")
        #expect(bl.blocked == true)
        #expect(bl.author?.handle.rawValue == "blocked.bsky.social")
    }

    @Test("bookmarkView.item absorbs unknown $type as .unknown")
    func decodeItemUnknown() throws {
        let json = """
        {
            "bookmarks": [
                {
                    "subject": {"uri": "at://did:plc:future/app.bsky.feed.post/rkey-f", "cid": "bafyF"},
                    "createdAt": "2026-05-07T12:00:00Z",
                    "item": {
                        "$type": "app.bsky.feed.defs#someFutureVariant",
                        "uri": "at://did:plc:future/app.bsky.feed.post/rkey-f"
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        let response = try iso8601.decode(GetBookmarksResponse.self, from: json)
        guard case .unknown(let t) = response.bookmarks[0].item else {
            Issue.record("expected .unknown variant")
            return
        }
        #expect(t == "app.bsky.feed.defs#someFutureVariant")
    }

    @Test("Mixed page (post + notFound + blocked + unknown) decodes end-to-end (issue #0154)")
    func decodeMixedPage() throws {
        let json = """
        {
            "bookmarks": [
                {
                    "subject": {"uri": "at://did:plc:author/app.bsky.feed.post/rkey-post", "cid": "bafyPost"},
                    "createdAt": "2026-05-07T12:00:00Z",
                    "item": \(Self.postViewJSON)
                },
                {
                    "subject": {"uri": "at://did:plc:gone/app.bsky.feed.post/rkey-x", "cid": "bafyX"},
                    "createdAt": "2026-05-07T12:01:00Z",
                    "item": {
                        "$type": "app.bsky.feed.defs#notFoundPost",
                        "uri": "at://did:plc:gone/app.bsky.feed.post/rkey-x",
                        "notFound": true
                    }
                },
                {
                    "subject": {"uri": "at://did:plc:blocked/app.bsky.feed.post/rkey-y", "cid": "bafyY"},
                    "createdAt": "2026-05-07T12:02:00Z",
                    "item": {
                        "$type": "app.bsky.feed.defs#blockedPost",
                        "uri": "at://did:plc:blocked/app.bsky.feed.post/rkey-y",
                        "blocked": true,
                        "author": {
                            "did": "did:plc:blocked",
                            "handle": "blocked.bsky.social",
                            "displayName": null,
                            "avatar": null,
                            "labels": []
                        }
                    }
                },
                {
                    "subject": {"uri": "at://did:plc:future/app.bsky.feed.post/rkey-f", "cid": "bafyF"},
                    "createdAt": "2026-05-07T12:03:00Z",
                    "item": {"$type": "app.bsky.feed.defs#someFutureVariant"}
                }
            ],
            "cursor": "next"
        }
        """.data(using: .utf8)!
        let response = try iso8601.decode(GetBookmarksResponse.self, from: json)
        #expect(response.bookmarks.count == 4)
        if case .post = response.bookmarks[0].item {} else { Issue.record("[0] expected .post") }
        if case .notFound = response.bookmarks[1].item {} else { Issue.record("[1] expected .notFound") }
        if case .blocked = response.bookmarks[2].item {} else { Issue.record("[2] expected .blocked") }
        if case .unknown = response.bookmarks[3].item {} else { Issue.record("[3] expected .unknown") }
        #expect(response.cursor == "next")
    }

    @Test("Per-item defensive decode skips a malformed bookmark envelope (issue #0154)")
    func decodeSkipsMalformedItem() throws {
        // Second entry is missing `subject` entirely — its decode must fail
        // and be skipped, but the first and third entries should survive.
        let json = """
        {
            "bookmarks": [
                {
                    "subject": {"uri": "at://did:plc:author/app.bsky.feed.post/rkey-1", "cid": "bafy1"},
                    "createdAt": "2026-05-07T12:00:00Z"
                },
                {
                    "createdAt": "2026-05-07T12:01:00Z"
                },
                {
                    "subject": {"uri": "at://did:plc:author/app.bsky.feed.post/rkey-3", "cid": "bafy3"},
                    "createdAt": "2026-05-07T12:02:00Z"
                }
            ]
        }
        """.data(using: .utf8)!
        let response = try iso8601.decode(GetBookmarksResponse.self, from: json)
        #expect(response.bookmarks.count == 2)
        #expect(response.bookmarks[0].subject.cid == "bafy1")
        #expect(response.bookmarks[1].subject.cid == "bafy3")
    }
}

// MARK: - BlobRef (#0197)

@Suite("BlobRef lexicon (#0197)")
struct BlobRefCodableTests {
    /// Drill into a nested JSON dictionary via key path components.
    private func dig(_ json: [String: Any], _ path: [Any]) -> Any? {
        var current: Any? = json
        for component in path {
            if let key = component as? String {
                current = (current as? [String: Any])?[key]
            } else if let index = component as? Int {
                current = (current as? [Any])?[index]
            }
        }
        return current
    }

    @Test("BlobRef encodes the $type: blob discriminator")
    func encodeEmitsTypeDiscriminator() throws {
        let blob = BlobRef(cid: "bafkreigcid", mimeType: "image/png", size: 1234)
        let data = try iso8601Encoder.encode(blob)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["$type"] as? String == "blob")
        #expect(dig(json, ["ref", "$link"]) as? String == "bafkreigcid")
        #expect(json["mimeType"] as? String == "image/png")
        #expect(json["size"] as? Int == 1234)
        #expect(json["cid"] == nil)
    }

    @Test("PostRecord with image embed carries $type: blob at embed.images[0].image")
    func encodeImagePost() throws {
        let blob = BlobRef(cid: "bafkreiimage", mimeType: "image/jpeg", size: 9876)
        let record = PostRecord(
            text: "image post",
            embed: .images([EmbedImage(image: blob, alt: "alt text", aspectRatio: AspectRatio(width: 4, height: 3))]),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let data = try iso8601Encoder.encode(record)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dig(json, ["embed", "$type"]) as? String == "app.bsky.embed.images")
        #expect(dig(json, ["embed", "images", 0, "image", "$type"]) as? String == "blob")
        #expect(dig(json, ["embed", "images", 0, "image", "ref", "$link"]) as? String == "bafkreiimage")
        #expect(dig(json, ["embed", "images", 0, "image", "mimeType"]) as? String == "image/jpeg")
        #expect(dig(json, ["embed", "images", 0, "image", "size"]) as? Int == 9876)
    }

    @Test("PostRecord with external embed carries $type: blob at embed.external.thumb")
    func encodeExternalThumbPost() throws {
        let thumb = BlobRef(cid: "bafkreithumb", mimeType: "image/jpeg", size: 555)
        let record = PostRecord(
            text: "link card post",
            embed: .external(EmbedExternal(uri: "https://example.com", title: "Example", description: "desc", thumb: thumb)),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let data = try iso8601Encoder.encode(record)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dig(json, ["embed", "$type"]) as? String == "app.bsky.embed.external")
        #expect(dig(json, ["embed", "external", "thumb", "$type"]) as? String == "blob")
        #expect(dig(json, ["embed", "external", "thumb", "ref", "$link"]) as? String == "bafkreithumb")
    }

    @Test("PostRecord with video embed carries $type: blob at embed.video")
    func encodeVideoPost() throws {
        let blob = BlobRef(cid: "bafkreivideo", mimeType: "video/mp4", size: 100_000)
        let record = PostRecord(
            text: "video post",
            embed: .video(EmbedVideo(video: blob, captions: nil, alt: nil, aspectRatio: nil)),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let data = try iso8601Encoder.encode(record)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dig(json, ["embed", "$type"]) as? String == "app.bsky.embed.video")
        #expect(dig(json, ["embed", "video", "$type"]) as? String == "blob")
        #expect(dig(json, ["embed", "video", "ref", "$link"]) as? String == "bafkreivideo")
    }

    @Test("BlobRef round-trips through encode/decode")
    func roundTripBlobRef() throws {
        let blob = BlobRef(cid: "bafkreiroundtrip", mimeType: "image/png", size: 42)
        let decoded = try roundTrip(blob)
        #expect(decoded == blob)
    }

    @Test("BlobRef decodes the server shape carrying $type")
    func decodeServerShape() throws {
        let json = """
        { "$type": "blob", "ref": { "$link": "bafkreiserver" }, "mimeType": "image/png", "size": 77 }
        """.data(using: .utf8)!
        let blob = try iso8601.decode(BlobRef.self, from: json)
        #expect(blob == BlobRef(cid: "bafkreiserver", mimeType: "image/png", size: 77))
    }

    @Test("BlobRef decodes without $type (lenient reads)")
    func decodeWithoutType() throws {
        let json = """
        { "ref": { "$link": "bafkreinotype" }, "mimeType": "image/png", "size": 7 }
        """.data(using: .utf8)!
        let blob = try iso8601.decode(BlobRef.self, from: json)
        #expect(blob == BlobRef(cid: "bafkreinotype", mimeType: "image/png", size: 7))
    }

    @Test("BlobRef decodes the deprecated legacy {cid, mimeType} shape")
    func decodeLegacyShape() throws {
        let json = """
        { "cid": "bafylegacy", "mimeType": "image/jpeg" }
        """.data(using: .utf8)!
        let blob = try iso8601.decode(BlobRef.self, from: json)
        #expect(blob.cid == "bafylegacy")
        #expect(blob.mimeType == "image/jpeg")
        #expect(blob.size == 0)
    }
}

// MARK: - DID document (session responses)

@Suite("DIDDocument PDS endpoint")
struct DIDDocumentTests {
    @Test("GetSessionResponse decodes didDoc and extracts the PDS endpoint")
    func decodeGetSessionDidDoc() throws {
        let json = """
        {
            "did": "did:plc:abc",
            "handle": "alice.bsky.social",
            "active": true,
            "didDoc": {
                "@context": ["https://www.w3.org/ns/did/v1"],
                "id": "did:plc:abc",
                "service": [
                    {
                        "id": "#atproto_pds",
                        "type": "AtprotoPersonalDataServer",
                        "serviceEndpoint": "https://jellybaby.us-east.host.bsky.network"
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        let session = try iso8601.decode(GetSessionResponse.self, from: json)
        #expect(session.didDoc?.pdsEndpoint == URL(string: "https://jellybaby.us-east.host.bsky.network"))
    }

    @Test("pdsEndpoint matches a fully qualified service id")
    func fullyQualifiedServiceID() {
        let doc = DIDDocument(service: [
            .init(
                id: "did:plc:abc#atproto_pds",
                type: "AtprotoPersonalDataServer",
                serviceEndpoint: "https://pds.example.com"
            )
        ])
        #expect(doc.pdsEndpoint == URL(string: "https://pds.example.com"))
    }

    @Test("pdsEndpoint ignores non-PDS services and rejects invalid URLs")
    func rejectsNonPDSAndInvalid() {
        let labelerOnly = DIDDocument(service: [
            .init(id: "#atproto_labeler", type: "AtprotoLabeler", serviceEndpoint: "https://labeler.example.com")
        ])
        #expect(labelerOnly.pdsEndpoint == nil)

        let badURL = DIDDocument(service: [
            .init(id: "#atproto_pds", type: "AtprotoPersonalDataServer", serviceEndpoint: "not a url")
        ])
        #expect(badURL.pdsEndpoint == nil)

        #expect(DIDDocument(service: nil).pdsEndpoint == nil)
    }

    @Test("malformed service entries decode leniently instead of failing the response")
    func lenientServiceDecoding() throws {
        let json = """
        {
            "did": "did:plc:abc",
            "handle": "alice.bsky.social",
            "didDoc": {
                "service": [
                    { "id": 42, "type": ["x"], "serviceEndpoint": { "uri": "https://weird.example" } },
                    {
                        "id": "#atproto_pds",
                        "type": "AtprotoPersonalDataServer",
                        "serviceEndpoint": "https://pds.example.com"
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        let session = try iso8601.decode(GetSessionResponse.self, from: json)
        #expect(session.didDoc?.pdsEndpoint == URL(string: "https://pds.example.com"))
    }

    @Test("session responses without a didDoc still decode")
    func missingDidDoc() throws {
        let json = """
        { "did": "did:plc:abc", "handle": "alice.bsky.social" }
        """.data(using: .utf8)!
        let session = try iso8601.decode(GetSessionResponse.self, from: json)
        #expect(session.didDoc == nil)
    }
}
