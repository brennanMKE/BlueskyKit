# Concepts

This document is a glossary for anyone reading the BlueskyKit codebase without prior AT Protocol or Bluesky knowledge. It covers protocol fundamentals, Bluesky-specific constructs, and codebase architecture decisions. Each concept links naturally to the source types you will encounter while reading the code.

---

## AT Protocol Fundamentals

### DID

**Decentralized Identifier.** A globally unique, persistent identifier for an account that is independent of any particular server or domain. DIDs look like `did:plc:abc123...` or `did:web:example.com`. Because a DID is permanent, it survives handle changes, server migrations, and domain transfers.

In BlueskyKit, `DID` is a newtype wrapper over `String` defined in `BlueskyCore/Identifiers.swift`:

```swift
struct DID: RawRepresentable, Hashable, Codable {
    let rawValue: String
}
```

All API calls that target a specific account accept a `DID`, not a handle, because handles can change.

### Handle

A human-readable, mutable username such as `alice.bsky.social` or `alice.example.com`. Handles are resolved to DIDs via DNS TXT records or the `com.atproto.identity.resolveHandle` XRPC method before any account operation is performed.

`Handle` in `BlueskyCore/Identifiers.swift` is the same newtype pattern as `DID`.

### AT-URI

**AT Uniform Resource Identifier.** A URI scheme specific to AT Protocol that identifies a particular record in a particular repository. The format is:

```
at://<DID or handle>/<collection NSID>/<record key>
```

Example: `at://did:plc:abc123/app.bsky.feed.post/3k2j1h`

In the codebase the type is named `ATURI` to avoid colliding with Swift's `URI` vocabulary. It appears in `BlueskyCore/Identifiers.swift` and throughout the codebase wherever a record reference is stored (post likes, reposts, list memberships, report subjects).

### CID

**Content Identifier.** A hash of a record's content encoded in a standard multiformat. A CID changes whenever the record's content changes, so it acts as a version identifier. When you like a post, the like record embeds both the AT-URI (which post) and the CID (which version of that post), guaranteeing the like refers to an immutable snapshot.

`CID` in `BlueskyCore/Identifiers.swift` follows the same newtype pattern.

### NSID

**Namespaced Identifier.** A dot-separated identifier for a Lexicon (schema). NSIDs look like reverse-DNS domain names followed by a record or method name:

```
app.bsky.feed.post          <- record type
com.atproto.server.createSession  <- XRPC method
```

The first segment indicates ownership: `com.atproto.*` is the base protocol layer; `app.bsky.*` is the Bluesky application layer. Custom third-party schemas would use a different domain.

NSIDs do not appear as a dedicated Swift type in this codebase; they appear as string literals in `NetworkClient` call sites.

### Lexicon

A schema definition in AT Protocol, analogous to an OpenAPI specification for a single record type or XRPC method. A Lexicon file is JSON and defines field names, types, required fields, and constraints. Bluesky's Lexicons are open-sourced at `github.com/bluesky-social/atproto`.

BlueskyKit decodes Lexicon-defined records with private `Decodable` structs inside each module. The field names in those structs mirror the Lexicon definitions exactly (camelCase as JSON keys, with `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase` disabled — AT Proto uses camelCase natively).

### XRPC

**Cross-Resource Procedure Call.** The HTTP-based RPC mechanism AT Protocol uses. Every API call is either a `query` (GET) or a `procedure` (POST). Queries are idempotent and cacheable; procedures mutate state.

`NetworkClient` in `BlueskyKit` provides two generic methods:

```swift
func query<T: Decodable>(_ nsid: String, params: [String: String]) async throws -> T
func procedure<Body: Encodable, T: Decodable>(_ nsid: String, body: Body) async throws -> T
```

---

## Bluesky-Specific Concepts

### Feed Generator

A server-side algorithm that produces a custom timeline by returning a list of AT-URIs. Feed generators are themselves AT Protocol records (`app.bsky.feed.generator`) hosted on any server. When a client requests a feed, it calls `app.bsky.feed.getFeed` with the generator's AT-URI; the PDS proxies the call to the generator's declared service endpoint.

In BlueskyKit, the `FeedStore` fetches both the home timeline (`app.bsky.feed.getTimeline`) and any custom feed by AT-URI. The `Feed` and `FeedPost` types that describe the response live in `BlueskyCore/Feed.swift`.

### Labeler

A service that attaches semantic labels to content (posts, accounts, images) as a moderation signal. Labels can indicate adult content, spam, impersonation, and so on. Any third party can run a labeler; users subscribe to the labelers they trust.

Labels flow back from the API alongside the content they annotate. The client reads the user's per-labeler visibility preferences (`show`, `warn`, `hide`) and filters or warns accordingly.

In BlueskyKit, labelers are managed in `BlueskyModeration`. `LabelerProfileStore` fetches a single labeler's service record (`app.bsky.labeler.getService`). The `ContentFilterPreference` type in `BlueskyCore/Moderation.swift` represents the user's visibility choice for a given label value.

### Starter Pack

A curated package containing a list of accounts to follow and optionally a feed generator, designed to help new users bootstrap their experience quickly. Starter packs are `app.bsky.graph.starterpack` records and are displayed in `BlueskyFeed` and browsable from the profile area.

### Facet

A structured annotation on a span of text within a post. Facets enable rich text features like clickable mentions, hashtags, and hyperlinks without requiring a custom markup language. Each facet has a byte-range (start/end indices into the UTF-8 post text) and a `feature` describing what the span represents.

`Facet` and `FacetFeature` are defined in `BlueskyCore/RichText.swift`:

```swift
struct Facet: Codable {
    let index: ByteSlice        // { byteStart, byteEnd }
    let features: [FacetFeature]
}

enum FacetFeature: Codable {
    case mention(DID)
    case link(URL)
    case tag(String)
}
```

Facets are processed before display to annotate `AttributedString` spans.

### Embed

Structured media or reference attached to a post. AT Protocol defines several embed types:

| Embed type | NSID | Description |
|-----------|------|-------------|
| Images | `app.bsky.embed.images` | Up to 4 images with alt text |
| External | `app.bsky.embed.external` | Link card with title, description, thumbnail |
| Record | `app.bsky.embed.record` | Quoted post or linked record |
| Record with media | `app.bsky.embed.recordWithMedia` | Quoted post plus images or external |
| Video | `app.bsky.embed.video` | Video attachment |

`Embed` is defined in `BlueskyCore/Feed.swift` as an enum with associated values matching each type.

### Rich Text

A post's body text plus its array of `Facet` annotations. "Rich text" in AT Protocol is plain UTF-8 text plus out-of-band facets rather than an inline markup language. The `RichText` type in `BlueskyCore/RichText.swift` pairs the raw string with its facets and provides utilities for rendering.

### Moderation List vs. User List

Both are `app.bsky.graph.list` records. The `purpose` field distinguishes them:

| Purpose value | Meaning |
|--------------|---------|
| `app.bsky.graph.defs#modlist` | Moderation list — bulk mute or block all members |
| `app.bsky.graph.defs#curatelist` | Curation list — organizational grouping, similar to a Twitter list |

`BlueskyModeration` operates on moderation lists. A future `BlueskyLists` module would handle curation lists.

---

## Codebase Architecture

### Store / ViewModel / View Pattern

BlueskyKit uses a strict three-tier architecture for every feature:

```
NetworkClient / PreferencesStore
        |
      Store          <- owns all mutable state; performs I/O
        |
   ViewModel         <- pure transformations of store state for display
        |
      View           <- reads ViewModel; dispatches user actions to Store
```

The **Store** is an `@Observable` (or `ObservableObject`) class that holds `@Published` properties. It calls `NetworkClient` for remote I/O and `PreferencesStore` for local I/O. Stores contain no SwiftUI imports.

The **ViewModel** is also `@Observable` and depends on one or more stores. It exposes computed properties that convert raw model values (e.g., `Date`, `Int`) into display-ready types (e.g., `String`, `AttributedString`). ViewModels contain no networking code.

The **View** is a SwiftUI `View`. It reads from the ViewModel with `@StateObject` or `@EnvironmentObject`, and calls store methods in `.task {}` blocks or button actions. Views contain no business logic.

This separation means stores are unit-testable with a mock `NetworkClient` and no SwiftUI dependency, and ViewModels are testable with a mock store.

### Actor Isolation Model

BlueskyKit applies Swift's concurrency actor system deliberately and asymmetrically.

#### BlueskyCore: No Actor Isolation

`BlueskyCore` declares no `defaultIsolation` in `Package.swift`. All its types are plain structs and enums with no `@MainActor` annotation. This is intentional: `Decodable` conformances on these types will be called from networking task contexts (which run on cooperative thread pool threads, not the main actor). Adding `@MainActor` to these types would require every `JSONDecoder.decode` call to be awaited from an isolated context, producing unnecessary hops.

#### Feature Modules: @MainActor Default Isolation

All modules that contain UI (`BlueskyAuth`, `BlueskyFeed`, `BlueskySettings`, `BlueskyModeration`, etc.) declare:

```swift
// in Package.swift swiftSettings for the target:
.enableExperimentalFeature("StrictConcurrency"),
SwiftSetting.unsafeFlags(["-Xfrontend", "-default-actor-isolation", "-Xfrontend", "MainActor"])
```

This makes every type in those modules `@MainActor`-isolated by default, so ViewModels and Views automatically update on the main thread without explicit `DispatchQueue.main.async` calls. Stores that need to perform background I/O use `Task { }` internally; the async `NetworkClient` methods handle the thread hop.

#### BlueskyDataStore: Custom Actor

`KeychainAccountStore` in `BlueskyDataStore` is implemented as a custom actor (not `@MainActor`) because keychain access should not block the main thread. Its protocol, `AccountStore`, declares its requirements `nonisolated async` so callers on any isolation domain can call it with `await`.

```swift
// BlueskyKit/AccountStore.swift
public protocol AccountStore: Sendable {
    nonisolated func save(_ account: Account) async throws
    nonisolated func loadAll() async throws -> [Account]
    nonisolated func delete(_ did: DID) async throws
}
```

The same pattern applies to `PreferencesStore` and `NetworkClient`.

### Session Lifecycle

AT Protocol sessions consist of two JWTs:

| Token | Lexicon field | Typical TTL | Used for |
|-------|--------------|-------------|---------|
| Access token | `accessJwt` | ~2 hours | Bearer token on every API request |
| Refresh token | `refreshJwt` | ~90 days | Obtaining a new access token |

`SessionManager` (in `BlueskyAuth`) holds both tokens in memory and persists them in the keychain via `KeychainAccountStore`. When `NetworkClient` receives a `401 Unauthorized` response:

1. It calls `SessionManaging.refreshSession()` to POST to `com.atproto.server.refreshSession` using the `refreshJwt` as the bearer token.
2. On success, the new `accessJwt` (and possibly new `refreshJwt`) are saved and the original request is retried.
3. If the refresh call itself returns `401`, the session is considered expired; `SessionManaging.signOut()` is called and the app returns to the login screen.

Auth endpoints (`createSession`, `refreshSession`, `deleteSession`) bypass `NetworkClient` entirely and use raw `URLSession` calls within `SessionManager`. This avoids a circular dependency where `NetworkClient` would need a reference back to `SessionManager` to refresh tokens.

### Protocol-First Design

All cross-module dependencies are expressed as protocols defined in `BlueskyKit`, not concrete types:

| Protocol | Purpose |
|----------|---------|
| `SessionManaging` | Current user identity; sign-in / sign-out |
| `AccountStore` | Persist and retrieve `Account` records |
| `PreferencesStore` | Read and write user preferences |
| `NetworkClient` | Make XRPC queries and procedures |

Feature modules (`BlueskyFeed`, `BlueskySettings`, `BlueskyModeration`, etc.) depend on these protocols. The concrete implementations (`KeychainAccountStore`, `ATProtoClient`, etc.) live in separate modules (`BlueskyDataStore`, `BlueskyNetworking`). The Xcode app target wires everything together with dependency injection at startup.

This means any module can be developed and tested in isolation using lightweight mock implementations:

```swift
// Test double for NetworkClient
final class MockNetworkClient: NetworkClient, @unchecked Sendable {
    var stubbedResponse: Any?
    func query<T: Decodable>(_ nsid: String, params: [String: String]) async throws -> T {
        return stubbedResponse as! T
    }
    // ...
}
```

### Cursor-Based Pagination

AT Protocol list endpoints (timelines, follower lists, mute lists, etc.) use opaque cursor strings for pagination rather than page numbers or offsets. The first request omits a cursor; the response includes a `cursor` field if more results exist. Passing that cursor in the next request yields the following page.

```swift
struct PagedResult<T> {
    let items: [T]
    let cursor: String?   // nil means no more pages
}
```

Stores accumulate results by appending each page to a local array. Views trigger the next-page load by calling a store action when the user scrolls near the bottom of the list (the "load more" pattern). If `cursor` is `nil` after a fetch, the store sets a `hasMore: Bool` flag to `false` and stops making additional requests.

Cursors are opaque: do not attempt to parse or construct them. Their format is server-defined and may change between API versions.

### @MainActor Protocol Mocks vs. nonisolated Protocol Mocks

Because of the `defaultIsolation(MainActor.self)` setting in feature modules, mock implementations must declare their isolation carefully:

- **`@MainActor` protocol** (e.g., `SessionManaging`): mock is `@MainActor final class`
- **`nonisolated` protocol** (e.g., `NetworkClient`, `AccountStore`): mock is `final class, @unchecked Sendable`

Using `@unchecked Sendable` on `nonisolated` mocks suppresses the compiler warning about mutable state crossing concurrency boundaries, which is safe in tests because tests run serially. Do not use `@unchecked Sendable` on production types.

---

## Quick Reference: Type Locations

| Type | Module | File |
|------|--------|------|
| `DID`, `Handle`, `ATURI`, `CID` | `BlueskyCore` | `Identifiers.swift` |
| `Facet`, `FacetFeature`, `RichText` | `BlueskyCore` | `RichText.swift` |
| `Post`, `FeedPost`, `Embed` | `BlueskyCore` | `Feed.swift` |
| `Profile`, `ModerationList` | `BlueskyCore` | `Graph.swift` |
| `ContentFilterPreference` | `BlueskyCore` | `Moderation.swift` |
| `SessionManaging` | `BlueskyKit` | `SessionManaging.swift` |
| `AccountStore` | `BlueskyKit` | `AccountStore.swift` |
| `NetworkClient` | `BlueskyKit` | `NetworkClient.swift` |
| `KeychainAccountStore` | `BlueskyDataStore` | `KeychainAccountStore.swift` |
| `SessionManager`, `LoginView` | `BlueskyAuth` | (respective files) |
