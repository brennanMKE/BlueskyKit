import Foundation
import BlueskyCore
import BlueskyKit

/// URLSession-based `NetworkClient` for AT Protocol XRPC requests.
///
/// Attaches the current account's access JWT as a Bearer header.
/// On HTTP 401, performs one token refresh via `com.atproto.server.refreshSession`
/// and retries the original request before propagating the error.
public actor ATProtoClient: NetworkClient {

    private let accountStore: any AccountStore
    private let session: URLSession
    private let pathMonitor: (any NetworkPathMonitoring)?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // `.iso8601` uses ISO8601DateFormatter's default options, which reject
        // fractional seconds — but the AT Proto appview routinely emits
        // timestamps like `...:00.123Z`, so whole feed items failed to decode
        // (#0214). Parse fractional first, fall back to whole-second, and
        // tolerate >3 fractional digits by truncating to milliseconds.
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = ATProtoClient.parseISO8601(s) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid ISO8601 date: \(s)"
            )
        }
        return d
    }()

    // ISO8601 parsing is serialized through this actor's isolation (the decoder
    // is only used from actor-isolated `decode`), so sharing these formatters is
    // safe. `nonisolated(unsafe)` opts out of the Sendable check accordingly.
    nonisolated(unsafe) private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses an AT Proto ISO8601 timestamp, tolerating fractional seconds
    /// (including >3 digits, which `ISO8601DateFormatter` otherwise rejects).
    nonisolated static func parseISO8601(_ s: String) -> Date? {
        if let d = iso8601Fractional.date(from: s) { return d }
        if let d = iso8601Plain.date(from: s) { return d }
        if let normalized = normalizeFractionalSeconds(s),
           let d = iso8601Fractional.date(from: normalized) {
            return d
        }
        return nil
    }

    /// Truncates sub-second precision to milliseconds so a microsecond/
    /// nanosecond timestamp (e.g. `...:00.123456Z`) parses.
    nonisolated private static func normalizeFractionalSeconds(_ s: String) -> String? {
        guard let dot = s.firstIndex(of: ".") else { return nil }
        let afterDot = s.index(after: dot)
        var end = afterDot
        while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
        let digits = s[afterDot..<end]
        guard digits.count > 3 else { return nil }
        return String(s[s.startIndex..<afterDot]) + digits.prefix(3) + String(s[end...])
    }

    public init(
        accountStore: any AccountStore,
        session: URLSession = .shared,
        pathMonitor: (any NetworkPathMonitoring)? = nil
    ) {
        self.accountStore = accountStore
        self.session = session
        self.pathMonitor = pathMonitor
    }

    // MARK: - NetworkClient

    nonisolated public func get<Response: Decodable & Sendable>(
        lexicon: String,
        params: [String: String]
    ) async throws -> Response {
        try await performGet(lexicon: lexicon, params: params)
    }

    nonisolated public func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String,
        body: Body
    ) async throws -> Response {
        try await performPost(lexicon: lexicon, body: body, proxyDID: nil)
    }

    /// Per-call proxied POST. Attaches `atproto-proxy: <did>#atproto_labeler`
    /// when `proxyDID` is non-nil, otherwise behaves identically to the
    /// non-proxied `post`. Mirrors RN's `agent.createModerationReport(..., {
    /// headers: { 'atproto-proxy': '<did>#atproto_labeler' }})`.
    nonisolated public func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String,
        body: Body,
        proxyDID: DID?
    ) async throws -> Response {
        try await performPost(lexicon: lexicon, body: body, proxyDID: proxyDID)
    }

    nonisolated public func upload<Response: Decodable & Sendable>(
        lexicon: String,
        data: Data,
        mimeType: String
    ) async throws -> Response {
        try await performUpload(lexicon: lexicon, data: data, mimeType: mimeType)
    }

    // MARK: - Actor-isolated implementations

    private func performGet<Response: Decodable & Sendable>(
        lexicon: String,
        params: [String: String]
    ) async throws -> Response {
        let stored = try await currentStoredAccount()
        let request = buildGetRequest(stored: stored, lexicon: lexicon, params: params)
        let (data, response) = try await rawSend(request)

        if (response as? HTTPURLResponse)?.statusCode == 401 {
            let refreshed = try await refreshTokens(stored: stored)
            let retryRequest = buildGetRequest(stored: refreshed, lexicon: lexicon, params: params)
            let (retryData, retryResponse) = try await rawSend(retryRequest)
            return try decode(Response.self, from: retryData, response: retryResponse)
        }

        return try decode(Response.self, from: data, response: response)
    }

    private func performUpload<Response: Decodable & Sendable>(
        lexicon: String,
        data: Data,
        mimeType: String
    ) async throws -> Response {
        let stored = try await currentStoredAccount()
        let request = buildUploadRequest(stored: stored, lexicon: lexicon, data: data, mimeType: mimeType)
        let (responseData, response) = try await rawSend(request)

        if (response as? HTTPURLResponse)?.statusCode == 401 {
            let refreshed = try await refreshTokens(stored: stored)
            let retryRequest = buildUploadRequest(stored: refreshed, lexicon: lexicon, data: data, mimeType: mimeType)
            let (retryData, retryResponse) = try await rawSend(retryRequest)
            return try decode(Response.self, from: retryData, response: retryResponse)
        }

        return try decode(Response.self, from: responseData, response: response)
    }

    private func performPost<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String,
        body: Body,
        proxyDID: DID?
    ) async throws -> Response {
        let stored = try await currentStoredAccount()
        let request = try buildPostRequest(stored: stored, lexicon: lexicon, body: body, proxyDID: proxyDID)
        let (data, response) = try await rawSend(request)

        if (response as? HTTPURLResponse)?.statusCode == 401 {
            let refreshed = try await refreshTokens(stored: stored)
            let retryRequest = try buildPostRequest(stored: refreshed, lexicon: lexicon, body: body, proxyDID: proxyDID)
            let (retryData, retryResponse) = try await rawSend(retryRequest)
            return try decode(Response.self, from: retryData, response: retryResponse)
        }

        return try decode(Response.self, from: data, response: response)
    }

    // MARK: - Request building

    private func buildGetRequest(
        stored: StoredAccount,
        lexicon: String,
        params: [String: String]
    ) -> URLRequest {
        var components = URLComponents(
            url: stored.account.serviceEndpoint.appending(path: "xrpc/\(lexicon)"),
            resolvingAgainstBaseURL: false
        )!
        if !params.isEmpty {
            components.queryItems = params.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(stored.accessJwt)", forHTTPHeaderField: "Authorization")
        applyProxyHeader(&req, lexicon: lexicon)
        return req
    }

    private func buildPostRequest<Body: Encodable>(
        stored: StoredAccount,
        lexicon: String,
        body: Body,
        proxyDID: DID? = nil
    ) throws -> URLRequest {
        let url = stored.account.serviceEndpoint.appending(path: "xrpc/\(lexicon)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(stored.accessJwt)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        if let proxyDID {
            // Per-call proxy override (e.g. moderation report routed to a
            // specific labeler). Takes precedence over the lexicon-prefix rule
            // below — the caller knows which service should handle the call.
            req.setValue("\(proxyDID.rawValue)#atproto_labeler", forHTTPHeaderField: "atproto-proxy")
        } else {
            applyProxyHeader(&req, lexicon: lexicon)
        }
        return req
    }

    private func buildUploadRequest(
        stored: StoredAccount,
        lexicon: String,
        data: Data,
        mimeType: String
    ) -> URLRequest {
        let url = stored.account.serviceEndpoint.appending(path: "xrpc/\(lexicon)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(stored.accessJwt)", forHTTPHeaderField: "Authorization")
        req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        applyProxyHeader(&req, lexicon: lexicon)
        return req
    }

    /// Adds the `atproto-proxy` header for lexicons served by a separate AT Protocol service.
    ///
    /// `chat.bsky.*` lexicons are served by the chat proxy at `did:web:api.bsky.chat#bsky_chat`,
    /// not by the user's PDS. The PDS forwards proxied requests to the appropriate service
    /// based on this header. Without it the PDS responds with `MethodNotImplemented`.
    ///
    /// Mirrors `DM_SERVICE_HEADERS` in the React Native reference (`src/lib/constants.ts`).
    private nonisolated func applyProxyHeader(_ req: inout URLRequest, lexicon: String) {
        if lexicon.hasPrefix("chat.bsky.") {
            req.setValue("did:web:api.bsky.chat#bsky_chat", forHTTPHeaderField: "atproto-proxy")
        }
    }

    // MARK: - Network primitives

    private func rawSend(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if let monitor = pathMonitor, !monitor.isViable {
            throw ATError.noNetwork
        }
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            throw ATError.network(urlError)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: URLResponse) throws -> T {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let envelope = try? decoder.decode(XRPCErrorEnvelope.self, from: data) {
                throw ATError.xrpc(code: envelope.error, message: envelope.message ?? "")
            }
            throw ATError.httpStatus(http.statusCode)
        }
        // Some AT Protocol procedures (e.g. createBookmark, deleteBookmark) return
        // HTTP 200 with an empty body rather than `{}`. Substitute an empty JSON
        // object so that Decodable types with no required fields decode cleanly.
        let payload = data.isEmpty ? Data("{}".utf8) : data
        do {
            return try decoder.decode(type, from: payload)
        } catch {
            throw ATError.decodingFailed(String(describing: error))
        }
    }

    // MARK: - Account + token refresh

    private func currentStoredAccount() async throws -> StoredAccount {
        guard let did = try await accountStore.loadCurrentDID(),
              let stored = try await accountStore.load(did: did) else {
            throw ATError.unauthenticated
        }
        return stored
    }

    /// In-flight refresh, so concurrent 401s coalesce onto a single
    /// `refreshSession` call instead of stampeding it (#0208). AT Proto rotates
    /// the refresh token, so parallel refreshes invalidate each other and a
    /// late one would overwrite the freshly-rotated tokens, spuriously expiring
    /// a valid session.
    private var refreshTask: Task<StoredAccount, Error>?

    /// Single-flight wrapper around `performRefresh`. If a refresh is already
    /// running, awaits it; otherwise starts one, re-loading the latest stored
    /// account first (another request may have already rotated the tokens).
    private func refreshTokens(stored: StoredAccount) async throws -> StoredAccount {
        if let task = refreshTask {
            return try await task.value
        }
        let task = Task<StoredAccount, Error> { [self] in
            let latest = (try? await currentStoredAccount()) ?? stored
            return try await performRefresh(stored: latest)
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// Calls `refreshSession` on the PDS, saves the new tokens, and returns the updated `StoredAccount`.
    ///
    /// Throws `ATError.sessionExpired` if the refresh token is rejected.
    private func performRefresh(stored: StoredAccount) async throws -> StoredAccount {
        let url = stored.account.serviceEndpoint.appending(path: "xrpc/com.atproto.server.refreshSession")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(stored.refreshJwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await rawSend(req)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ATError.sessionExpired
        }

        let refreshResponse: RefreshSessionResponse
        do {
            refreshResponse = try decoder.decode(RefreshSessionResponse.self, from: data)
        } catch {
            throw ATError.decodingFailed(String(describing: error))
        }

        let updated = StoredAccount(
            account: stored.account,
            accessJwt: refreshResponse.accessJwt,
            refreshJwt: refreshResponse.refreshJwt
        )
        try await accountStore.save(updated)
        return updated
    }
}

// MARK: - Private Codable types

private struct XRPCErrorEnvelope: Decodable, Sendable {
    let error: String
    let message: String?
}

private struct RefreshSessionResponse: Decodable, Sendable {
    let did: String
    let handle: String
    let accessJwt: String
    let refreshJwt: String
}
