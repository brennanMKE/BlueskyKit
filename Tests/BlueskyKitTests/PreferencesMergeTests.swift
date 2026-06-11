import Testing
import Foundation
import Synchronization
import BlueskyKit
@testable import BlueskyCore

// MARK: - Fixture

/// A realistic `app.bsky.actor.getPreferences` payload carrying every kind of
/// entry the merge must preserve: modeled prefs, multiple entries of the same
/// `$type` (content labels, per-feed feedViewPrefs), and an *unmodeled* pref
/// (`bskyAppStatePref`) with nested objects, arrays, ints, doubles, and null.
private let prefsFixture = Data("""
{
  "preferences": [
    {"$type": "app.bsky.actor.defs#adultContentPref", "enabled": true},
    {"$type": "app.bsky.actor.defs#contentLabelPref", "label": "porn", "visibility": "hide"},
    {"$type": "app.bsky.actor.defs#contentLabelPref", "label": "spam", "labelerDid": "did:plc:labeler1", "visibility": "warn"},
    {"$type": "app.bsky.actor.defs#savedFeedsPrefV2", "items": [
      {"id": "aaa", "type": "timeline", "value": "following", "pinned": true}
    ]},
    {"$type": "app.bsky.actor.defs#feedViewPref", "feed": "home", "hideReplies": true, "hideRepliesByUnfollowed": true, "hideRepliesByLikeCount": 2, "hideReposts": false, "hideQuotePosts": false},
    {"$type": "app.bsky.actor.defs#feedViewPref", "feed": "at://did:plc:x/app.bsky.feed.generator/cool", "hideReplies": false, "hideRepliesByUnfollowed": false, "hideRepliesByLikeCount": 0, "hideReposts": true, "hideQuotePosts": true},
    {"$type": "app.bsky.actor.defs#labelersPref", "labelers": [{"did": "did:plc:labeler1"}]},
    {"$type": "app.bsky.actor.defs#bskyAppStatePref", "queuedNudges": ["nudge-one"], "nuxs": [{"id": "NeueTypography", "completed": false, "data": "{\\"x\\":1}", "score": 1.5}], "activeProgressGuide": {"guide": "like-10-and-follow-7", "numLikes": 3, "numFollows": null}},
    {"$type": "app.bsky.actor.defs#personalDetailsPref", "birthDate": "1990-06-15T00:00:00.000Z"}
  ]
}
""".utf8)

// MARK: - Helpers

private struct PrefsEnvelope: Decodable {
    let preferences: [JSONValue]
}

private func decodeEntries(_ data: Data) throws -> [JSONValue] {
    try JSONDecoder().decode(PrefsEnvelope.self, from: data).preferences
}

private func encodedEntries(of request: PutPreferencesRequest) throws -> [JSONValue] {
    try decodeEntries(JSONEncoder().encode(request))
}

private func entries(_ type: String, in all: [JSONValue]) -> [JSONValue] {
    all.filter { $0.typeDiscriminator == type }
}

private func fixtureResponse() throws -> GetPreferencesResponse {
    try JSONDecoder().decode(GetPreferencesResponse.self, from: prefsFixture)
}

// MARK: - Merge tests

@Suite("Preferences merge (#0201)")
struct PreferencesMergeTests {

    @Test("rawPreferences decodes every entry, including unmodeled $types")
    func rawPreferencesDecodesEveryEntry() throws {
        let response = try fixtureResponse()
        #expect(response.rawPreferences.count == 9)
        let unknown = entries("app.bsky.actor.defs#bskyAppStatePref", in: response.rawPreferences)
        #expect(unknown.count == 1)
        // Spot-check nested values survived the decode.
        let object = try #require(unknown.first?.objectValue)
        #expect(Set(object.keys) == ["$type", "queuedNudges", "nuxs", "activeProgressGuide"])
        #expect(object["queuedNudges"] == .array([.string("nudge-one")]))
        #expect(object["activeProgressGuide"]?.objectValue?["numLikes"] == .integer(3))
        #expect(object["activeProgressGuide"]?.objectValue?["numFollows"] == .null)
        #expect(object["nuxs"]?.arrayValue?.first?.objectValue?["score"] == .number(1.5))
    }

    @Test("Upsert replaces only the targeted $type entries")
    func upsertReplacesOnlyTargetedType() throws {
        let current = try fixtureResponse().rawPreferences
        let newFeed = SavedFeed(id: "bbb", type: "feed", value: "at://did:plc:y/app.bsky.feed.generator/new", pinned: true)
        let request = PutPreferencesRequest(merging: current, applying: .savedFeeds([newFeed]))
        let out = try encodedEntries(of: request)

        // Same entry count: exactly one savedFeedsPrefV2 was swapped out.
        #expect(out.count == current.count)

        // The targeted entry was replaced.
        let savedFeeds = entries(ActorPreferenceType.savedFeedsV2, in: out)
        #expect(savedFeeds.count == 1)
        let items = try #require(savedFeeds.first?.objectValue?["items"]?.arrayValue)
        #expect(items.count == 1)
        #expect(items.first?.objectValue?["id"] == .string("bbb"))

        // Every non-targeted entry rode through unchanged.
        for entry in current where entry.typeDiscriminator != ActorPreferenceType.savedFeedsV2 {
            #expect(out.contains(entry))
        }
    }

    @Test("Unknown preference types round-trip with key set and values intact")
    func unknownPreferenceRoundTripsVerbatim() throws {
        let current = try fixtureResponse().rawPreferences
        let request = PutPreferencesRequest(merging: current, applying: .postLanguages(["es"]))
        let out = try encodedEntries(of: request)

        let unknownBefore = entries("app.bsky.actor.defs#bskyAppStatePref", in: current)
        let unknownAfter = entries("app.bsky.actor.defs#bskyAppStatePref", in: out)
        #expect(unknownBefore == unknownAfter)
        #expect(unknownAfter.count == 1)
        // postLanguagesPref was absent from the fixture, so the merge appends it.
        #expect(out.count == current.count + 1)
        let langs = entries(ActorPreferenceType.postLanguages, in: out)
        #expect(langs.first?.objectValue?["languages"] == .array([.string("es")]))
    }

    @Test("feedView mutation replaces only the matching feed's entry")
    func feedViewReplacementKeepsOtherFeeds() throws {
        let current = try fixtureResponse().rawPreferences
        let pref = FeedViewPref(
            feed: "home",
            hideReplies: false,
            hideRepliesByUnfollowed: true,
            hideRepliesByLikeCount: 2,
            hideReposts: true,
            hideQuotePosts: false
        )
        let request = PutPreferencesRequest(merging: current, applying: .feedView(pref))
        let out = try encodedEntries(of: request)

        let feedViews = entries(ActorPreferenceType.feedView, in: out)
        #expect(feedViews.count == 2)
        let home = try #require(feedViews.first { $0.objectValue?["feed"] == .string("home") })
        #expect(home.objectValue?["hideReposts"] == .bool(true))
        #expect(home.objectValue?["hideReplies"] == .bool(false))
        // The non-home feedViewPref is byte-identical to the input.
        let other = try #require(
            entries(ActorPreferenceType.feedView, in: current)
                .first { $0.objectValue?["feed"] != .string("home") }
        )
        #expect(feedViews.contains(other))
    }

    @Test("Adult content + labels mutation keeps every other preference")
    func adultContentMutationKeepsEverythingElse() throws {
        let current = try fixtureResponse().rawPreferences
        let request = PutPreferencesRequest(
            merging: current,
            applying: .adultContentAndLabels(
                enabled: false,
                contentLabels: [ContentLabelPref(label: "nudity", visibility: "show")]
            )
        )
        let out = try encodedEntries(of: request)

        #expect(entries(ActorPreferenceType.adultContent, in: out).first?.objectValue?["enabled"] == .bool(false))
        let labels = entries(ActorPreferenceType.contentLabel, in: out)
        #expect(labels.count == 1)
        #expect(labels.first?.objectValue?["label"] == .string("nudity"))
        // Untouched prefs survive.
        for type in [
            ActorPreferenceType.savedFeedsV2,
            ActorPreferenceType.labelers,
            ActorPreferenceType.personalDetails,
            "app.bsky.actor.defs#bskyAppStatePref",
        ] {
            let before = entries(type, in: current)
            #expect(entries(type, in: out) == before, "expected \(type) to ride through unchanged")
        }
        #expect(entries(ActorPreferenceType.feedView, in: out).count == 2)
    }
}

// MARK: - Writer test double

/// `NetworkClient` that serves the fixture for `getPreferences` and records
/// every POSTed body.
private final class PrefsCapturingClient: NetworkClient, Sendable {
    private let posted = Mutex<[(lexicon: String, body: Data)]>([])

    var postedBodies: [(lexicon: String, body: Data)] {
        posted.withLock { $0 }
    }

    nonisolated func get<Response: Decodable & Sendable>(
        lexicon: String, params: [String: String]
    ) async throws -> Response {
        guard lexicon == "app.bsky.actor.getPreferences" else {
            throw ATError.unknown("unexpected GET \(lexicon) in test")
        }
        return try JSONDecoder().decode(Response.self, from: prefsFixture)
    }

    nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String, body: Body
    ) async throws -> Response {
        let data = try JSONEncoder().encode(body)
        posted.withLock { $0.append((lexicon, data)) }
        return try JSONDecoder().decode(Response.self, from: Data("{}".utf8))
    }

    nonisolated func upload<Response: Decodable & Sendable>(
        lexicon: String, data: Data, mimeType: String
    ) async throws -> Response {
        throw ATError.unknown("unexpected upload in test")
    }
}

// MARK: - Writer tests

@Suite("PreferencesWriter (#0201)")
struct PreferencesWriterTests {

    /// Asserts `body` is a full-array put: the mutated `$type` aside, every
    /// fixture entry must be present and unchanged.
    private func expectFullArrayBody(
        _ body: (lexicon: String, body: Data)?, replacing replacedTypes: Set<String>
    ) throws -> [JSONValue] {
        let posted = try #require(body)
        #expect(posted.lexicon == "app.bsky.actor.putPreferences")
        let out = try decodeEntries(posted.body)
        let current = try decodeEntries(prefsFixture)
        for entry in current where !replacedTypes.contains(entry.typeDiscriminator ?? "") {
            #expect(out.contains(entry), "expected untouched pref \(entry.typeDiscriminator ?? "?") in put body")
        }
        return out
    }

    @Test("Saved feed pin writes the full preferences array")
    func savedFeedPinWritesFullArray() async throws {
        let client = PrefsCapturingClient()
        var feeds = try fixtureResponse().savedFeeds
        feeds.append(SavedFeed(id: "pin1", type: "feed", value: "at://did:plc:z/app.bsky.feed.generator/discover", pinned: true))
        try await PreferencesWriter().update(network: client, .savedFeeds(feeds))

        let out = try expectFullArrayBody(
            client.postedBodies.first, replacing: [ActorPreferenceType.savedFeedsV2]
        )
        let items = try #require(
            entries(ActorPreferenceType.savedFeedsV2, in: out).first?.objectValue?["items"]?.arrayValue
        )
        #expect(items.count == 2)
    }

    @Test("Label visibility write keeps saved feeds and unknown prefs")
    func labelVisibilityWritesFullArray() async throws {
        let client = PrefsCapturingClient()
        try await PreferencesWriter().update(
            network: client,
            .adultContentAndLabels(
                enabled: true,
                contentLabels: [
                    ContentLabelPref(label: "porn", visibility: "warn"),
                    ContentLabelPref(label: "spam", visibility: "warn", labelerDid: DID(rawValue: "did:plc:labeler1")),
                ]
            )
        )
        let out = try expectFullArrayBody(
            client.postedBodies.first,
            replacing: [ActorPreferenceType.adultContent, ActorPreferenceType.contentLabel]
        )
        #expect(entries(ActorPreferenceType.contentLabel, in: out).count == 2)
    }

    @Test("Adult content toggle keeps every other preference")
    func adultContentToggleWritesFullArray() async throws {
        let client = PrefsCapturingClient()
        try await PreferencesWriter().update(
            network: client,
            .adultContentAndLabels(enabled: false, contentLabels: [
                ContentLabelPref(label: "porn", visibility: "hide"),
                ContentLabelPref(label: "spam", visibility: "warn", labelerDid: DID(rawValue: "did:plc:labeler1")),
            ])
        )
        let out = try expectFullArrayBody(
            client.postedBodies.first,
            replacing: [ActorPreferenceType.adultContent, ActorPreferenceType.contentLabel]
        )
        #expect(entries(ActorPreferenceType.adultContent, in: out).first?.objectValue?["enabled"] == .bool(false))
    }

    @Test("Closure mutation sees fresh server state and can skip the write")
    func closureMutationCanSkip() async throws {
        let client = PrefsCapturingClient()
        try await PreferencesWriter().update(network: client) { prefs in
            // Fresh state is the decoded fixture.
            #expect(prefs.savedFeeds.count == 1)
            return nil // RN's `cb → false`: skip the put entirely.
        }
        #expect(client.postedBodies.isEmpty)
    }
}
