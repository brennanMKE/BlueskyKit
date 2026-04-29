# BlueskyCore

`BlueskyCore` is the data-model foundation for BlueskyKit. It contains pure value types — identifiers, account/session structs, post and feed models, profile views, graph records, moderation types, chat, search, notifications, pagination, and errors — with no business logic and no actor isolation.

## Why no actor isolation

Network responses are decoded on URLSession's internal background threads. If `BlueskyCore` types carried `@MainActor` isolation (via `swiftSettings` in `Package.swift`), their `Codable` conformances would also be `@MainActor`-isolated, making them impossible to decode off the main thread without a warning or runtime hop.

`BlueskyCore` therefore has no `swiftSettings` entry. All of its types are plain value types (`struct`, `enum`, `typealias`) that are `Codable` and `Sendable` and can be constructed and decoded from any concurrency context. Every other module in BlueskyKit applies `defaultIsolation(MainActor.self)` and imports `BlueskyCore` freely.

---

## Identifiers

**File:** `Sources/BlueskyCore/Identifiers.swift`

### `DID`

A W3C Decentralized Identifier — the stable, permanent identity of an AT Protocol account. Typed as a `RawRepresentable` wrapper over `String` so the compiler prevents accidental confusion with handles or AT-URIs.

```swift
public struct DID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible
```

### `Handle`

A human-readable `@handle.tld` identifier. Like `DID`, it is a `RawRepresentable` wrapper; passing a `Handle` where a `DID` is expected is a compile error.

```swift
public struct Handle: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible
```

### `ATURI`

An AT-URI of the form `at://repo/collection/rkey`. Provides computed properties `repo`, `collection`, and `rkey` that parse the raw string on demand. No regex — uses `split(separator:maxSplits:)` for performance.

```swift
public struct ATURI: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible
// at://did:plc:xyz/app.bsky.feed.post/3abc
aturi.repo       // "did:plc:xyz"
aturi.collection // "app.bsky.feed.post"
aturi.rkey       // "3abc"
```

### `CID`

A content identifier — treated as an opaque `String` client-side. No crypto operations are performed; CIDs are only stored, compared, and forwarded.

```swift
public typealias CID = String
```

---

## Account and Auth

**Files:** `Sources/BlueskyCore/Account.swift`, `Sources/BlueskyCore/Auth.swift`

### `Account`

The in-memory representation of an authenticated Bluesky account. Constructed by `SessionManager` from a session response combined with profile data. `serviceEndpoint` is the PDS base URL (defaults to `https://bsky.social`) and enables self-hosted PDS support.

```swift
public struct Account: Codable, Hashable, Identifiable, Sendable
```

| Field | Type | Notes |
|---|---|---|
| `did` | `DID` | Primary identifier; also `id` for `Identifiable`. |
| `handle` | `Handle` | Human-readable handle. |
| `displayName` | `String?` | Optional display name. |
| `avatarURL` | `URL?` | CDN URL for the profile avatar. |
| `serviceEndpoint` | `URL` | PDS base URL for all API calls. |
| `email` | `String?` | Account email (only present on own account). |
| `emailConfirmed` | `Bool?` | Whether the email address has been verified. |

### `StoredAccount`

An `Account` bundled with its JWT pair for Keychain persistence. Serialized as JSON by `KeychainAccountStore`.

```swift
public struct StoredAccount: Codable, Sendable
// Fields: account, accessJwt, refreshJwt
```

### App password types

`AppPasswordView`, `ListAppPasswordsResponse`, `CreateAppPasswordRequest`, `CreateAppPasswordResponse`, and `RevokeAppPasswordRequest` model the `com.atproto.server.*AppPassword` endpoints. These allow users to create and revoke scoped app passwords for third-party clients.

---

## Posts and Feed

**Files:** `Sources/BlueskyCore/Post.swift`, `Sources/BlueskyCore/Feed.swift`

### `PostRecord`

The stored content of a post as written to the AT Protocol repo (`app.bsky.feed.post`). Used both when creating posts and when reading embedded `value` fields.

```swift
public struct PostRecord: Codable, Sendable
```

| Field | Type | Notes |
|---|---|---|
| `text` | `String` | Post body text. |
| `facets` | `[RichTextFacet]?` | Byte-range annotations (mentions, links, hashtags). |
| `embed` | `Embed?` | Attached media or quote. |
| `reply` | `ReplyRef?` | Root and parent pointers for reply posts. |
| `langs` | `[String]?` | BCP-47 language codes. |
| `createdAt` | `Date` | Client-side creation timestamp. |

### `PostView`

The full post view returned by feed and thread endpoints. Contains the resolved author, engagement counts, and viewer-state. Count fields default to `0` if absent in the JSON (the API omits zero counts).

```swift
public struct PostView: Codable, Sendable
```

Key fields: `uri`, `cid`, `author: ProfileBasic`, `record: PostRecord`, `embed: EmbedView?`, `replyCount`, `repostCount`, `likeCount`, `quoteCount`, `indexedAt`, `labels: [Label]`, `viewer: PostViewerState?`.

### `PostViewerState`

The authenticated viewer's relationship to a post.

| Field | Notes |
|---|---|
| `like: ATURI?` | AT-URI of the viewer's like record, set if the viewer has liked this post. |
| `repost: ATURI?` | AT-URI of the viewer's repost record. |
| `threadMuted: Bool?` | Whether the viewer has muted this thread. |
| `replyDisabled: Bool?` | Whether replies are disabled for the viewer. |

### `FeedViewPost`

A post as it appears in a feed (timeline, author feed, custom feed). Wraps a `PostView` with optional reply context (root/parent posts above the post) and an optional `FeedReason` (why it appeared — currently only repost).

### `FeedReason`

A discriminated enum decoded from `$type`. Currently only `.repost(by: ProfileBasic, indexedAt: Date)` is known; future server-side types are preserved as `.unknown(String)` for forward compatibility.

### `ReplyRef` / `ReplyContext`

`ReplyRef` is stored inside `PostRecord` and carries `{root, parent}` as `PostRef` pairs (AT-URI + CID). `ReplyContext` is the resolved version in `FeedViewPost`, carrying the actual `PostView` objects shown above a reply.

### `FeedResponse`

Response envelope for `getTimeline`, `getFeed`, and `getAuthorFeed`.

```swift
public struct FeedResponse: Decodable, Sendable {
    public let feed: [FeedViewPost]
    public let cursor: String?
}
```

### Thread types

`ThreadViewPost` is a recursive `indirect enum` with cases `.post(ThreadPost)`, `.notFound(uri:)`, `.blocked(uri:)`, and `.unknown`. `ThreadPost` holds a `PostView` plus optional `parent` and `replies` arrays, both also `ThreadViewPost`. `GetPostThreadResponse` wraps the root `ThreadViewPost`.

### Repo operation types

`CreateRecordRequest<T>`, `CreateRecordResponse`, `DeleteRecordRequest`, `PutRecordRequest<T>` model `com.atproto.repo.*` write endpoints. `EmptyResponse` is a no-field `Decodable` used for operations that return `{}`.

### Interaction records

`LikeRecord` and `RepostRecord` are encodable structs used with `CreateRecordRequest` to create like and repost records. Both embed `$type` in their `CodingKeys` so the JSON is self-describing.

### `ProfileRecord`

Encodable struct for updating a profile via `com.atproto.repo.putRecord`. Carries `displayName` and `description`.

---

## Profile

**File:** `Sources/BlueskyCore/Profile.swift`

Three progressively more detailed profile views are provided, matching the three AT Protocol lexicon levels.

### `ProfileBasic`

Minimal actor view used inside post, notification, and message payloads. Fields: `did`, `handle`, `displayName?`, `avatar: URL?`, `labels: [Label]`. The custom `init(from:)` treats absent `labels` as `[]`.

### `ProfileView`

Profile view with bio and viewer state, used in follow lists and search results. Adds `description?`, `indexedAt?`, and `viewer: ProfileViewerState?`.

### `ProfileDetailed`

Full profile returned by `app.bsky.actor.getProfile`. Adds `banner: URL?`, `followersCount`, `followsCount`, `postsCount`, and `createdAt?`. All count fields default to `0` when absent.

### `ProfileViewerState`

Relationship between the authenticated viewer and another account.

| Field | Notes |
|---|---|
| `muted: Bool?` | Whether the viewer has muted this account. |
| `mutedByList: ListBasic?` | The moderation list responsible for the mute, if any. |
| `blockedBy: Bool?` | Whether the other account has blocked the viewer. |
| `blocking: ATURI?` | AT-URI of the viewer's block record. |
| `following: ATURI?` | AT-URI of the viewer's follow record. |
| `followedBy: ATURI?` | AT-URI of the other account's follow record for the viewer. |

### `ListBasic`

Lightweight list reference used in viewer state and moderation contexts. Fields: `uri`, `cid`, `name`, `purpose` (modlist or curatelist string), `avatar?`, `labels`.

---

## Graph

**File:** `Sources/BlueskyCore/Graph.swift`

### Relationship records

`FollowRecord` and `BlockRecord` are encodable AT Protocol records (`app.bsky.graph.follow` and `app.bsky.graph.block`). Both embed `$type` and serialize the subject DID as a plain string. `MuteActorRequest` is the request body for `app.bsky.graph.muteActor`.

### Graph response types

| Type | Endpoint |
|---|---|
| `GetFollowersResponse` | `app.bsky.graph.getFollowers` |
| `GetFollowsResponse` | `app.bsky.graph.getFollows` |
| `GetMutesResponse` | `app.bsky.graph.getMutes` |
| `GetBlocksResponse` | `app.bsky.graph.getBlocks` |
| `GetListsResponse` | `app.bsky.graph.getLists` |
| `GetListFeedResponse` | `app.bsky.feed.getListFeed` |

All include a `cursor: Cursor?` for pagination.

### List types

`ListRecord` is the encodable record for creating a list via `com.atproto.repo.createRecord`. `ListItemRecord` creates a list membership entry. `ListView` is the full list view returned by the API, including `creator: ProfileView`, `purpose`, and `labels`.

---

## Moderation

**File:** `Sources/BlueskyCore/Moderation.swift`

### `Label`

An `app.bsky.label.defs#label` applied to a record or account by a labeler service.

| Field | Notes |
|---|---|
| `src: DID` | DID of the labeler that issued the label. |
| `uri: String` | AT-URI of the labeled record, or a DID string for account-level labels. |
| `val: String` | Label value, e.g. `"porn"`, `"gore"`, `"!warn"`. |
| `neg: Bool?` | `true` if this label negates a previously applied label. |
| `cts: Date` | Creation timestamp. |

### Report types

`ReportSubjectRepo` and `ReportSubjectRecord` are two `Encodable` subject types for content reports. Each encodes a `$type` discriminator (`com.atproto.admin.defs#repoRef` and `com.atproto.repo.strongRef` respectively). `CreateReportRequest` uses `AnyEncodable` to hold either subject type. `CreateReportResponse` carries the server-assigned report `id`.

### `GetListResponse` / `ListItemView`

`GetListResponse` (also in Moderation.swift) is returned by `app.bsky.graph.getList` and pairs the `ListView` header with its `[ListItemView]` members and cursor.

### Preferences and actor preferences

`ContentLabelPref` carries a label string, visibility string, and optional labeler DID. `SavedFeed` models an `app.bsky.actor.defs#savedFeed` entry with `type` (`"feed"`, `"list"`, or `"timeline"`), `value` (AT-URI or `"following"`), and `pinned` flag.

`GetPreferencesResponse` decodes the heterogeneous `preferences` array from `app.bsky.actor.getPreferences` into three typed fields: `adultContentEnabled`, `contentLabels`, and `savedFeeds`. `PutPreferencesRequest` encodes those same preferences back, using private `_AdultPref`, `_LabelPref`, and `_SavedFeedsPrefV2` helpers.

### Labeler types

`LabelerView` represents an `app.bsky.labeler.defs#labelerView` with `creator: ProfileView`, `likeCount?`, and `labels`. `GetLabelerServicesResponse` wraps an array of them.

---

## Chat

**File:** `Sources/BlueskyCore/Chat.swift`

### `ConvoView`

A conversation returned by `chat.bsky.convo.listConvos` and `chat.bsky.convo.getConvo`. Fields: `id`, `rev` (revision string), `members: [ProfileBasic]`, `lastMessage: MessageView?`, `unreadCount`, `muted`.

### `MessageView`

A message as returned in convo views and message histories. Fields: `id`, `rev`, `text`, `embed: EmbedView?`, `sender: MessageSender`, `sentAt`.

### `MessageSender`

Carries only the sender `DID`, matching the `chat.bsky.convo.defs#messageSender` lexicon definition.

### Request/response types

| Type | Purpose |
|---|---|
| `ListConvosResponse` | `chat.bsky.convo.listConvos` |
| `GetMessagesResponse` | `chat.bsky.convo.getMessages` |
| `MessageInput` | Message body for `sendMessage` (text + optional embed). |
| `SendMessageRequest` | `chat.bsky.convo.sendMessage` (convoId + message). |
| `ConvoIDRequest` | Generic request carrying only `convoId` (leave, mute, unmute). |
| `ConvoResponse` | Generic response wrapping a single `ConvoView`. |
| `UpdateReadRequest` | `chat.bsky.convo.updateRead` (convoId + optional messageId). |

---

## Search

**File:** `Sources/BlueskyCore/Search.swift`

| Type | Endpoint | Returns |
|---|---|---|
| `SearchActorsResponse` | `app.bsky.actor.searchActors` | `[ProfileView]` + cursor |
| `SearchActorsTypeaheadResponse` | `app.bsky.actor.searchActorsTypeahead` | `[ProfileBasic]` |
| `GetSuggestionsResponse` | `app.bsky.actor.getSuggestions` | `[ProfileView]` + cursor |
| `SearchPostsResponse` | `app.bsky.feed.searchPosts` | `[PostView]` + cursor + `hitsTotal?` |
| `GetSuggestedFeedsResponse` | `app.bsky.feed.getSuggestedFeeds` | `[GeneratorView]` + cursor |

---

## Notifications

**File:** `Sources/BlueskyCore/Notification.swift`

### `NotificationView`

A single notification entry from `app.bsky.notification.listNotifications`.

| Field | Notes |
|---|---|
| `uri` / `cid` | Identifies the notification record. |
| `author: ProfileBasic` | The account that triggered the notification. |
| `reason: String` | Kind: `like`, `repost`, `follow`, `mention`, `reply`, `quote`, `starterpack-joined`, `verified`, etc. |
| `reasonSubject: ATURI?` | AT-URI of the subject that triggered the notification (e.g. the liked post). |
| `isRead: Bool` | Whether the notification has been seen by the user. |
| `indexedAt: Date` | Server-side indexing timestamp. |
| `labels: [Label]` | Moderation labels on the notification. |

### Other notification types

| Type | Purpose |
|---|---|
| `ListNotificationsResponse` | Wraps `[NotificationView]` + cursor + `seenAt?` + `priority?`. |
| `UpdateSeenRequest` | Body for `app.bsky.notification.updateSeen` (marks all notifications as seen up to `seenAt`). |
| `GetUnreadCountResponse` | Response for `app.bsky.notification.getUnreadCount`, contains `count: Int`. |
| `RegisterPushRequest` | Body for `app.bsky.notification.registerPush` — device token, platform (`"ios"`/`"android"`), and app bundle ID. |

---

## Pagination

**File:** `Sources/BlueskyCore/Pagination.swift`

### `Cursor`

An opaque server-side pagination cursor.

```swift
public typealias Cursor = String
```

### `PagedResult<T>`

A generic page of items from a cursor-paginated endpoint. `cursor` is `nil` when there are no more pages.

```swift
public struct PagedResult<T: Sendable>: Sendable {
    public let items: [T]
    public let cursor: Cursor?
}
```

This type is used by higher-level modules to standardize paginated results. The raw API response types (e.g. `FeedResponse`, `GetFollowersResponse`) carry their own `cursor` directly because they must match the lexicon JSON shape exactly.

---

## Rich Text

**File:** `Sources/BlueskyCore/RichText.swift`

### `RichTextFacet`

A byte-range annotation on post text, carrying a `ByteSlice` (UTF-8 `byteStart`/`byteEnd` positions) and an array of `FacetFeature` values. Byte offsets match the raw UTF-8 encoding of the post text, not Swift character indices.

### `FacetFeature`

A discriminated `enum` decoded from `$type`:

| Case | `$type` | Payload |
|---|---|---|
| `.mention(did:)` | `app.bsky.richtext.facet#mention` | `DID` of the mentioned user. |
| `.link(uri:)` | `app.bsky.richtext.facet#link` | Raw URI string. |
| `.tag(tag:)` | `app.bsky.richtext.facet#tag` | Hashtag string (without `#`). |
| `.unknown(String)` | anything else | The raw `$type` string, preserved for forward compatibility. |

---

## Embeds

**File:** `Sources/BlueskyCore/Embed.swift`

Two parallel discriminated enum hierarchies exist: one for outgoing post records (`Embed`) and one for resolved API views (`EmbedView`).

### Shared helpers

`AspectRatio` carries `width` and `height` integers. `BlobRef` wraps an IPLD CID stored as `{ "ref": { "$link": "<cid>" }, "mimeType": "...", "size": N }` — the custom `Codable` handles the nested `$link` encoding transparently.

### Embed payload types (stored in records)

| Type | Purpose |
|---|---|
| `EmbedImage` | A single image: `BlobRef` + alt text + optional `AspectRatio`. |
| `EmbedExternal` | A link card: URI, title, description, optional thumbnail `BlobRef`. |
| `EmbedVideo` | A video blob with optional captions and aspect ratio. |
| `VideoCaption` | A language code + subtitle file `BlobRef`. |
| `EmbedRecordRef` | A `{uri, cid}` reference to a quoted post. |

### `Embed`

The `indirect enum` attached to outgoing `PostRecord` values, identified by `$type`. Cases: `.images([EmbedImage])`, `.external(EmbedExternal)`, `.record(EmbedRecordRef)`, `.recordWithMedia(record:media:)`, `.video(EmbedVideo)`, `.unknown(String)`.

### EmbedView types (resolved views in API responses)

| Type | Purpose |
|---|---|
| `EmbedImageView` | Resolved image with `thumb` and `fullsize` CDN URLs. |
| `EmbedExternalView` | Resolved link card with optional `thumb: URL`. |
| `EmbedVideoView` | Resolved video with HLS `playlist: URL` and optional `thumbnail: URL`. |
| `EmbedViewRecord` | A fully resolved quoted post, including author and `PostRecord` value. |
| `EmbedRecordContent` | Discriminated enum: `.post(EmbedViewRecord)`, `.notFound(uri:)`, `.blocked(uri:)`, `.unknown`. |
| `EmbedRecordView` | Thin wrapper carrying `record: EmbedRecordContent`. |

### `EmbedView`

The `indirect enum` returned inside `PostView`, mirroring `Embed` but using view types. Cases: `.images([EmbedImageView])`, `.external(EmbedExternalView)`, `.record(EmbedRecordView)`, `.recordWithMedia(record:media:)`, `.video(EmbedVideoView)`, `.unknown(String)`.

---

## Feed Generators

**File:** `Sources/BlueskyCore/FeedGenerator.swift`

### `GeneratorView`

A custom feed ("algorithmic feed") as returned by the API. Key fields include `did: DID` (the feed generator service DID, distinct from the creator's DID), `creator: ProfileView`, `displayName`, `likeCount?`, `acceptsInteractions?`, `viewer: GeneratorViewerState?`, and `labels`.

### `GeneratorViewerState`

Carries only `like: ATURI?` — the AT-URI of the viewer's like record for this feed generator.

### Response types

`GetFeedGeneratorsResponse` wraps `[GeneratorView]` for bulk fetch. `GetActorFeedsResponse` adds a `cursor` for paginated retrieval of a user's created feeds.

---

## Starter Packs

**File:** `Sources/BlueskyCore/StarterPack.swift`

### `StarterPackView`

Full view of a starter pack returned by `app.bsky.graph.getStarterPack`. Contains `creator: ProfileBasic`, an optional backing `list: ListBasic`, `listItemsSample: [ListItemView]?`, `feeds: [GeneratorView]?`, join counts, and `labels`.

### `StarterPackBasic`

Lightweight reference used in actor-level listings (`getActorStarterPacks`). Carries only `name`, `creator`, item count, and join counts — no list or feed details.

### `StarterPackRecord`

The encodable repo record for creating a starter pack. Embeds `$type = "app.bsky.graph.starterpack"` and stores the backing list as an AT-URI string.

---

## Repo and Utility Types

**File:** `Sources/BlueskyCore/Repo.swift`

### `AnyEncodable`

A type-erased `Encodable & Sendable` wrapper used where a heterogeneous array of encodable values must be stored in a concrete type (e.g. `PutPreferencesRequest.preferences`, `CreateReportRequest.subject`).

```swift
public struct AnyEncodable: Encodable, Sendable {
    public init<T: Encodable & Sendable>(_ value: T)
}
```

### Blob upload

`UploadBlobResponse` wraps a single `BlobRef` — the response from `com.atproto.repo.uploadBlob`.

### Apply-writes types

`WriteCreate` and `WriteDelete` represent individual write operations for `com.atproto.repo.applyWrites`. Both embed `$type` in their encoded output. `WriteOp` is a union enum of the two. `ApplyWritesRequest` takes a `DID` repo and an array of `WriteOp`. `ApplyWritesResponse` optionally returns a `RepoCommit` (CID + rev) on success.

---

## Contacts

**File:** `Sources/BlueskyCore/Contacts.swift`

Types for the `app.bsky.contact.*` phone-contact import flow: `StartPhoneVerificationRequest`, `VerifyPhoneRequest/Response` (returns a token), `ImportContactsRequest/Response` (takes the token + contact list, returns match indexes), `GetContactMatchesResponse` (paginated `[ProfileBasic]`), `ContactSyncStatus`, and `DismissMatchRequest`.

---

## Cache Support

**File:** `Sources/BlueskyCore/Cache.swift`

### `CacheResult<T>`

Pairs a cached value with its freshness status. Defined in `BlueskyCore` (not `BlueskyKit`) specifically so it can be constructed and accessed from background networking tasks without triggering `@MainActor` isolation requirements.

```swift
public struct CacheResult<T: Sendable>: Sendable {
    public let value: T
    /// true when the entry's TTL has elapsed since it was stored.
    public let isExpired: Bool
}
```

The stale-while-revalidate pattern: callers display `value` immediately, then start a background refresh if `isExpired` is `true`.

---

## Errors

**File:** `Sources/BlueskyCore/ATError.swift`

`ATError` is the unified error type thrown by all BlueskyKit network and storage operations.

```swift
public enum ATError: Error, Sendable {
    case network(URLError)
    case httpStatus(Int)
    case unauthenticated
    case sessionExpired
    case authFactorTokenRequired
    case xrpc(code: String, message: String)
    case decodingFailed(String)
    case unknown(String)
}
```

| Case | When thrown |
|---|---|
| `.network(URLError)` | A transport-level URL error (no connection, timeout, etc.). |
| `.httpStatus(Int)` | An unexpected HTTP status code — not a 200 or a well-formed XRPC 4xx. |
| `.unauthenticated` | No session is active; the user must log in. |
| `.sessionExpired` | The access token expired and the refresh token is also invalid. |
| `.authFactorTokenRequired` | The server requires a TOTP factor token before completing login. |
| `.xrpc(code:message:)` | The server returned an XRPC error envelope — `code` is the XRPC error name (e.g. `"InvalidToken"`), `message` is human-readable. |
| `.decodingFailed(String)` | The response payload could not be decoded; carries a description. |
| `.unknown(String)` | Any other error; carries a human-readable description. |
