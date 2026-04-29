# BlueskySearch

`BlueskySearch` is a SwiftUI module that provides a type-ahead search screen covering three result categories: people, posts, and feeds. When the query field is empty the screen shows actor suggestions fetched on first load. It depends on `BlueskyKit`, `BlueskyCore`, and `BlueskyUI`.

## Dependencies

| Module | Role |
|--------|------|
| `BlueskyKit` | `NetworkClient` protocol |
| `BlueskyCore` | `ProfileView`, `PostView`, `GeneratorView`, `FeedViewPost` value types |
| `BlueskyUI` | `AvatarView`, `PostCard`, `FeedCard` shared components |

---

## SearchTab

An enum that controls which result set is displayed and which endpoint is called.

```swift
public enum SearchTab: String, CaseIterable, Identifiable {
    case people, posts, feeds
}
```

| Case | AT Proto endpoint |
|------|------------------|
| `.people` | `app.bsky.actor.searchActors` |
| `.posts` | `app.bsky.feed.searchPosts` |
| `.feeds` | `app.bsky.feed.getSuggestedFeeds` |

---

## SearchScreen

`SearchScreen` is the top-level `View`. It owns a `SearchViewModel` and switches its body based on whether the query field is empty.

### Initializer

```swift
public struct SearchScreen: View {
    public init(
        network: any NetworkClient,
        onActorTap: ((ProfileView) -> Void)? = nil,
        onPostTap: ((PostView) -> Void)? = nil
    )
}
```

Navigation callbacks are optional closures injected by the host. The screen itself does not perform navigation; it delegates taps upward.

### Layout modes

#### Empty query — suggestions

When `viewModel.query` is empty (or whitespace only), the screen shows a "Suggested" section populated from `viewModel.suggestedActors`. Each row is rendered by the private `ActorRow` view. Suggestions are loaded once on `.task` via `viewModel.loadSuggestions()`; subsequent appearances are no-ops because the store guards against refetching a non-empty list.

#### Active query — tab strip + results

When the query is non-empty, a segmented `Picker` bound to `viewModel.activeTab` appears above the result list. Changing the active tab triggers an immediate fresh search for the new tab:

```swift
.onChange(of: viewModel.activeTab) { _, _ in
    Task { await viewModel.search(fresh: true) }
}
```

Result lists are rendered in `ScrollView` / `LazyVStack` containers. Infinite scroll is triggered by `.onAppear` on the last row of each list, which calls `viewModel.loadMore()`.

### Search bar

The search bar is a custom `HStack` containing a magnifying glass icon, a `TextField`, and a clear button that appears when the query is non-empty. Three interactions trigger a search:

| Interaction | Behavior |
|-------------|----------|
| Typing in the field | `viewModel.onQueryChange()` — debounced 300 ms, fresh search |
| Pressing Return / Submit | `viewModel.search(fresh: true)` — immediate, cancels any pending debounce |
| Tapping the clear button | `viewModel.query = ""`; `viewModel.clearResults()` |

### Result rendering

| Tab | Row view | Navigation |
|-----|----------|------------|
| People | Private `ActorRow` (avatar + display name + handle + bio excerpt) | `onActorTap?(actor)` |
| Posts | `PostCard` wrapping a synthetic `FeedViewPost` | `onPostTap?(post)` |
| Feeds | `FeedCard` from `BlueskyUI` | No callback; feed tap is handled inside `FeedCard` |

An empty-state message ("No people found", "No posts found", "No feeds found") is shown when a tab's result array is empty and loading has finished.

---

## SearchStore

`SearchStore` is an `@Observable` class that owns all network I/O for the search screen.

### Protocol

```swift
public protocol SearchStoring: AnyObject, Observable, Sendable {
    var actors: [ProfileView] { get }
    var posts: [PostView] { get }
    var suggestedFeeds: [GeneratorView] { get }
    var suggestedActors: [ProfileView] { get }
    var actorsCursor: String? { get }
    var postsCursor: String? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func search(query: String, tab: SearchTab, fresh: Bool) async
    func loadSuggestions() async
    func clearResults()
}
```

### `search(query:tab:fresh:)`

The `fresh` flag controls whether existing results are replaced or appended.

When `fresh == true`:
- `actors`, `posts`, `suggestedFeeds`, `actorsCursor`, and `postsCursor` are all reset before fetching.

When `fresh == false` (pagination):
- The stored cursor for the active tab is forwarded as a `cursor` query parameter.
- New results are appended to the existing array.

The store guards against concurrent calls with `guard !isLoading`. This means rapid successive calls (such as those produced by debounce) will be silently dropped if a request is already in flight.

### Pagination cursors

People and post results each have independent cursors (`actorsCursor`, `postsCursor`). Feed results (`suggestedFeeds`) come from `getSuggestedFeeds`, which does not use cursor-based pagination in this implementation.

### `loadSuggestions()`

Calls `app.bsky.actor.getSuggestions` with `limit=20`. The guard `guard suggestedActors.isEmpty` makes this a one-shot load per store instance.

### `clearResults()`

Resets `actors`, `posts`, `suggestedFeeds`, `actorsCursor`, and `postsCursor` to their zero values. Called when the user clears the search field.

### AT Proto lexicons used

| Action | Lexicon | Limit |
|--------|---------|-------|
| Search actors | `app.bsky.actor.searchActors` | 25 per page |
| Search posts | `app.bsky.feed.searchPosts` | 25 per page |
| Search feeds | `app.bsky.feed.getSuggestedFeeds` | 25 |
| Suggestions | `app.bsky.actor.getSuggestions` | 20 |

---

## SearchViewModel

`SearchViewModel` is an `@Observable` class that sits between the view and the store. It holds the mutable UI state (`query`, `activeTab`) and owns the debounce `Task`.

```swift
@Observable
public final class SearchViewModel {
    public var query: String = ""
    public var activeTab: SearchTab = .people

    // Forwarded read-only state from store:
    public var actors: [ProfileView]
    public var posts: [PostView]
    public var suggestedFeeds: [GeneratorView]
    public var suggestedActors: [ProfileView]
    public var actorsCursor: String?
    public var postsCursor: String?
    public var isLoading: Bool
    public var errorMessage: String?
}
```

### Debounce

`onQueryChange()` cancels any pending `debounceTask` and creates a new one that sleeps 300 ms before calling `store.search(query:tab:fresh:)`. If the task is cancelled before the sleep completes (because the user typed again), no search is issued.

```swift
public func onQueryChange() {
    debounceTask?.cancel()
    let q = query
    let tab = activeTab
    debounceTask = Task {
        try? await Task.sleep(nanoseconds: 300_000_000) // 300 ms
        guard !Task.isCancelled, !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        await store.search(query: q, tab: tab, fresh: true)
    }
}
```

### Public methods

| Method | Behavior |
|--------|----------|
| `onQueryChange()` | Cancels pending debounce task and schedules a new 300 ms debounced fresh search. |
| `search(fresh:)` | Calls `store.search` immediately with the current `query` and `activeTab`. |
| `loadMore()` | Calls `store.search` with `fresh: false` to append the next page. |
| `loadSuggestions()` | Forwards to `store.loadSuggestions()`. |
| `clearResults()` | Forwards to `store.clearResults()`. |

---

## Usage example

```swift
import BlueskySearch

// Inside a NavigationStack:
SearchScreen(
    network: networkClient,
    onActorTap: { profile in
        navigator.push(ProfileScreen(
            actorDID: profile.did,
            network: networkClient,
            accountStore: accountStore
        ))
    },
    onPostTap: { post in
        navigator.push(ThreadScreen(uri: post.uri, network: networkClient))
    }
)
```

The screen manages its own `SearchViewModel` lifecycle via `@State`. A new `SearchViewModel` (and therefore a fresh `SearchStore`) is created each time `SearchScreen` is instantiated.
