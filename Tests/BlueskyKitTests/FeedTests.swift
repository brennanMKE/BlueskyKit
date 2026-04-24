import Testing
import Foundation
@testable import BlueskyCore

@Suite("Feed types")
struct FeedTests {

    // MARK: - FeedResponse

    @Test("FeedResponse decodes feed and cursor")
    func feedResponseDecodes() throws {
        let json = """
        {
            "feed": [],
            "cursor": "abc123"
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(FeedResponse.self, from: data)
        #expect(response.feed.isEmpty)
        #expect(response.cursor == "abc123")
    }

    @Test("FeedResponse decodes with nil cursor")
    func feedResponseNilCursor() throws {
        let json = #"{"feed": []}"#
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(FeedResponse.self, from: data)
        #expect(response.cursor == nil)
    }

    // MARK: - CreateRecordRequest / Response

    @Test("CreateRecordRequest encodes repo and collection")
    func createRecordRequestEncodes() throws {
        let record = LikeRecord(
            subject: PostRef(
                uri: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
                cid: "cid123"
            )
        )
        let req = CreateRecordRequest(
            repo: "did:plc:alice",
            collection: "app.bsky.feed.like",
            record: record
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["repo"] as? String == "did:plc:alice")
        #expect(obj["collection"] as? String == "app.bsky.feed.like")
        let r = obj["record"] as! [String: Any]
        #expect(r["$type"] as? String == "app.bsky.feed.like")
    }

    @Test("LikeRecord encodes with $type")
    func likeRecordEncodes() throws {
        let record = LikeRecord(
            subject: PostRef(
                uri: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
                cid: "cid123"
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["$type"] as? String == "app.bsky.feed.like")
        let subject = obj["subject"] as! [String: Any]
        #expect(subject["uri"] as? String == "at://did:plc:alice/app.bsky.feed.post/abc")
    }

    @Test("RepostRecord encodes with $type")
    func repostRecordEncodes() throws {
        let record = RepostRecord(
            subject: PostRef(
                uri: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
                cid: "cid123"
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["$type"] as? String == "app.bsky.feed.repost")
    }

    @Test("DeleteRecordRequest encodes repo, collection, rkey")
    func deleteRecordRequestEncodes() throws {
        let req = DeleteRecordRequest(
            repo: "did:plc:alice",
            collection: "app.bsky.feed.like",
            rkey: "3kz12abc"
        )
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["repo"] as? String == "did:plc:alice")
        #expect(obj["collection"] as? String == "app.bsky.feed.like")
        #expect(obj["rkey"] as? String == "3kz12abc")
    }

    // MARK: - ATURI rkey extraction

    @Test("ATURI.rkey extracts last path component")
    func atURIRkey() {
        let uri = ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.like/3kz12abc")
        #expect(uri.rkey == "3kz12abc")
    }

    @Test("ATURI.rkey is nil for short paths")
    func atURIRkeyNilForShort() {
        let uri = ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.like")
        #expect(uri.rkey == nil)
    }

    // MARK: - ThreadViewPost

    @Test("ThreadViewPost decodes notFound")
    func threadViewPostNotFound() throws {
        let json = """
        {
            "$type": "app.bsky.feed.defs#notFoundPost",
            "uri": "at://did:plc:alice/app.bsky.feed.post/xyz",
            "notFound": true
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let post = try decoder.decode(ThreadViewPost.self, from: data)
        guard case .notFound(let uri) = post else {
            Issue.record("Expected .notFound")
            return
        }
        #expect(uri.rawValue == "at://did:plc:alice/app.bsky.feed.post/xyz")
    }

    @Test("ThreadViewPost decodes blocked")
    func threadViewPostBlocked() throws {
        let json = """
        {
            "$type": "app.bsky.feed.defs#blockedPost",
            "uri": "at://did:plc:bob/app.bsky.feed.post/abc",
            "blocked": true
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let post = try decoder.decode(ThreadViewPost.self, from: data)
        guard case .blocked(let uri) = post else {
            Issue.record("Expected .blocked")
            return
        }
        #expect(uri.rawValue == "at://did:plc:bob/app.bsky.feed.post/abc")
    }

    @Test("EmptyResponse decodes from empty object")
    func emptyResponseDecodes() throws {
        let data = "{}".data(using: .utf8)!
        let response = try JSONDecoder().decode(EmptyResponse.self, from: data)
        _ = response
    }
}
