# BlueskyNetworking

`BlueskyNetworking` provides the production `NetworkClient` implementation for AT Protocol XRPC requests. It handles Bearer-token authentication and automatic token refresh on HTTP 401.

## Overview

The module depends on `BlueskyCore` and `BlueskyKit`. It has no UI dependency. `ATProtoClient` is a Swift actor, so all internal state (encoders, decoders, the `URLSession` reference) is isolated to its executor and safe to share across concurrent callers.

Auth-specific endpoints (`createSession`, `refreshSession`, `deleteSession`) are **not** handled here. Those belong to `BlueskyAuth.SessionManager`, which calls them with a different auth header (refresh token or no token). `ATProtoClient` only sends the access JWT.

## Types

### `ATProtoClient`

`public actor ATProtoClient: NetworkClient`

A URLSession-backed implementation of the `NetworkClient` protocol. Sends access-token Bearer authentication on every request and transparently refreshes the token on a single HTTP 401 before retrying.

**Initializer**

```swift
public init(accountStore: any AccountStore, session: URLSession = .shared)
```

`accountStore` is queried for the current `StoredAccount` before each request. Inject a custom `URLSession` (with a specific configuration or mock) in tests.

**Methods** (all `nonisolated`, dispatching to actor-isolated private counterparts)

| Method | HTTP | Description |
|---|---|---|
| `get<Response>(lexicon:params:)` | GET | XRPC query. `params` are appended as URL query items, sorted alphabetically for stable URLs. |
| `post<Body, Response>(lexicon:body:)` | POST | XRPC procedure. `body` is JSON-encoded with ISO 8601 date strategy. |
| `upload<Response>(lexicon:data:mimeType:)` | POST | Raw binary upload (e.g. `com.atproto.repo.uploadBlob`). `Content-Type` is set to the supplied `mimeType`; the body is the raw `Data` without JSON encoding. |

All three methods follow the same request lifecycle:

1. Load the current `StoredAccount` from the `AccountStore`. Throws `ATError.unauthenticated` if none exists.
2. Build the `URLRequest` with the access JWT in `Authorization: Bearer <accessJwt>`.
3. Send the request via `URLSession`.
4. If the response status is 401, call `refreshTokens` and retry the original request once with the new access JWT.
5. On any other non-2xx status, decode the XRPC error envelope and throw `ATError.xrpc` or `ATError.httpStatus`.

**URL construction**

Requests target `<serviceEndpoint>/xrpc/<lexicon>`. The `serviceEndpoint` comes from `stored.account.serviceEndpoint`, which defaults to `https://bsky.social` but can be overridden per-account to support self-hosted PDS servers.

**Token refresh**

```swift
private func refreshTokens(stored: StoredAccount) async throws -> StoredAccount
```

Calls `xrpc/com.atproto.server.refreshSession` with `Authorization: Bearer <refreshJwt>`. On success, persists the new `StoredAccount` to the `AccountStore` and returns it. If the server returns a non-2xx status, throws `ATError.sessionExpired` — the app should route the user back to the login screen.

Refresh is attempted at most once per request. If the retry also returns 401, the error propagates to the caller.

**Error mapping**

| Condition | Thrown error |
|---|---|
| `URLError` from `URLSession` | `ATError.network(urlError)` |
| Non-2xx with XRPC error body | `ATError.xrpc(code:message:)` |
| Non-2xx without parseable body | `ATError.httpStatus(statusCode)` |
| 401 on refresh attempt | `ATError.sessionExpired` |
| No current account | `ATError.unauthenticated` |
| JSON decode failure | `ATError.decodingFailed(description)` |

---

## Usage example

```swift
// Wire up once at app startup
let accountStore = KeychainAccountStore()
let client = ATProtoClient(accountStore: accountStore)

// XRPC GET
struct TimelineParams: Encodable { ... }
let feed: FeedResponse = try await client.get(
    lexicon: "app.bsky.feed.getTimeline",
    params: ["limit": "50", "cursor": cursor]
)

// XRPC POST
struct LikeBody: Encodable & Sendable { ... }
struct LikeResponse: Decodable & Sendable { ... }
let result: LikeResponse = try await client.post(
    lexicon: "com.atproto.repo.createRecord",
    body: LikeBody(...)
)

// Binary upload
let blob: BlobResponse = try await client.upload(
    lexicon: "com.atproto.repo.uploadBlob",
    data: imageData,
    mimeType: "image/jpeg"
)
```

## Testing

Inject a mock that conforms to `NetworkClient` (defined in `BlueskyKit`):

```swift
final class MockNetworkClient: NetworkClient, @unchecked Sendable {
    nonisolated func get<Response: Decodable & Sendable>(
        lexicon: String,
        params: [String: String]
    ) async throws -> Response { ... }

    nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String,
        body: Body
    ) async throws -> Response { ... }

    nonisolated func upload<Response: Decodable & Sendable>(
        lexicon: String,
        data: Data,
        mimeType: String
    ) async throws -> Response { ... }
}
```

Because the protocol requirements are `nonisolated`, the mock does not need to be an actor — `@unchecked Sendable` is sufficient for test doubles that return fixture data without shared mutable state.
