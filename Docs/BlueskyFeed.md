# BlueskyFeed

`BlueskyFeed` is a Swift module that delivers all feed-reading and content-browsing screens for the Bluesky client. It owns the full timeline experience: fetching posts from network feeds, displaying threads, surfacing saved feeds, browsing a video-only scroll, and managing bookmarked posts.

## Dependencies

| Dependency | Role |
|---|---|
| `BlueskyKit` | Protocol contracts — `SessionManaging`, `NetworkClient`, `AccountStore` |
| `BlueskyCore` | Shared value types — `Post`, `Profile`, `Embed`, `CursorPage`, identifiers |
| `BlueskyUI` | Reusable presentational components — `PostCard`, `FeedCard`, `AvatarView`, etc. |

`BlueskyFeed` has no direct dependency on `BlueskyDataStore` or `BlueskyAuth`; concrete implementations are injected at the app-target level.

---

## Architecture

`BlueskyFeed` follows a strict three-layer pattern for every screen:

```
Store  ──(async throws)──>  ViewModel  ──(@Published)──>  View
```

### Store layer

Stores perform all network I/O. Each store is a Swift `actor` (or an `@MainActor final class` where the protocol requires it) that exposes `async throws` methods. Stores hold no SwiftUI state. Their single responsibility is loading, refreshing, and paginating data from the AT Protocol network via `NetworkClient`.

### ViewModel layer

ViewModels are `@MainActor @Observable` (or `ObservableObject`) classes. They own all published UI state (`posts`, `isLoading`, `errorMessage`, `hasMore`). A ViewModel holds a reference to its Store and calls store methods inside `Task { }` blocks, funnelling results onto the main actor. ViewModels contain no `URLSession` calls and no raw `Decodable` decoding.

### View layer

Views are purely declarative SwiftUI structs. They receive a ViewModel as an `@State` or `@StateObject` dependency. Views never call network APIs directly; they call ViewModel intent methods (`loadFeed()`, `refresh()`, `loadMore()`).

---

## Stores

### FeedStore

`Sources/BlueskyFeed/FeedStore.swift`

Responsible for fetching the home timeline and any algorithm/generator-based feed. Key responsibilities:

- Calls the AT Protocol `app.bsky.feed.getTimeline` and `app.bsky.feed.getFeed` endpoints via `NetworkClient`.
- Returns a `CursorPage<Post>` on each call so the ViewModel can append pages.
- Accepts an optional `cursor` parameter for pagination; `nil` cursor fetches the first page.
- Stateless between calls — the cursor is owned by the ViewModel.

```swift
actor FeedStore {
    func fetchTimeline(cursor: String?) async throws -> CursorPage<Post>
    func fetchFeed(uri: String, cursor: String?) async throws -> CursorPage<Post>
}
```

### ThreadStore

`Sources/BlueskyFeed/ThreadStore.swift`

Loads a single post thread (the root post, its parents, and its replies).

- Calls `app.bsky.feed.getPostThread`.
- Returns a `ThreadNode` tree that `ThreadViewModel` flattens into a displayable list.
- Caches the last-fetched thread in memory for fast back-navigation.

```swift
actor ThreadStore {
    func fetchThread(uri: String) async throws -> ThreadNode
}
```

### SavedFeedsStore

`Sources/BlueskyFeed/SavedFeedsStore.swift`

Manages the user's pinned and saved feed generators.

- Calls `app.bsky.actor.getPreferences` to retrieve the saved-feeds preference item.
- Calls `app.bsky.feed.getFeedGenerators` to resolve generator records for display.
- Exposes a `reorder` method that writes updated preferences back via `app.bsky.actor.putPreferences`.

```swift
actor SavedFeedsStore {
    func fetchSavedFeeds() async throws -> [FeedGenerator]
    func reorder(pinned: [String], saved: [String]) async throws
}
```

### BookmarksStore

`Sources/BlueskyFeed/BookmarksStore.swift`

Manages locally bookmarked posts. Bookmarks are stored on-device (not in the AT Protocol graph) and synced lazily.

- Persists bookmark records to a local store (injected via a `BookmarkPersisting` protocol).
- Exposes `addBookmark(post:)` and `removeBookmark(uri:)`.
- `fetchBookmarks()` loads the local list and then resolves any posts whose content has been evicted by calling `app.bsky.feed.getPosts`.

```swift
actor BookmarksStore {
    func fetchBookmarks() async throws -> [Post]
    func addBookmark(post: Post) async throws
    func removeBookmark(uri: String) async throws
}
```

---

## ViewModels

### FeedViewModel

`Sources/BlueskyFeed/FeedViewModel.swift`

Mediates between `FeedStore` and `FeedView` / `FeedSwitcherView`.

Published state:

| Property | Type | Description |
|---|---|---|
| `posts` | `[Post]` | Accumulated pages of feed items |
| `isLoading` | `Bool` | True while the first page is in flight |
| `isLoadingMore` | `Bool` | True while a subsequent page is in flight |
| `errorMessage` | `String?` | Surface-level error text for the UI |
| `hasMore` | `Bool` | Whether a next-page cursor is available |

Intent methods: `loadFeed()`, `refresh()`, `loadMore()`.

On `loadFeed()` / `refresh()` the ViewModel resets `cursor` to `nil`, clears `posts`, and fetches a fresh first page. On `loadMore()` it passes the stored cursor to `FeedStore` and appends the result.

### ThreadViewModel

`Sources/BlueskyFeed/ThreadViewModel.swift`

Wraps `ThreadStore`. Flattens the `ThreadNode` tree into a flat `[ThreadItem]` array (parent chain first, then the focused post, then replies) for display in a `List`.

```swift
@MainActor @Observable final class ThreadViewModel {
    var items: [ThreadItem] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil

    func load(uri: String) async
}
```

### SavedFeedsViewModel

`Sources/BlueskyFeed/SavedFeedsViewModel.swift`

Wraps `SavedFeedsStore`. Exposes `pinnedFeeds` and `savedFeeds` arrays. Provides `move(from:to:)` and `pin(uri:)` / `unpin(uri:)` helpers that call through to the store and optimistically update local state.

### BookmarksViewModel

`Sources/BlueskyFeed/BookmarksViewModel.swift`

Wraps `BookmarksStore`. Exposes `bookmarks: [Post]` and `isEmpty: Bool`. Provides `add(post:)` and `remove(uri:)` intent methods that keep the local list in sync with the store.

---

## Views and Screens

### FeedView

`Sources/BlueskyFeed/FeedView.swift`

The primary timeline screen. Displays a scrollable `List` of `PostCard` rows driven by `FeedViewModel`.

Key behaviours:

- Triggers `loadFeed()` on `task {}` at first appearance.
- Provides pull-to-refresh via `.refreshable`.
- Appends the next page when the last visible row appears (using an `onAppear` sentinel).
- Shows a full-screen `ProgressView` on the initial load and an inline spinner row at the bottom during pagination.
- Errors surface as an inline `ErrorBanner` with a retry button.

```swift
struct FeedView: View {
    @State private var viewModel: FeedViewModel

    init(store: FeedStore) {
        _viewModel = State(wrappedValue: FeedViewModel(store: store))
    }
}
```

### FeedSwitcherView

`Sources/BlueskyFeed/FeedSwitcherView.swift`

A segmented tab bar at the top of the feed column that lets the user switch between the home timeline and any pinned feed generator. Internally it holds a `selectedFeedURI: String?` (`nil` = timeline) and re-initialises `FeedViewModel` when the selection changes.

The switcher reads pinned feeds from `SavedFeedsViewModel` so the tab list stays in sync with the user's preferences without a separate network call.

### ThreadView

`Sources/BlueskyFeed/ThreadView.swift`

Displays a single post thread. The focused post is visually distinguished (larger text, full timestamp, engagement counts). Parent posts appear above in a chain; replies are listed below.

- Receives a `postURI: String` and constructs a `ThreadViewModel` on init.
- Uses `ThreadViewModel.load(uri:)` inside `task {}`.
- Renders each `ThreadItem` as a `PostCard`, using the item's `role` property (`.parent`, `.focus`, `.reply`) to select the appropriate display variant.

### SavedFeedsScreen

`Sources/BlueskyFeed/SavedFeedsScreen.swift`

A settings-style list screen for managing pinned and saved feed generators. Divided into two sections — **Pinned** and **Saved** — each backed by the corresponding array in `SavedFeedsViewModel`.

- Supports drag-to-reorder within the pinned section via `List` `onMove`, which calls `viewModel.move(from:to:)`.
- Each row shows a `FeedCard` (from `BlueskyUI`) with a pin/unpin toggle button.
- Calls `SavedFeedsViewModel.fetchSavedFeeds()` on appear.

### VideoFeedView

`Sources/BlueskyFeed/VideoFeedView.swift`

A vertical paging scroll that presents only posts containing video embeds, styled as a full-screen media viewer (similar to a short-form video feed). It reuses `FeedViewModel` with a dedicated video-only feed URI.

- Each page is a single `PostEmbedView` (video variant) overlaid with a semi-transparent `PostCard` metadata strip.
- `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))` drives the paging.
- Autoplay is triggered by the page becoming visible via `onAppear`; the previous page is paused.

### BookmarksScreen

`Sources/BlueskyFeed/BookmarksScreen.swift`

Displays the user's locally bookmarked posts in a scrollable list.

- Uses `BookmarksViewModel` to drive the list.
- Shows an empty-state illustration and prompt when `viewModel.isEmpty`.
- Supports swipe-to-delete (calls `viewModel.remove(uri:)`).
- Each row is a standard `PostCard`.

---

## Data-flow summary

```
App target
  └── injects NetworkClient, SessionManager
        └── FeedStore / ThreadStore / SavedFeedsStore / BookmarksStore
              └── FeedViewModel / ThreadViewModel / ...
                    └── FeedView / ThreadView / ...  (all BlueskyUI components)
```

No view has knowledge of `URLSession`, HTTP headers, or AT Protocol XRPC method names. All of that lives in the store layer.

---

## Error handling

Stores `throw` errors typed as `BlueskyError` (from `BlueskyCore`). ViewModels catch errors in their `Task` blocks and write a user-facing string to `errorMessage`. Views observe `errorMessage` and present it inline; they do not catch or inspect raw errors.

---

## Pagination contract

Every paginated store method returns `CursorPage<T>`:

```swift
struct CursorPage<T> {
    let items: [T]
    let cursor: String?   // nil when the last page has been reached
}
```

ViewModels track `cursor: String?` locally. When `cursor` is `nil` after a fetch, `hasMore` is set to `false` and further `loadMore()` calls are no-ops.
