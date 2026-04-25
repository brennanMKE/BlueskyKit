import Foundation
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
    nonisolated func get<Response: Decodable & Sendable>(
        lexicon: String,
        params: [String: String]
    ) async throws -> Response

    /// Performs an XRPC procedure (POST) for the given lexicon NSID.
    ///
    /// - Parameters:
    ///   - lexicon: The lexicon NSID, e.g. `"com.atproto.server.createSession"`.
    ///   - body: JSON-encodable request body.
    nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String,
        body: Body
    ) async throws -> Response

    /// Uploads raw bytes (e.g. an image) to an XRPC blob endpoint.
    ///
    /// - Parameters:
    ///   - lexicon: Typically `"com.atproto.repo.uploadBlob"`.
    ///   - data: Raw binary data to upload.
    ///   - mimeType: MIME type such as `"image/jpeg"` or `"image/png"`.
    nonisolated func upload<Response: Decodable & Sendable>(
        lexicon: String,
        data: Data,
        mimeType: String
    ) async throws -> Response
}
