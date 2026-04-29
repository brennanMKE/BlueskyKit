# BlueskyKit

`BlueskyKit` is the protocol-contract module for BlueskyKit. It defines the interfaces every other module depends on — session management, account persistence, network access, preferences, and caching — without providing any concrete implementations.

## Overview

The module has a single dependency: `BlueskyCore` (value types). All higher-level modules (`BlueskyAuth`, `BlueskyNetworking`, `BlueskyDataStore`, feature modules) import `BlueskyKit` to consume these contracts and inject concrete implementations.

All types in this module default to `@MainActor` isolation via the shared `swiftSettings` in `Package.swift`, with the notable exception that each protocol's requirements are declared `nonisolated` so implementations may themselves be actors.

---

## Protocols

### `SessionManaging`

```swift
public protocol SessionManaging: AnyObject, Sendable
```

The single source of truth for which account is currently active. It is the only protocol in `BlueskyKit` whose requirements are intended to run on the main actor — implementations are expected to be `@MainActor @Observable` classes so that SwiftUI views can observe session state directly.

**Properties**

| Property | Type | Description |
|---|---|---|
| `currentAccount` | `Account?` | The active account, or `nil` when signed out. |
| `accounts` | `[Account]` | All accounts stored on this device, for account switching. |

**Methods**

| Method | Description |
|---|---|
| `login(identifier:password:authFactorToken:) async throws -> Account` | Authenticates and persists the session. Pass a TOTP code in `authFactorToken` for 2FA flows. |
| `resumeSession(_ stored: StoredAccount) async throws` | Restores a stored session silently. Throws `ATError.sessionExpired` if the refresh token is no longer valid. |
| `switchAccount(to did: DID) async throws` | Switches the active session to an account already in `accounts`. |
| `logout(did: DID) async throws` | Signs out the account and clears its access tokens; keeps the account entry for quick re-login. |
| `removeAccount(did: DID) async throws` | Permanently removes the account and all stored credentials from this device. |

The production implementation is `SessionManager` in `BlueskyAuth`.

---

### `AccountStore`

```swift
public protocol AccountStore: AnyObject, Sendable
```

Persists `StoredAccount` values (an `Account` bundled with its JWTs) across app launches. All requirements are `nonisolated async` so implementations can be actor-isolated (e.g. a Swift actor serializing Keychain access).

**Methods**

| Method | Description |
|---|---|
| `save(_ account: StoredAccount) async throws` | Saves or overwrites the record for `account.account.did`. |
| `loadAll() async throws -> [StoredAccount]` | Returns all stored accounts in insertion order. |
| `load(did: DID) async throws -> StoredAccount?` | Returns the stored account for a DID, or `nil`. |
| `remove(did: DID) async throws` | Deletes the stored account. No-ops if not found. |
| `setCurrentDID(_ did: DID?) async throws` | Persists which DID is the currently active account. |
| `loadCurrentDID() async throws -> DID?` | Returns the persisted active DID, or `nil`. |

The production implementation is `KeychainAccountStore` in `BlueskyDataStore`.

---

### `NetworkClient`

```swift
public protocol NetworkClient: AnyObject, Sendable
```

Makes XRPC requests to the AT Protocol PDS. All requirements are `nonisolated async` so implementations can be actor-isolated and hold mutable state (token storage, retry counters) safely. The protocol is generic over response and body types, constrained to `Decodable & Sendable` and `Encodable & Sendable` respectively.

**Methods**

```swift
nonisolated func get<Response: Decodable & Sendable>(
    lexicon: String,
    params: [String: String]
) async throws -> Response
```

Performs an XRPC query (HTTP GET). `lexicon` is the lexicon NSID (e.g. `"app.bsky.feed.getTimeline"`). `params` are URL query parameters encoded as strings by the client.

```swift
nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
    lexicon: String,
    body: Body
) async throws -> Response
```

Performs an XRPC procedure (HTTP POST). `body` is JSON-encoded by the client.

```swift
nonisolated func upload<Response: Decodable & Sendable>(
    lexicon: String,
    data: Data,
    mimeType: String
) async throws -> Response
```

Uploads raw binary data (e.g. an image) to an XRPC blob endpoint. Typically called with `"com.atproto.repo.uploadBlob"`.

Auth endpoints (`createSession`, `refreshSession`, `deleteSession`) bypass `NetworkClient` entirely and use `URLSession` directly inside `SessionManager` — they need unauthenticated or refresh-token bearer auth, not the access-token bearer this client sends.

The production implementation is `ATProtoClient` in `BlueskyNetworking`.

---

### `PreferencesStore`

```swift
public protocol PreferencesStore: AnyObject, Sendable
```

Reads and writes typed user preferences. Values are JSON-encoded `Codable` blobs stored under plain string keys. All requirements are `nonisolated` (synchronous) so implementations can be simple wrappers around `UserDefaults` without async overhead.

**Methods**

| Method | Description |
|---|---|
| `set<T: Codable & Sendable>(_ value: T, for key: String) throws` | Encodes `value` as JSON and stores it under `key`. |
| `get<T: Codable & Sendable>(_ type: T.Type, for key: String) throws -> T?` | Decodes and returns the value for `key`, or `nil` if absent. |
| `remove(for key: String)` | Removes the value for `key`. No-ops if absent. |

The production implementation wraps `UserDefaults`.

---

### `CacheStore`

```swift
public protocol CacheStore: AnyObject, Sendable
```

A key/value cache with optional per-entry TTL. All requirements are `nonisolated async` so implementations can be actor-isolated (e.g. a Swift actor wrapping an in-memory dictionary or SwiftData store).

The protocol implements a stale-while-revalidate pattern: `fetch` always returns the cached entry even if expired. Callers display stale content immediately and trigger a background refresh when `CacheResult.isExpired` is `true`. `CacheResult<T>` is defined in `BlueskyCore` (not `BlueskyKit`) so it can be constructed and accessed from any actor context without `@MainActor` restrictions.

**Methods**

| Method | Description |
|---|---|
| `store<T: Codable & Sendable>(_ value: T, for key: String, ttl: TimeInterval?) async throws` | Encodes and stores `value`. Pass `nil` for `ttl` to cache indefinitely. |
| `fetch<T: Codable & Sendable>(_ type: T.Type, for key: String) async throws -> CacheResult<T>?` | Returns the cached entry (even if expired), or `nil` if no entry exists. |
| `evict(for key: String) async throws` | Removes the entry for `key`. No-ops if absent. |
| `evictAll() async throws` | Removes all cached entries. |

---

## Bootstrap

### `BlueskyEnvironment`

```swift
@MainActor @Observable
public final class BlueskyEnvironment
```

The application's dependency container. Assemble it at app launch by injecting one concrete implementation per protocol, then insert it into the SwiftUI environment. All feature modules receive their dependencies by reading this environment object.

**Properties**

| Property | Type |
|---|---|
| `session` | `any SessionManaging` |
| `accounts` | `any AccountStore` |
| `preferences` | `any PreferencesStore` |
| `network` | `any NetworkClient` |
| `cache` | `any CacheStore` |

---

## Usage

### Wiring the dependency graph

```swift
@main
struct BlueskyApp: App {
    let env = BlueskyEnvironment(
        session: SessionManager(
            accountStore: KeychainAccountStore(),
            network: ATProtoClient(accountStore: KeychainAccountStore())
        ),
        accounts: KeychainAccountStore(),
        preferences: UserDefaultsPreferencesStore(),
        network: ATProtoClient(accountStore: KeychainAccountStore()),
        cache: SwiftDataCacheStore(appGroupIdentifier: "group.app.bsky")
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(env)
                .task { await env.session.restoreLastSession() }
        }
    }
}
```

### Reading dependencies in feature views

```swift
struct TimelineView: View {
    @Environment(BlueskyEnvironment.self) private var env

    var body: some View {
        // env.session, env.network, env.cache are all available
    }
}
```

### Writing a mock for testing

Because `NetworkClient` is `nonisolated`, mocks do not need `@MainActor`. Use `@unchecked Sendable` to satisfy the protocol's `Sendable` requirement when the mock does not have real concurrency safety needs:

```swift
final class MockNetworkClient: NetworkClient, @unchecked Sendable {
    nonisolated func get<Response: Decodable & Sendable>(
        lexicon: String,
        params: [String: String]
    ) async throws -> Response {
        // return fixture data
    }

    nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String,
        body: Body
    ) async throws -> Response {
        // return fixture data
    }

    nonisolated func upload<Response: Decodable & Sendable>(
        lexicon: String,
        data: Data,
        mimeType: String
    ) async throws -> Response {
        // return fixture data
    }
}
```

For `@MainActor` protocols such as `SessionManaging`, use a `@MainActor final class` mock instead:

```swift
@MainActor
final class MockSessionManager: SessionManaging {
    var currentAccount: Account? = nil
    var accounts: [Account] = []

    func login(identifier: String, password: String, authFactorToken: String?) async throws -> Account {
        // return a fixture Account
    }
    // ...
}
```

---

## Dependencies

`BlueskyKit` imports `BlueskyCore` only. It has no dependency on Foundation beyond what `BlueskyCore` already imports, and no dependency on any other BlueskyKit module.
