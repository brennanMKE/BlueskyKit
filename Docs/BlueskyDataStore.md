# BlueskyDataStore

`BlueskyDataStore` provides the production persistence implementations for the three storage protocols defined in `BlueskyKit`: `AccountStore`, `PreferencesStore`, and `CacheStore`.

## Overview

All three types are actor-safe. They use the `nonisolated` wrapper pattern: the public `nonisolated` methods required by each protocol hop to the concrete actor or class executor, keeping implementation details isolated and preventing data races.

The module depends on `BlueskyCore` and `BlueskyKit`. It has no UI dependency and no `@MainActor` default isolation.

## Types

### `KeychainAccountStore`

`public actor KeychainAccountStore: AccountStore`

Stores `StoredAccount` values in the iOS/macOS Keychain under `kSecClassGenericPassword`.

**Initializer**

```swift
public init(service: String = "app.bsky")
```

`service` maps to `kSecAttrService`. Override it when multiple app targets need separate Keychain namespaces (e.g. `"com.example.myapp"`).

**Storage layout**

| Keychain account attribute | Content |
|---|---|
| `"account:<did>"` | JSON-encoded `StoredAccount` |
| `"current-did"` | UTF-8 string of the active DID's raw value |

All items are stored with `kSecAttrAccessibleAfterFirstUnlock`, which allows session restore during background fetch without requiring the device to be unlocked.

**Methods** (all `nonisolated`, dispatching to actor-isolated private counterparts)

| Method | Behaviour |
|---|---|
| `save(_ account: StoredAccount)` | Upserts: updates existing item if found, adds new item otherwise. |
| `loadAll()` | Returns all items whose `kSecAttrAccount` begins with `"account:"`. Skips the `"current-did"` entry automatically. |
| `load(did:)` | Loads a single `StoredAccount` by DID. Returns `nil` when `errSecItemNotFound`. |
| `remove(did:)` | Deletes the item. No-ops when not found (`errSecItemNotFound` is not an error). |
| `setCurrentDID(_ did:)` | Delete-then-add: deletes the existing `"current-did"` entry unconditionally before writing the new value. Pass `nil` to clear the active DID without writing a replacement. |
| `loadCurrentDID()` | Returns the active `DID`, or `nil` if the entry is absent. |

**`KeychainError`**

```swift
public enum KeychainError: Error, Sendable {
    case addFailed(OSStatus)
    case updateFailed(OSStatus)
    case deleteFailed(OSStatus)
    case readFailed(OSStatus)
}
```

Wraps raw `OSStatus` values. `errSecItemNotFound` is never thrown — callers receive `nil` or a no-op instead.

---

### `UserDefaultsPreferencesStore`

`public final class UserDefaultsPreferencesStore: PreferencesStore, @unchecked Sendable`

Stores typed user preferences as JSON-encoded blobs in `UserDefaults`. `UserDefaults` is documented as thread-safe, which is why `@unchecked Sendable` is safe here.

**Initializer**

```swift
public init(suiteName: String? = nil)
```

Pass an App Group identifier (e.g. `"group.com.example.myapp"`) to share preferences between the main app and extensions. Defaults to `UserDefaults.standard` when `suiteName` is `nil` or when the suite cannot be created.

**Methods** (all `nonisolated`)

| Method | Behaviour |
|---|---|
| `set<T: Codable & Sendable>(_ value: T, for key: String)` | Encodes `value` to JSON and writes it under `key`. |
| `get<T: Codable & Sendable>(_ type: T.Type, for key: String) -> T?` | Reads the blob for `key`, decodes it, and returns the typed value. Returns `nil` if absent. |
| `remove(for key: String)` | Removes the value for `key`. No-op if not present. |

---

### `SwiftDataCacheStore`

`public actor SwiftDataCacheStore: CacheStore`

Stores arbitrary `Codable` values as JSON blobs in a SwiftData (`ModelContainer`) database with optional per-entry TTL.

**`CacheEntry` model**

```swift
@Model final class CacheEntry {
    @Attribute(.unique) var key: String
    var data: Data          // JSON-encoded value
    var expiresAt: Date?    // nil = cache indefinitely
    var storedAt: Date
}
```

Each operation creates a fresh `ModelContext` to avoid cross-context change-tracking conflicts and keep actor state minimal.

**Initializers**

```swift
public init(appGroupIdentifier: String? = nil) throws
```
Creates a persistent store. Pass an App Group identifier to place the SwiftData file (`BlueskyCache.store`) in the shared container so a notification extension can read the same cache.

```swift
public static func inMemory() throws -> SwiftDataCacheStore
```
Creates an in-memory store. Use this in tests and Xcode Previews.

**Methods** (all `nonisolated`, dispatching to actor-isolated private counterparts)

| Method | Behaviour |
|---|---|
| `store<T>(_ value: T, for key: String, ttl: TimeInterval?)` | Delete-then-insert: removes any existing entry for `key` before writing the new one to prevent duplicate primary keys. Pass `nil` for `ttl` to cache indefinitely. |
| `fetch<T>(_ type: T.Type, for key: String) -> CacheResult<T>?` | Returns the cached entry, including stale entries. `CacheResult.isExpired` is `true` when `expiresAt < .now`. Returns `nil` only when no entry exists for `key`. |
| `evict(for key: String)` | Deletes the entry for `key`. No-op if absent. |
| `evictAll()` | Deletes all `CacheEntry` rows. |

**Stale-while-revalidate pattern**

`fetch` always returns an entry if one exists, even if it is expired. The caller checks `result.isExpired` and decides whether to show the stale value while kicking off a background refresh. This avoids a blank-screen flash on slow networks.

---

## Usage example

```swift
// Wiring up dependencies at the app entry point
let accountStore = KeychainAccountStore()           // actor
let prefsStore = UserDefaultsPreferencesStore()    // final class
let cacheStore = try SwiftDataCacheStore()          // actor

let network = ATProtoClient(accountStore: accountStore)
let session = SessionManager(accountStore: accountStore, network: network)

// Reading a preference
let theme = try prefsStore.get(AppTheme.self, for: "theme")

// Writing a preference
try prefsStore.set(AppTheme.dark, for: "theme")

// Caching a feed response (10-minute TTL)
try await cacheStore.store(feedResponse, for: "timeline", ttl: 600)

// Fetching with stale-while-revalidate
if let result = try await cacheStore.fetch(FeedResponse.self, for: "timeline") {
    showFeed(result.value)
    if result.isExpired {
        Task { await refreshTimeline() }
    }
}
```
