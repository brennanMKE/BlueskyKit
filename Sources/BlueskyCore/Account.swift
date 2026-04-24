import Foundation

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

    public init(
        did: DID,
        handle: Handle,
        displayName: String?,
        avatarURL: URL?,
        serviceEndpoint: URL,
        email: String?,
        emailConfirmed: Bool?
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.serviceEndpoint = serviceEndpoint
        self.email = email
        self.emailConfirmed = emailConfirmed
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
