import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

nonisolated private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "SessionManager"
)

/// Production implementation of `SessionManaging`.
///
/// Stores all sessions in the injected `AccountStore` (Keychain in production).
/// Auth-specific endpoints (`createSession`, `refreshSession`, `deleteSession`) are
/// called directly with `URLSession` because they need unauthenticated or
/// refresh-token–authenticated requests — not the access-token bearer used by
/// the general `NetworkClient`.
@MainActor
@Observable
public final class SessionManager: SessionManaging {

    /// The account whose credentials are active for API calls.
    public private(set) var currentAccount: Account?

    /// All accounts stored on this device, including those not currently active.
    public private(set) var accounts: [Account] = []

    /// Service URL used by `login(identifier:password:authFactorToken:)`.
    /// Override before calling login to support self-hosted PDS.
    public var serviceURL: URL = URL(string: "https://bsky.social")!

    private let accountStore: any AccountStore
    // Reserved for post-auth calls (e.g. profile hydration after login)
    private let network: any NetworkClient

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(accountStore: any AccountStore, network: any NetworkClient) {
        self.accountStore = accountStore
        self.network = network
    }

    // MARK: - App launch restore

    /// Loads all stored accounts and resumes the last active session.
    /// Call once from the app's root view on appear.
    public func restoreLastSession() async {
        logger.debug("restoreLastSession start")
        do {
            let allStored = try await accountStore.loadAll()
            logger.debug("loadAll returned \(allStored.count, privacy: .public) stored accounts")
            accounts = allStored.map { $0.account }

            let currentDID = try await accountStore.loadCurrentDID()
            logger.debug("loadCurrentDID returned \(currentDID?.rawValue ?? "nil", privacy: .public)")

            if let currentDID,
               let stored = allStored.first(where: { $0.account.did == currentDID }) {
                logger.debug("resuming session for \(currentDID.rawValue, privacy: .public)")
                try await resumeSession(stored)
                logger.debug("resumeSession succeeded")
            } else {
                logger.debug("no session to restore — showing login")
            }
        } catch {
            logger.error("restoreLastSession failed: \(error, privacy: .public)")
        }
    }

    // MARK: - SessionManaging

    @discardableResult
    public func login(identifier: String, password: String, authFactorToken: String?) async throws -> Account {
        let response = try await callCreateSession(
            identifier: identifier,
            password: password,
            authFactorToken: authFactorToken,
            serviceURL: serviceURL
        )

        let account = Account(
            did: DID(rawValue: response.did),
            handle: Handle(rawValue: response.handle),
            displayName: nil,
            avatarURL: nil,
            serviceEndpoint: serviceURL,
            email: response.email,
            emailConfirmed: response.emailConfirmed
        )
        let stored = StoredAccount(account: account, accessJwt: response.accessJwt, refreshJwt: response.refreshJwt)

        try await accountStore.save(stored)
        try await accountStore.setCurrentDID(account.did)
        upsert(account: account)
        currentAccount = account

        return account
    }

    public func resumeSession(_ stored: StoredAccount) async throws {
        var stored = stored

        if jwtIsExpired(stored.accessJwt) {
            let refreshed = try await callRefreshSession(stored: stored)
            stored = StoredAccount(
                account: stored.account,
                accessJwt: refreshed.accessJwt,
                refreshJwt: refreshed.refreshJwt
            )
            try await accountStore.save(stored)
        }

        upsert(account: stored.account)
        currentAccount = stored.account
    }

    public func switchAccount(to did: DID) async throws {
        guard let stored = try await accountStore.load(did: did) else {
            throw ATError.unknown("No stored account for DID \(did)")
        }
        try await resumeSession(stored)
        try await accountStore.setCurrentDID(did)
    }

    public func logout(did: DID) async throws {
        if let stored = try await accountStore.load(did: did) {
            // Best-effort server-side session deletion; ignore errors
            try? await callDeleteSession(stored: stored)
            // Clear tokens; keep the Account entry for quick re-login
            let cleared = StoredAccount(account: stored.account, accessJwt: "", refreshJwt: "")
            try await accountStore.save(cleared)
        }

        if currentAccount?.did == did {
            currentAccount = nil
            try await accountStore.setCurrentDID(nil)
        }
    }

    public func removeAccount(did: DID) async throws {
        try await accountStore.remove(did: did)
        accounts.removeAll { $0.did == did }

        if currentAccount?.did == did {
            currentAccount = nil
            try await accountStore.setCurrentDID(nil)
        }
    }

    // MARK: - AT Protocol auth endpoints

    private func callCreateSession(
        identifier: String,
        password: String,
        authFactorToken: String?,
        serviceURL: URL
    ) async throws -> CreateSessionResponse {
        let url = serviceURL.appending(path: "xrpc/com.atproto.server.createSession")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            CreateSessionBody(identifier: identifier, password: password, authFactorToken: authFactorToken)
        )
        return try await send(req, expecting: CreateSessionResponse.self)
    }

    private func callRefreshSession(stored: StoredAccount) async throws -> RefreshSessionResponse {
        let url = stored.account.serviceEndpoint.appending(path: "xrpc/com.atproto.server.refreshSession")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(stored.refreshJwt)", forHTTPHeaderField: "Authorization")
        return try await send(req, expecting: RefreshSessionResponse.self)
    }

    private func callDeleteSession(stored: StoredAccount) async throws {
        let url = stored.account.serviceEndpoint.appending(path: "xrpc/com.atproto.server.deleteSession")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(stored.refreshJwt)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)
    }

    private func send<T: Decodable>(_ request: URLRequest, expecting: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ATError.decodingFailed(String(describing: error))
        }
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if let xrpcError = try? decoder.decode(XRPCErrorEnvelope.self, from: data) {
                if xrpcError.error == "AuthFactorTokenRequired" {
                    throw ATError.authFactorTokenRequired
                }
                throw ATError.xrpc(code: xrpcError.error, message: xrpcError.message ?? "")
            }
            throw ATError.httpStatus(http.statusCode)
        }
    }

    // MARK: - JWT expiry

    /// Returns `true` if the JWT is expired or expires within the next 60 seconds.
    private func jwtIsExpired(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return true }

        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem != 0 { b64 += String(repeating: "=", count: 4 - rem) }

        guard let data = Data(base64Encoded: b64),
              let claims = try? JSONDecoder().decode(JWTClaims.self, from: data),
              let exp = claims.exp else { return true }

        return Date(timeIntervalSince1970: TimeInterval(exp)) <= Date().addingTimeInterval(60)
    }

    // MARK: - Helpers

    private func upsert(account: Account) {
        if let i = accounts.firstIndex(where: { $0.did == account.did }) {
            accounts[i] = account
        } else {
            accounts.append(account)
        }
    }
}

// MARK: - Private Codable types

private struct CreateSessionBody: Encodable, Sendable {
    let identifier: String
    let password: String
    let authFactorToken: String?
}

private struct CreateSessionResponse: Decodable, Sendable {
    let did: String
    let handle: String
    let email: String?
    let emailConfirmed: Bool?
    let accessJwt: String
    let refreshJwt: String
}

private struct RefreshSessionResponse: Decodable, Sendable {
    let did: String
    let handle: String
    let accessJwt: String
    let refreshJwt: String
}

private struct XRPCErrorEnvelope: Decodable, Sendable {
    let error: String
    let message: String?
}

private struct JWTClaims: Decodable, Sendable {
    let exp: Int?
}
