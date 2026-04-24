import BlueskyCore

/// Contract for managing authenticated Bluesky sessions.
///
/// `BlueskyAuth` provides the production implementation. Tests inject a mock.
/// All requirements run on the `@MainActor` (inherited from the module default).
public protocol SessionManaging: AnyObject, Sendable {
    /// The currently active account, or `nil` if no session is open.
    var currentAccount: Account? { get }

    /// All accounts that have been added to this device (for account switching).
    var accounts: [Account] { get }

    /// Authenticates with `identifier` (handle, DID, or email) and `password`.
    ///
    /// Pass a TOTP token in `authFactorToken` when 2FA is required.
    /// Returns the newly authenticated `Account` and persists the session.
    @discardableResult
    func login(identifier: String, password: String, authFactorToken: String?) async throws -> Account

    /// Restores a previously stored session without prompting the user.
    ///
    /// Throws `ATError.sessionExpired` if the refresh token is no longer valid.
    func resumeSession(_ stored: StoredAccount) async throws

    /// Switches the active account to the one identified by `did`.
    ///
    /// The account must already be in `accounts`. Throws if not found.
    func switchAccount(to did: DID) async throws

    /// Signs out the account identified by `did` and clears its access tokens.
    ///
    /// The account remains in `accounts` for quick re-login; use `removeAccount`
    /// to fully delete it from the device.
    func logout(did: DID) async throws

    /// Removes the account from this device entirely, including stored credentials.
    func removeAccount(did: DID) async throws
}
