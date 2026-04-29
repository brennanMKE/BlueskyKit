# BlueskyAuth

`BlueskyAuth` is the authentication module for BlueskyKit. It provides the concrete session implementation and the two SwiftUI views that drive the sign-in flow.

## Overview

The module depends on `BlueskyCore` (value types) and `BlueskyKit` (protocol contracts). It has no dependency on `BlueskyNetworking` — auth endpoints are called directly with `URLSession` because they require unauthenticated or refresh-token–authenticated requests, not the access-token bearer used by `NetworkClient`.

All types in this module default to `@MainActor` isolation via the shared `swiftSettings` in `Package.swift`.

## Types

### `SessionManager`

`@MainActor @Observable public final class SessionManager: SessionManaging`

The production implementation of the `SessionManaging` protocol. It owns all observable session state and is the single source of truth for which account is active.

**Initializer**

```swift
public init(accountStore: any AccountStore, network: any NetworkClient)
```

Inject a `KeychainAccountStore` (or any `AccountStore`) and an `ATProtoClient` (or any `NetworkClient`). The `network` parameter is reserved for post-auth calls such as profile hydration; auth itself uses `URLSession` directly.

**Published state**

| Property | Type | Description |
|---|---|---|
| `currentAccount` | `Account?` | The currently active account, or `nil` when signed out. |
| `accounts` | `[Account]` | All accounts stored on this device, including inactive ones. |
| `serviceURL` | `URL` | Target PDS (default `https://bsky.social`). Set before calling `login` to support self-hosted servers. |

**Methods**

`restoreLastSession() async`
Call once from the app's root view `.task` or `.onAppear`. Loads all stored accounts from the `AccountStore`, resolves the last-active DID, refreshes the access token if needed, and sets `currentAccount`. Failures are swallowed so the app falls through to the login screen silently.

`login(identifier:password:authFactorToken:) async throws -> Account`
Authenticates via `com.atproto.server.createSession`. Pass a TOTP code in `authFactorToken` when the server first returns `ATError.authFactorTokenRequired`. Saves the `StoredAccount` to the `AccountStore` and updates `currentAccount`.

`resumeSession(_ stored: StoredAccount) async throws`
Resumes a previously stored session. If the access JWT is expired (or expires within 60 seconds), the method calls `com.atproto.server.refreshSession` and persists the new tokens before continuing.

`switchAccount(to did: DID) async throws`
Switches the active session to an account that is already in `accounts`. Calls `resumeSession` internally.

`logout(did: DID) async throws`
Signs the account out. Calls `com.atproto.server.deleteSession` on a best-effort basis (errors are ignored), then clears the stored access and refresh tokens. The `Account` entry is kept in the store so the user can re-authenticate quickly.

`removeAccount(did: DID) async throws`
Permanently removes the account from the `AccountStore` and from `accounts`. Clears `currentAccount` if the removed account was active.

**JWT expiry check**

`jwtIsExpired(_:)` decodes the JWT payload (base64url), reads the `exp` claim, and returns `true` if the token expires within the next 60 seconds. Tokens that cannot be decoded are treated as expired.

**AT Protocol endpoints**

Auth endpoints are called with raw `URLSession` to avoid circular dependencies with `NetworkClient`:

| Method | Endpoint | Auth header |
|---|---|---|
| `callCreateSession` | `xrpc/com.atproto.server.createSession` | None (unauthenticated) |
| `callRefreshSession` | `xrpc/com.atproto.server.refreshSession` | `Bearer <refreshJwt>` |
| `callDeleteSession` | `xrpc/com.atproto.server.deleteSession` | `Bearer <refreshJwt>` |

XRPC error responses (`{"error":…, "message":…}`) are decoded and re-thrown as `ATError.xrpc`. The `AuthFactorTokenRequired` XRPC error is mapped to `ATError.authFactorTokenRequired` for the UI to detect.

---

### `LoginView`

`public struct LoginView: View`

A full sign-in form. Handles handle/password entry, optional custom PDS URL, and TOTP 2FA when the server requests it.

**Initializer**

```swift
public init(session: SessionManager, onSuccess: @escaping () -> Void)
```

`onSuccess` is called on the main actor after `session.login` returns successfully. Use it to dismiss the view or navigate to the main feed.

**Behavior**

- Shows a username/email field and a password field.
- When `SessionManager.login` throws `ATError.authFactorTokenRequired`, the view animates in a "Two-factor code" field and re-submits automatically when the user taps "Verify".
- A "Use a custom server" toggle reveals a hosting-provider URL field. The URL is validated (`http` or `https` scheme) before being assigned to `session.serviceURL`.
- Inline error messages are shown for `ATError.xrpc`, `ATError.network`, and `ATError.httpStatus`.
- The sign-in button is disabled while loading or when either the handle or password field is empty.

---

### `AccountPickerView`

`public struct AccountPickerView: View`

Displays all accounts stored on the device and lets the user switch to one or add a new one.

**Initializer**

```swift
public init(
    session: SessionManager,
    onAccountSelected: @escaping () -> Void,
    onAddAccount: @escaping () -> Void
)
```

`onAccountSelected` is invoked after `session.switchAccount` succeeds. `onAddAccount` is invoked when the user taps "Use a different account" to navigate to `LoginView`.

**Behavior**

- Lists all entries from `session.accounts` in a scrollable `LazyVStack`.
- The active account (`session.currentAccount`) is marked with a checkmark.
- A per-row loading indicator appears while `switchAccount` is in flight.
- Each row has a context menu with a destructive "Remove account" action that calls `session.removeAccount`.
- Error messages from either action are shown below the list.

---

## Usage example

```swift
// App root
@State private var session = SessionManager(
    accountStore: KeychainAccountStore(),
    network: ATProtoClient(accountStore: KeychainAccountStore())
)

var body: some Scene {
    WindowGroup {
        ContentView(session: session)
            .task { await session.restoreLastSession() }
    }
}

// Auth gate
if session.currentAccount != nil {
    MainFeedView(session: session)
} else if session.accounts.isEmpty {
    LoginView(session: session) { /* navigate */ }
} else {
    AccountPickerView(
        session: session,
        onAccountSelected: { /* navigate */ },
        onAddAccount: { /* show LoginView */ }
    )
}
```
