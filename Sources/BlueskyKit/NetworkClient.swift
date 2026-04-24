import BlueskyCore

/// Contract for making XRPC requests to the AT Protocol PDS.
///
/// `BlueskyNetworking` provides the production URLSession implementation.
/// Tests inject a mock that returns fixture data.
public protocol NetworkClient: AnyObject, Sendable {
    /// Performs an XRPC query (GET) for the given lexicon NSID.
    ///
    /// - Parameters:
    ///   - lexicon: The lexicon NSID, e.g. `"app.bsky.feed.getTimeline"`.
    ///   - params: URL query parameters (strings only; the client encodes them).
    func get<Response: Decodable & Sendable>(
        lexicon: String,
        params: [String: String]
    ) async throws -> Response

    /// Performs an XRPC procedure (POST) for the given lexicon NSID.
    ///
    /// - Parameters:
    ///   - lexicon: The lexicon NSID, e.g. `"com.atproto.server.createSession"`.
    ///   - body: JSON-encodable request body.
    func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String,
        body: Body
    ) async throws -> Response
}
