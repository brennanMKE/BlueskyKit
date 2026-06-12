import Foundation

/// Status of a Bluesky account as reported by `com.atproto.server.getSession`
/// (and `createSession` / `refreshSession`).
///
/// `active` is the implicit default — when the server response omits `status`
/// the account is considered active. The other three values gate the app into
/// dedicated holding screens (deactivated / takendown / suspended) before the
/// main UI is shown.
public enum AccountStatus: String, Codable, Sendable, Hashable {
    case active
    case takendown
    case suspended
    case deactivated
}

/// An authenticated Bluesky account (in-memory representation).
///
/// The auth module constructs this from a session response + DID document.
/// `serviceEndpoint` is the PDS base URL (e.g. `https://bsky.social`) and
/// supports self-hosted PDS deployments.
public struct Account: Codable, Hashable, Identifiable, Sendable {
    public var id: DID { did }

    public let did: DID
    public let handle: Handle
    public let displayName: String?
    public let avatarURL: URL?
    public let serviceEndpoint: URL
    public let email: String?
    public let emailConfirmed: Bool?
    /// Account moderation/lifecycle status. `nil` is treated as `.active` —
    /// matches RN, which also treats absent `status` and `active: true` as the
    /// regular signed-in state. Persisted with the rest of the account so the
    /// gate decision survives app restarts before the next `getSession`.
    public let status: AccountStatus?

    public init(
        did: DID,
        handle: Handle,
        displayName: String?,
        avatarURL: URL?,
        serviceEndpoint: URL,
        email: String?,
        emailConfirmed: Bool?,
        status: AccountStatus? = nil
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.serviceEndpoint = serviceEndpoint
        self.email = email
        self.emailConfirmed = emailConfirmed
        self.status = status
    }

    /// Convenience: `true` when the server has not flagged the account into a
    /// holding state. Existing call sites that don't care about lifecycle can
    /// keep using this rather than spelling out the enum.
    public var isActive: Bool {
        switch status {
        case nil, .active: return true
        case .takendown, .suspended, .deactivated: return false
        }
    }

    /// Returns a copy with `status` replaced. Used by `SessionManager` when
    /// `getSession` updates the lifecycle state without changing identity.
    public func with(status newStatus: AccountStatus?) -> Account {
        Account(
            did: did,
            handle: handle,
            displayName: displayName,
            avatarURL: avatarURL,
            serviceEndpoint: serviceEndpoint,
            email: email,
            emailConfirmed: emailConfirmed,
            status: newStatus
        )
    }

    /// Returns a copy with `serviceEndpoint` replaced. Used by `SessionManager`
    /// when a session response's DID document reports the account's actual PDS
    /// host (which can differ from the entryway URL used to sign in).
    public func with(serviceEndpoint newEndpoint: URL) -> Account {
        Account(
            did: did,
            handle: handle,
            displayName: displayName,
            avatarURL: avatarURL,
            serviceEndpoint: newEndpoint,
            email: email,
            emailConfirmed: emailConfirmed,
            status: status
        )
    }
}

/// An account bundled with its JWTs for Keychain persistence.
///
/// The auth module serializes this to JSON and stores it in the Keychain.
public struct StoredAccount: Codable, Sendable {
    public let account: Account
    public let accessJwt: String
    public let refreshJwt: String

    public init(account: Account, accessJwt: String, refreshJwt: String) {
        self.account = account
        self.accessJwt = accessJwt
        self.refreshJwt = refreshJwt
    }
}
