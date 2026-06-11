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

    /// Calls `com.atproto.server.describeServer` against the current `serviceURL`
    /// (or the supplied override). Used by the signup flow to drive the invite-
    /// code requirement and the available user-domain suffix list.
    public func describeServer(_ serviceURL: URL? = nil) async throws -> DescribeServerResponse {
        let target = serviceURL ?? self.serviceURL
        let url = target.appending(path: "xrpc/com.atproto.server.describeServer")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(req, expecting: DescribeServerResponse.self)
    }

    /// Creates a new account on the chosen PDS and persists the resulting
    /// session exactly like `login(identifier:password:authFactorToken:)`.
    @discardableResult
    public func createAccount(
        request: CreateAccountRequest,
        serviceURL: URL? = nil,
        birthDate: Date? = nil,
        email: String? = nil
    ) async throws -> Account {
        let target = serviceURL ?? self.serviceURL
        let url = target.appending(path: "xrpc/com.atproto.server.createAccount")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let response: CreateAccountResponse = try await send(req, expecting: CreateAccountResponse.self)

        let account = Account(
            did: DID(rawValue: response.did),
            handle: Handle(rawValue: response.handle),
            displayName: nil,
            avatarURL: nil,
            serviceEndpoint: target,
            email: email ?? request.email,
            emailConfirmed: false,
            status: nil
        )
        let stored = StoredAccount(
            account: account,
            accessJwt: response.accessJwt,
            refreshJwt: response.refreshJwt
        )

        try await accountStore.save(stored)
        try await accountStore.setCurrentDID(account.did)
        upsert(account: account)
        currentAccount = account
        self.serviceURL = target

        // Best-effort: write birth date as a personal detail. Failure is non-fatal —
        // matches RN behavior where personal-details writes are fire-and-forget after
        // createAccount succeeds.
        if let birthDate {
            do {
                try await callPutPreferences(
                    accessJwt: response.accessJwt,
                    serviceEndpoint: target,
                    birthDate: birthDate
                )
            } catch {
                logger.debug("createAccount: failed to set initial birthDate preference: \(error.localizedDescription, privacy: .public)")
            }
        }

        return account
    }

    private func callPutPreferences(accessJwt: String, serviceEndpoint: URL, birthDate: Date) async throws {
        // Read-modify-write (#0201): `putPreferences` replaces the entire
        // preference namespace, so even this fresh-account write fetches the
        // current full array first and merges the birth date into it. This
        // path runs before the authenticated `NetworkClient` exists, so it
        // performs the GET + PUT legs directly via URLSession.
        var getReq = URLRequest(url: serviceEndpoint.appending(path: "xrpc/app.bsky.actor.getPreferences"))
        getReq.setValue("Bearer \(accessJwt)", forHTTPHeaderField: "Authorization")
        let (getData, getResponse) = try await URLSession.shared.data(for: getReq)
        try validateHTTP(response: getResponse, data: getData)
        let current = try JSONDecoder().decode(GetPreferencesResponse.self, from: getData)

        let url = serviceEndpoint.appending(path: "xrpc/app.bsky.actor.putPreferences")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessJwt)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(
            PutPreferencesRequest(merging: current.rawPreferences, applying: .birthDate(birthDate))
        )
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)
    }

    /// Requests a password-reset email for `email` from the chosen PDS.
    /// The PDS sends an `XXXXX-XXXXX` base32 code to the address; the user
    /// then completes the flow with `resetPassword(serviceURL:token:password:)`.
    ///
    /// Called while signed out, so we go directly via `URLSession` rather than
    /// the authenticated `NetworkClient`. Throws `ATError.xrpc` on a server
    /// rejection.
    public func requestPasswordReset(serviceURL: URL? = nil, email: String) async throws {
        let target = serviceURL ?? self.serviceURL
        let url = target.appending(path: "xrpc/com.atproto.server.requestPasswordReset")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(RequestPasswordResetRequest(email: email))

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)
    }

    /// Submits the user's reset code and a new password to the chosen PDS,
    /// completing the forgot-password flow. Bluesky returns an empty body on
    /// success.
    ///
    /// Called while signed out, so we go directly via `URLSession`. Throws
    /// `ATError.xrpc` on an invalid token / rejected password.
    public func resetPassword(serviceURL: URL? = nil, token: String, password: String) async throws {
        let target = serviceURL ?? self.serviceURL
        let url = target.appending(path: "xrpc/com.atproto.server.resetPassword")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ResetPasswordRequest(token: token, password: password))

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)
    }

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
            emailConfirmed: response.emailConfirmed,
            status: SessionManager.normalizeStatus(active: response.active, status: response.status)
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
            let refreshedAccount = stored.account.with(
                status: Self.normalizeStatus(active: refreshed.active, status: refreshed.status)
            )
            stored = StoredAccount(
                account: refreshedAccount,
                accessJwt: refreshed.accessJwt,
                refreshJwt: refreshed.refreshJwt
            )
            try await accountStore.save(stored)
        }

        upsert(account: stored.account)
        currentAccount = stored.account

        // Pull the authoritative `status` flag from `getSession` so the gate in
        // RootView can tell active / deactivated / takendown / suspended apart.
        // Best-effort: a network failure here must not block the resume — the
        // user is signed in either way; we'll re-check on the next launch.
        do {
            let info = try await callGetSession(stored: stored)
            let merged = stored.account.with(
                status: Self.normalizeStatus(active: info.active, status: info.status)
            )
            let updatedStored = StoredAccount(
                account: merged,
                accessJwt: stored.accessJwt,
                refreshJwt: stored.refreshJwt
            )
            try await accountStore.save(updatedStored)
            upsert(account: merged)
            if currentAccount?.did == merged.did {
                currentAccount = merged
            }
        } catch {
            logger.debug("getSession during resume failed (non-fatal): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Refreshes the active session's `status` from `com.atproto.server.getSession`.
    ///
    /// Used by `DeactivatedView` after a successful `activateAccount` so the
    /// RootView gate can re-evaluate and route to MainTabView. Returns the
    /// updated `Account` on success.
    @discardableResult
    public func refreshCurrentSession() async throws -> Account {
        guard let did = currentAccount?.did,
              let stored = try await accountStore.load(did: did) else {
            throw ATError.unknown("No active session to refresh")
        }
        let info = try await callGetSession(stored: stored)
        let merged = stored.account.with(
            status: Self.normalizeStatus(active: info.active, status: info.status)
        )
        let updatedStored = StoredAccount(
            account: merged,
            accessJwt: stored.accessJwt,
            refreshJwt: stored.refreshJwt
        )
        try await accountStore.save(updatedStored)
        upsert(account: merged)
        currentAccount = merged
        return merged
    }

    /// Calls `com.atproto.server.activateAccount` on the active account's PDS.
    ///
    /// On success the account leaves the `deactivated` state. The caller
    /// should follow up with `refreshCurrentSession()` so the RootView gate
    /// can route back to `MainTabView`. Mirrors RN's `Deactivated.tsx`
    /// `handleActivate` flow (`agent.com.atproto.server.activateAccount()`
    /// followed by `agent.resumeSession`).
    public func activateAccount() async throws {
        guard let did = currentAccount?.did,
              let stored = try await accountStore.load(did: did) else {
            throw ATError.unknown("No active session to activate")
        }
        let url = stored.account.serviceEndpoint.appending(path: "xrpc/com.atproto.server.activateAccount")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(stored.accessJwt)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)
    }

    /// Submits a takendown / suspended-account appeal as a moderation report
    /// against the current user's own DID. Mirrors RN's `Takendown.tsx`
    /// `submitAppeal` mutation:
    ///
    ///     agent.com.atproto.moderation.createReport(
    ///       { reasonType: ToolsOzoneReportDefs.REASONAPPEAL,
    ///         subject: { $type: 'com.atproto.admin.defs#repoRef',
    ///                    did: currentAccount.did },
    ///         reason: appealText },
    ///       { headers: BLUESKY_MOD_SERVICE_HEADERS })
    ///
    /// The `BLUESKY_MOD_SERVICE_HEADERS` constant routes the report through
    /// the Bluesky moderation labeler at
    /// `did:plc:ar7c4by46qjdydhdevvrndac#atproto_labeler`. Without that
    /// header the request would otherwise hit the user's PDS and be rejected
    /// (the takendown account can't act on its own behalf there).
    ///
    /// We bypass the shared `NetworkClient.post` because:
    ///   * The caller is in a `.takendown` / `.suspended` state — wrapping
    ///     in the standard auto-refresh path would compete with the gate.
    ///   * The labeler proxy header is one-shot, not a global proxy rule.
    ///
    /// Throws `ATError.xrpc` on a server rejection so the view can render
    /// the message inline.
    public func submitTakendownAppeal(reason: String) async throws {
        guard let did = currentAccount?.did,
              let stored = try await accountStore.load(did: did) else {
            throw ATError.unknown("No active session to appeal")
        }

        let body = TakendownAppealBody(
            reasonType: "tools.ozone.report.defs#reasonAppeal",
            subject: TakendownAppealBody.Subject(did: did.rawValue),
            reason: reason
        )

        let url = stored.account.serviceEndpoint.appending(path: "xrpc/com.atproto.moderation.createReport")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(stored.accessJwt)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Route the report through the Bluesky moderation labeler. RN sets
        // the same header via `BLUESKY_MOD_SERVICE_HEADERS`.
        req.setValue("did:plc:ar7c4by46qjdydhdevvrndac#atproto_labeler", forHTTPHeaderField: "atproto-proxy")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)
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
            // Best-effort server-side session deletion. Failure here does not block
            // local logout: we still clear tokens below. Log at debug level so the
            // discarded error is observable.
            do {
                try await callDeleteSession(stored: stored)
            } catch {
                logger.debug("server-side deleteSession failed (continuing local logout): \(error.localizedDescription, privacy: .public)")
            }
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

    private func callGetSession(stored: StoredAccount) async throws -> GetSessionResponse {
        let url = stored.account.serviceEndpoint.appending(path: "xrpc/com.atproto.server.getSession")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(stored.accessJwt)", forHTTPHeaderField: "Authorization")
        return try await send(req, expecting: GetSessionResponse.self)
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

        guard let data = Data(base64Encoded: b64) else { return true }
        let claims: JWTClaims
        do {
            claims = try JSONDecoder().decode(JWTClaims.self, from: data)
        } catch {
            // Treat as expired so a refresh is triggered. Log at debug level so a
            // chronically malformed JWT becomes observable rather than silent.
            logger.debug("JWT claims decode failed: \(error.localizedDescription, privacy: .public)")
            return true
        }
        guard let exp = claims.exp else { return true }

        return Date(timeIntervalSince1970: TimeInterval(exp)) <= Date().addingTimeInterval(60)
    }

    // MARK: - Helpers

    /// Reconciles the two flavors of "is this account in a holding state" that
    /// the AT Proto server returns. Mirrors RN, which prefers `status` when
    /// present and falls back to `active` (treating `active: true` as the
    /// implicit `.active` state).
    static func normalizeStatus(active: Bool?, status: AccountStatus?) -> AccountStatus? {
        if let status { return status }
        if active == false { return nil } // unknown specific status, but inactive
        return .active
    }

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
    let active: Bool?
    let status: AccountStatus?
}

private struct RefreshSessionResponse: Decodable, Sendable {
    let did: String
    let handle: String
    let accessJwt: String
    let refreshJwt: String
    let active: Bool?
    let status: AccountStatus?
}

private struct XRPCErrorEnvelope: Decodable, Sendable {
    let error: String
    let message: String?
}

private struct JWTClaims: Decodable, Sendable {
    let exp: Int?
}

/// Request body for the takendown / suspended self-appeal call. Encodes as a
/// `com.atproto.moderation.createReport` payload with the subject as a
/// `com.atproto.admin.defs#repoRef` pointing at the user's own DID.
private struct TakendownAppealBody: Encodable, Sendable {
    let reasonType: String
    let subject: Subject
    let reason: String

    struct Subject: Encodable, Sendable {
        let did: String

        private enum CodingKeys: String, CodingKey {
            case type = "$type", did
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("com.atproto.admin.defs#repoRef", forKey: .type)
            try c.encode(did, forKey: .did)
        }
    }
}
