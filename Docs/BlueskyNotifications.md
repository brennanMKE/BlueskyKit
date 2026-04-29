# BlueskyNotifications

`BlueskyNotifications` is a SwiftUI module that renders the notification feed for a signed-in Bluesky user. It handles likes, reposts, follows, mentions, replies, and quotes. On first load it immediately marks all notifications as seen. Pull-to-refresh and infinite scroll are supported. It depends on `BlueskyKit`, `BlueskyCore`, and `BlueskyUI`.

## Dependencies

| Module | Role |
|--------|------|
| `BlueskyKit` | `NetworkClient` protocol |
| `BlueskyCore` | `NotificationView`, `ATURI` value types |
| `BlueskyUI` | `AvatarView` shared component |

---

## NotificationsScreen

`NotificationsScreen` is the top-level `View`. It owns a `NotificationsViewModel` and presents one of three states: a full-screen loading spinner, an error view with a Retry button, or the scrollable notification list.

### Initializer

```swift
public struct NotificationsScreen: View {
    public init(
        network: any NetworkClient,
        onUnreadCountChange: ((Int) -> Void)? = nil
    )
}
```

`onUnreadCountChange` is an optional closure that fires whenever `viewModel.unreadCount` changes. The host can use this to update a badge in the app's tab bar.

### Lifecycle

| Event | Action |
|-------|--------|
| `.task` | Calls `viewModel.loadInitial()` then `viewModel.markSeen()`. |
| `.onChange(of: viewModel.unreadCount)` | Forwards the new count to `onUnreadCountChange`. |
| Pull to refresh | Calls `viewModel.refresh()` (replaces all rows). |
| Last row `.onAppear` | Calls `viewModel.loadMore()` to append the next page. |

### State switching

```
notifications.isEmpty && isLoading  →  ProgressView (full-screen)
notifications.isEmpty && errorMessage != nil  →  Error view with Retry
otherwise  →  notification List
```

The error view shows a warning icon, the error message, and a "Retry" button that calls `viewModel.refresh()`.

### Notification list

Notifications are rendered in a plain-style `List`. Each row is the private `NotificationRow` view. Row separators are hidden; rows span the full width with custom horizontal padding applied inside the row. The list uses `.refreshable` for pull-to-refresh.

### Thread navigation

Tapping a notification row sets `threadURI` to `notification.reasonSubject`. A `navigationDestination` binding pushes a text placeholder view (stub pending a `BlueskyFeed` thread screen). Only notifications that carry a `reasonSubject` URI are tappable.

### NotificationRow

`NotificationRow` is a private `View` that renders a single notification. Its layout is a horizontal stack:

```
[reason icon]  [avatar + author name + unread dot]  [relative timestamp]
               [reason text line]
```

#### Reason icons and colors

| Reason | SF Symbol | Color |
|--------|-----------|-------|
| `like` | `heart.fill` | `.pink` |
| `repost` | `arrow.2.squarepath` | `.green` |
| `follow` | `person.fill.badge.plus` | `.blue` |
| `mention` | `at` | `.secondary` |
| `reply` | `bubble.left.fill` | `.secondary` |
| `quote` | `quote.bubble.fill` | `.secondary` |
| (other) | `bell.fill` | `.secondary` |

#### Unread indicator

An 8 pt accent-color filled `Circle` appears next to the author name when `notification.isRead == false`. It disappears once `markSeen()` has been called on app entry.

#### Reason text

| Reason | Label |
|--------|-------|
| `like` | "liked your post" |
| `repost` | "reposted your post" |
| `follow` | "followed you" |
| `mention` | "mentioned you" |
| `reply` | "replied to your post" |
| `quote` | "quoted your post" |
| (other) | The raw reason string |

---

## NotificationsStore

`NotificationsStore` is an `@Observable` class that owns all network I/O for the notifications screen.

### Protocol

```swift
public protocol NotificationsStoring: AnyObject, Observable, Sendable {
    var notifications: [NotificationView] { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    var unreadCount: Int { get }

    func loadInitial() async
    func loadMore() async
    func refresh() async
    func markSeen() async
    func fetchUnreadCount() async
}
```

### `loadInitial()`

Fetches the first 50 notifications from `app.bsky.notification.listNotifications`. The guard `guard !isLoading, notifications.isEmpty` makes this a no-op if the list has already been populated. On success, `notifications` and `cursor` are set; on failure, `errorMessage` is set and the error is logged via `OSLog`.

### `loadMore()`

Appends the next page of 50 notifications using the stored `cursor`. If `cursor` is `nil` (the feed is exhausted), the call is a no-op. The cursor is updated to the value returned by the response.

### `refresh()`

Unconditional refetch: always resets `notifications` and `cursor` to the latest page, regardless of `isLoading`. Sets `errorMessage` on failure.

### `markSeen()`

Posts to `app.bsky.notification.updateSeen` with the current timestamp. On success, `unreadCount` is set to `0`. The `UpdateSeenRequest` body is constructed internally by the store.

### `fetchUnreadCount()`

Calls `app.bsky.notification.getUnreadCount` and updates `unreadCount` from the response. Intended for use by the host app on foreground transitions or push notification receipt to keep the tab badge accurate without loading the full feed.

### AT Proto lexicons used

| Action | Lexicon | Notes |
|--------|---------|-------|
| Initial load | `app.bsky.notification.listNotifications` | `limit=50` |
| Pagination | `app.bsky.notification.listNotifications` | `limit=50`, `cursor=<cursor>` |
| Refresh | `app.bsky.notification.listNotifications` | `limit=50`, no cursor |
| Mark seen | `app.bsky.notification.updateSeen` | POST; resets `unreadCount` to 0 |
| Unread count | `app.bsky.notification.getUnreadCount` | GET; used for badge updates |

### Logging

The store uses `OSLog` with category `NotificationsStore`. Network errors from `loadInitial` and `refresh` are logged at `.error` level with `privacy: .public`. Errors from `loadMore`, `markSeen`, and `fetchUnreadCount` are silently swallowed (no UI disruption on pagination or badge update failures).

---

## NotificationsViewModel

`NotificationsViewModel` is a thin `@Observable` wrapper that forwards all calls to a `NotificationsStoring` instance. Views hold the view model and never interact with the store directly.

```swift
@Observable
public final class NotificationsViewModel {
    // Forwarded read-only state:
    public var notifications: [NotificationView]
    public var isLoading: Bool
    public var errorMessage: String?
    public var unreadCount: Int

    public init(network: any NetworkClient)

    public func loadInitial() async
    public func loadMore() async
    public func refresh() async
    public func markSeen() async
    public func fetchUnreadCount() async
}
```

`NotificationsScreen` creates the view model via `@State` so it persists for the lifetime of the screen. The store is created inside `init` and held through the `NotificationsStoring` protocol, which allows substituting a mock in tests.

---

## Unread count integration

The recommended integration pattern for a tab bar badge:

```swift
NotificationsScreen(
    network: networkClient,
    onUnreadCountChange: { count in
        tabItem.badgeValue = count > 0 ? "\(count)" : nil
    }
)
```

To poll for new notifications in the background (e.g., on foreground transitions), retain a reference to a shared `NotificationsStore` and call `fetchUnreadCount()`:

```swift
// In your app's scene phase handler:
.onChange(of: scenePhase) { _, phase in
    if phase == .active {
        Task { await sharedNotificationsStore.fetchUnreadCount() }
    }
}
```

---

## Usage example

```swift
import BlueskyNotifications

// Inside a NavigationStack:
NotificationsScreen(
    network: networkClient,
    onUnreadCountChange: { count in
        unreadBadge = count
    }
)
```

The screen automatically calls `loadInitial()` and `markSeen()` on first appearance, so no additional setup is required from the host.
