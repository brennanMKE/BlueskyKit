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

    /// Performs an XRPC procedure (POST) routed through the labeler / service
    /// identified by `proxyDID`. Sends an `atproto-proxy` header in the form
    /// `<did>#atproto_labeler` so the user's PDS forwards the request to the
    /// chosen labeler. Used by the Report dialog (#0135) to direct reports at
    /// a specific moderation service.
    ///
    /// Conformers that don't care about per-call proxy routing get a default
    /// implementation that ignores `proxyDID`. The production
    /// `ATProtoClient` overrides this to actually attach the header.
    nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String,
        body: Body,
        proxyDID: DID?
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

extension NetworkClient {
    /// Default implementation: ignore `proxyDID` and fall through to the
    /// non-proxied `post`. Production clients (`ATProtoClient`) override this
    /// to attach the `atproto-proxy` header. Preview / test mocks therefore
    /// don't need to know about per-call proxying — they can satisfy only
    /// the original `post` requirement.
    public nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String,
        body: Body,
        proxyDID: DID?
    ) async throws -> Response {
        try await post(lexicon: lexicon, body: body)
    }
}
