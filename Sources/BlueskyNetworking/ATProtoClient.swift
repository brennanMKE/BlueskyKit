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

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(accountStore: any AccountStore, session: URLSession = .shared) {
        self.accountStore = accountStore
        self.session = session
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
        try await performPost(lexicon: lexicon, body: body)
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
        body: Body
    ) async throws -> Response {
        let stored = try await currentStoredAccount()
        let request = try buildPostRequest(stored: stored, lexicon: lexicon, body: body)
        let (data, response) = try await rawSend(request)

        if (response as? HTTPURLResponse)?.statusCode == 401 {
            let refreshed = try await refreshTokens(stored: stored)
            let retryRequest = try buildPostRequest(stored: refreshed, lexicon: lexicon, body: body)
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
        return req
    }

    private func buildPostRequest<Body: Encodable>(
        stored: StoredAccount,
        lexicon: String,
        body: Body
    ) throws -> URLRequest {
        let url = stored.account.serviceEndpoint.appending(path: "xrpc/\(lexicon)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(stored.accessJwt)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
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
        return req
    }

    // MARK: - Network primitives

    private func rawSend(_ request: URLRequest) async throws -> (Data, URLResponse) {
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
        do {
            return try decoder.decode(type, from: data)
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

    /// Calls `refreshSession` on the PDS, saves the new tokens, and returns the updated `StoredAccount`.
    ///
    /// Throws `ATError.sessionExpired` if the refresh token is rejected.
    private func refreshTokens(stored: StoredAccount) async throws -> StoredAccount {
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
