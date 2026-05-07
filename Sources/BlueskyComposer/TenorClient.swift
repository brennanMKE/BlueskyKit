import Foundation
import OSLog

private nonisolated let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "TenorClient"
)

// MARK: - Tenor result models

/// A single GIF result from Tenor's v2 API. Field shape mirrors the v2
/// envelope (`https://developers.google.com/tenor/guides/response-objects-and-errors`)
/// — only the fields the composer renders or posts are decoded.
public struct TenorGif: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String?
    public let contentDescription: String?
    public let mediaFormats: TenorMediaFormats

    /// The URL the composer posts as the external embed `uri`. Mirrors RN's
    /// `resolveGif` which uses `media_formats.gif.url` + width/height query
    /// params.
    public var gifURL: String { mediaFormats.gif.url }

    /// The URL rendered in the picker grid. Tenor returns `tinygif` for
    /// thumbnails; static rendering is fine — see issue #0099 Gotchas for the
    /// animated-thumbnail follow-up.
    public var thumbURL: String { mediaFormats.tinygif.url }

    /// The URL whose bytes are uploaded as the embed `thumb` blob. RN uses
    /// `media_formats.preview.url` (a static JPEG/PNG). Falls back to
    /// `tinygif` when `preview` is missing.
    public var previewURL: String { mediaFormats.preview?.url ?? mediaFormats.tinygif.url }

    /// Width / height of the canonical GIF, used by RN to set `hh` / `ww`
    /// query params on the embed URI so consumers can lay the GIF out
    /// without a network round-trip.
    public var dims: (width: Int, height: Int) {
        let dims = mediaFormats.gif.dims
        guard dims.count >= 2 else { return (0, 0) }
        return (dims[0], dims[1])
    }

    /// Free-text description used as the embed `title`. Falls back to the
    /// post title if `content_description` is missing (some Tenor results
    /// omit it).
    public var altText: String {
        if let cd = contentDescription, !cd.isEmpty { return cd }
        return title ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case contentDescription = "content_description"
        case mediaFormats = "media_formats"
    }
}

public struct TenorMediaFormats: Decodable, Sendable, Equatable {
    public let gif: TenorMediaObject
    public let tinygif: TenorMediaObject
    public let preview: TenorMediaObject?

    public init(gif: TenorMediaObject, tinygif: TenorMediaObject, preview: TenorMediaObject?) {
        self.gif = gif
        self.tinygif = tinygif
        self.preview = preview
    }
}

public struct TenorMediaObject: Decodable, Sendable, Equatable {
    public let url: String
    public let dims: [Int]
    public let size: Int?
    public let duration: Double?

    public init(url: String, dims: [Int] = [], size: Int? = nil, duration: Double? = nil) {
        self.url = url
        self.dims = dims
        self.size = size
        self.duration = duration
    }
}

private struct TenorEnvelope: Decodable {
    let results: [TenorGif]
    let next: String?
}

// MARK: - TenorClient

/// Backs the composer's GIF picker. Mirrors RN's
/// `state/queries/tenor.ts` — calls Bluesky's GIF proxy
/// (`https://gifs.bsky.app/tenor/v2/...`) rather than Tenor directly, so no
/// Tenor API key is required. The proxy applies the search / contentfilter /
/// media_filter parameters RN sets.
///
/// Modeled as `nonisolated final class` rather than an actor because there's
/// no shared mutable state — every call is a stateless `URLSession` request
/// and `URLSession.shared` is itself thread-safe. Keeping it
/// nonisolated lets the picker call into it from MainActor-isolated UI
/// without hopping actors.
public final class TenorClient: Sendable {

    /// Default proxy that RN uses. Override for tests / custom deployments.
    public static let defaultBaseURL = URL(string: "https://gifs.bsky.app")!

    private let baseURL: URL
    private let session: URLSession
    private let clientKey: String

    public init(
        baseURL: URL = TenorClient.defaultBaseURL,
        session: URLSession = .shared,
        clientKey: String = TenorClient.defaultClientKey
    ) {
        self.baseURL = baseURL
        self.session = session
        self.clientKey = clientKey
    }

    /// Platform-tagged client identifier (RN sets `bluesky-ios` / `bluesky-android` /
    /// `bluesky-web`). We only ship Apple platforms; tag iOS and macOS
    /// separately so the proxy's analytics can distinguish them.
    public static var defaultClientKey: String {
        #if os(iOS)
        return "bluesky-ios"
        #elseif os(macOS)
        return "bluesky-macos"
        #else
        return "bluesky-apple"
        #endif
    }

    // MARK: - Endpoints

    /// Featured / trending GIFs, shown when the search box is empty. Matches
    /// RN's `useTenorFeaturedGifsQuery`.
    public func featured(pos: String? = nil, locale: String? = nil) async throws -> [TenorGif] {
        try await fetch(path: "/tenor/v2/featured", query: ["pos": pos], locale: locale)
    }

    /// Search results for a free-text query. Matches RN's
    /// `useTenorGifSearchQuery`.
    public func search(query: String, pos: String? = nil, locale: String? = nil) async throws -> [TenorGif] {
        try await fetch(
            path: "/tenor/v2/search",
            query: ["q": query, "pos": pos],
            locale: locale
        )
    }

    // MARK: - Internal

    private func fetch(
        path: String,
        query: [String: String?],
        locale: String?
    ) async throws -> [TenorGif] {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_key", value: clientKey),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "contentfilter", value: "high"),
            // RN sets `media_filter=preview,gif,tinygif`. The proxy only honors a
            // subset of formats; including `preview` ensures we receive the
            // static thumbnail bytes we upload as the embed `thumb` blob.
            URLQueryItem(name: "media_filter", value: "preview,gif,tinygif")
        ]
        if let locale, !locale.isEmpty {
            items.append(URLQueryItem(name: "locale", value: locale))
        }
        for (key, value) in query {
            guard let value, !value.isEmpty else { continue }
            items.append(URLQueryItem(name: key, value: value))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Tenor request failed: status=\(code, privacy: .public) url=\(url.absoluteString, privacy: .public)")
            throw URLError(.badServerResponse)
        }
        do {
            let envelope = try JSONDecoder().decode(TenorEnvelope.self, from: data)
            return envelope.results
        } catch {
            logger.error("Tenor decode failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
