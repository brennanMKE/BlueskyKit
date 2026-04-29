# BlueskyProfile

`BlueskyProfile` is a SwiftUI module that renders a full user profile screen, handles follow/unfollow/block/mute actions with optimistic UI updates, and exposes an edit-profile sheet. It depends on `BlueskyKit`, `BlueskyCore`, and `BlueskyUI`.

## Dependencies

| Module | Role |
|--------|------|
| `BlueskyKit` | `NetworkClient`, `AccountStore` protocols |
| `BlueskyCore` | `DID`, `ATURI`, `ProfileDetailed`, `ProfileViewerState`, `FeedViewPost` value types |
| `BlueskyUI` | `AvatarView`, `PostCard` shared components |

---

## ProfileTab

An enum that drives both the segmented tab strip and the per-tab feed cache inside `ProfileStore`.

```swift
public enum ProfileTab: String, CaseIterable, Identifiable {
    case posts, replies, media, likes
}
```

| Case | AT Proto filter / endpoint |
|------|---------------------------|
| `.posts` | `app.bsky.feed.getAuthorFeed` with `filter=posts_no_replies` |
| `.replies` | `app.bsky.feed.getAuthorFeed` with `filter=posts_with_replies` |
| `.media` | `app.bsky.feed.getAuthorFeed` with `filter=posts_with_media` |
| `.likes` | `app.bsky.feed.getActorLikes` |

---

## ProfileScreen

`ProfileScreen` is the top-level `View` for a Bluesky profile. It owns a `ProfileViewModel` and composes `ProfileHeaderView`, a segmented tab strip, and a paginating post feed.

### Initializer

```swift
public struct ProfileScreen: View {
    public init(
        actorDID: DID,
        network: any NetworkClient,
        accountStore: any AccountStore,
        viewerDID: DID? = nil
    )
}
```

`viewerDID` is the currently signed-in user's DID. When it matches `actorDID`, the header shows an "Edit Profile" button instead of follow/block/mute controls.

### Layout

The screen is a single `ScrollView` with a `LazyVStack` whose section header is pinned. The pinned header contains:

1. `ProfileHeaderView` — banner, avatar, action buttons, display name, bio, stats.
2. A segmented `Picker` bound to `selectedTab`.

Feed items beneath the header are rendered as `PostCard` rows separated by `Divider` views. Infinite scroll is triggered when the last visible row appears on screen.

### Lifecycle

| Event | Action |
|-------|--------|
| `.task` | Calls `viewModel.loadProfile()` then `viewModel.loadFeed(tab:)` for the initial tab. |
| `.onChange(of: selectedTab)` | Calls `viewModel.loadFeed(tab:)` for the newly selected tab. |
| Last row `.onAppear` | Calls `viewModel.loadMoreFeed(tab:)` to fetch the next page. |

### Post tap navigation

Tapping a `PostCard` sets `threadURI` to the post's AT-URI. A `navigationDestination` binding presents a `ThreadPlaceholder` view (a stub that avoids a circular dependency on `BlueskyFeed`).

### Edit profile sheet

When `showEditProfile` is `true`, an `EditProfileSheet` is presented as a modal sheet. On save, the sheet invokes `viewModel.updateProfile(displayName:description:)` inside a detached `Task`.

---

## ProfileStore

`ProfileStore` is an `@Observable` class that owns all network I/O for a profile screen. It is never held directly by views; views interact through `ProfileViewModel`.

### Protocol

```swift
public protocol ProfileStoring: AnyObject, Observable, Sendable {
    var profile: ProfileDetailed? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func posts(for tab: ProfileTab) -> [FeedViewPost]
    func isLoadingFeed(for tab: ProfileTab) -> Bool

    func loadProfile(actorDID: DID) async
    func loadFeed(tab: ProfileTab, actorDID: DID) async
    func loadMoreFeed(tab: ProfileTab, actorDID: DID) async
    func follow() async
    func unfollow() async
    func block() async
    func unblock() async
    func mute() async
    func unmute() async
    func updateProfile(displayName: String?, description: String?) async throws
}
```

### Per-tab feed cache

The store keeps three private dictionaries keyed by `ProfileTab`:

- `tabPosts: [ProfileTab: [FeedViewPost]]` — accumulated post pages.
- `tabCursors: [ProfileTab: String?]` — AT Proto pagination cursors.
- `tabLoading: [ProfileTab: Bool]` — per-tab loading flags.

`loadFeed` is a no-op if a tab's posts have already been fetched (`tabPosts[tab] != nil`). `loadMoreFeed` is a no-op when there is no cursor remaining (end of feed).

### Optimistic mutations

Follow, unfollow, block, unblock, mute, and unmute all apply an optimistic state update to `profile` before the network call. If the call throws, the original snapshot is restored.

#### Follow optimistic pattern

```swift
let original = self.profile
let pendingURI = ATURI(rawValue: "pending:follow")
self.profile = profile
    .adjustingFollowersCount(by: 1)
    .withViewer { v in ProfileViewerState(following: pendingURI, ...) }
do {
    let resp: CreateRecordResponse = try await network.post(...)
    self.profile = profile.withViewer { v in ProfileViewerState(following: resp.uri, ...) }
} catch {
    self.profile = original
}
```

The same rollback pattern applies to unfollow (`adjustingFollowersCount(by: -1)`), block/unblock, and mute/unmute.

### AT Proto lexicons used

| Action | Lexicon |
|--------|---------|
| Fetch profile | `app.bsky.actor.getProfile` |
| Posts / replies / media | `app.bsky.feed.getAuthorFeed` |
| Likes | `app.bsky.feed.getActorLikes` |
| Follow | `com.atproto.repo.createRecord` (collection `app.bsky.graph.follow`) |
| Unfollow | `com.atproto.repo.deleteRecord` |
| Block | `com.atproto.repo.createRecord` (collection `app.bsky.graph.block`) |
| Unblock | `com.atproto.repo.deleteRecord` |
| Mute | `app.bsky.graph.muteActor` |
| Unmute | `app.bsky.graph.unmuteActor` |
| Update profile | `com.atproto.repo.putRecord` (collection `app.bsky.actor.profile`, rkey `self`) |

After `updateProfile` succeeds, the store immediately calls `loadProfile(actorDID:)` to refresh the cached profile.

---

## ProfileViewModel

`ProfileViewModel` is a thin `@Observable` wrapper that binds a specific `actorDID` to a `ProfileStoring` instance. Views hold the view model; the view model forwards all calls to the store, supplying `actorDID` automatically.

```swift
@Observable
public final class ProfileViewModel {
    public let actorDID: DID
    public var profile: ProfileDetailed?     // forwarded from store
    public var isLoading: Bool               // forwarded from store
    public var errorMessage: String?         // forwarded from store

    public func posts(for tab: ProfileTab) -> [FeedViewPost]
    public func isLoadingFeed(for tab: ProfileTab) -> Bool

    public func loadProfile() async
    public func loadFeed(tab: ProfileTab) async
    public func loadMoreFeed(tab: ProfileTab) async
    public func follow() async
    public func unfollow() async
    public func block() async
    public func unblock() async
    public func mute() async
    public func unmute() async
    public func updateProfile(displayName: String?, description: String?) async throws
}
```

`ProfileScreen` creates the view model via `@State` so it persists for the lifetime of the screen.

---

## ProfileHeaderView

`ProfileHeaderView` is a reusable `View` that renders all visual chrome above the tab strip. It is stateless: all actions are injected as closures.

### Initializer

```swift
public struct ProfileHeaderView: View {
    public init(
        profile: ProfileDetailed?,
        isOwnProfile: Bool,
        onFollow: @escaping () -> Void,
        onUnfollow: @escaping () -> Void,
        onBlock: @escaping () -> Void,
        onUnblock: @escaping () -> Void,
        onMute: @escaping () -> Void,
        onUnmute: @escaping () -> Void,
        onEditProfile: @escaping () -> Void
    )
}
```

### Visual regions

| Region | Notes |
|--------|-------|
| Banner | 130 pt tall `AsyncImage`. Falls back to a semi-transparent rectangle placeholder when no banner URL is set. |
| Avatar | 72 pt `AvatarView` with a white ring border, offset upward by 24 pt to overlap the banner. |
| Action buttons | Shown to the right of the avatar. Own profile: "Edit Profile" (`.bordered`). Other profile: "Following" / "Follow" button plus a `Menu` for block/unblock and mute/unmute. |
| Display name | `.title3 .bold`. Shows `displayName` if set; falls back to the handle. |
| Handle | `@handle` in secondary color. |
| Bio | Shown only when `description` is non-empty. |
| Stats row | Following count, Followers count, Posts count in a horizontal row. |

The follow button uses `.borderedProminent` style when not following and `.bordered` when already following. Block and mute entries live in an ellipsis `Menu` with destructive role applied to block/unblock only.

---

## EditProfileSheet

`EditProfileSheet` is a modal `NavigationStack` form for editing display name and bio. It accepts the current values as initializer arguments and calls an `onSave` closure on confirmation.

### Initializer

```swift
public struct EditProfileSheet: View {
    public init(
        displayName: String,
        description: String,
        onSave: @escaping (String, String) -> Void
    )
}
```

### Fields

| Field | Control | Notes |
|-------|---------|-------|
| Display name | `TextField` | Plain text; no character limit enforced in the view. |
| Bio | `TextEditor` | Minimum height 80 pt. |

### Save behavior

Tapping "Save" sets `isSaving = true`, calls `onSave(displayName, description)`, and immediately dismisses the sheet. The "Save" toolbar button is disabled while `isSaving` is `true` to prevent double-submission. Tapping "Cancel" dismisses without calling `onSave`.

The actual network call is fired by `ProfileScreen` inside a `Task`:

```swift
onSave: { name, desc in
    Task { try? await viewModel.updateProfile(displayName: name, description: desc) }
}
```

---

## Usage example

```swift
import BlueskyProfile

// Inside a NavigationStack:
ProfileScreen(
    actorDID: targetDID,
    network: networkClient,
    accountStore: accountStore,
    viewerDID: session.currentDID
)
```

To show the viewer's own profile, pass the same DID for both `actorDID` and `viewerDID`. The header will render "Edit Profile" instead of follow/block controls.
