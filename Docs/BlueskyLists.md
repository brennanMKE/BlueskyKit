# BlueskyLists

`BlueskyLists` implements the lists and starter-packs features for BlueskyKit.
It covers the full lifecycle: browsing, creating, deleting, member management,
and the distinct starter-pack flow that wraps a list with a shareable onboarding
record.

## Module overview

```
BlueskyLists
├── ListsScreen              — actor's list of lists; create / delete
├── ListsViewModel           — thin façade over ListsStoring
├── ListsStore               — list + starter-pack network I/O
├── ListDetailScreen         — members tab + feed tab for a single list
├── ListDetailViewModel      — thin façade over ListDetailStoring
├── ListDetailStore          — list detail, member paging, feed paging
├── ListCreateSheet          — form: name, purpose, description
├── StarterPackScreen        — public view of a starter pack
├── StarterPackViewModel     — thin façade exposing starterPack + followAll
└── StarterPackCreateSheet   — form: name, description, list picker
```

### Dependencies

| Dependency | Role |
|------------|------|
| `BlueskyCore` | `ATURI`, `DID`, `ListView`, `ListItemView`, `StarterPackView`, `FeedViewPost`, etc. |
| `BlueskyKit` | `NetworkClient`, `AccountStore` |
| `BlueskyUI` | `AvatarView`, `PostCard`, shared components |

---

## Lists vs. starter packs

**A list** (`app.bsky.graph.list`) is a named, ordered collection of Bluesky
accounts. There are two purposes:

| Purpose lexicon value | Label | Effect |
|----------------------|-------|--------|
| `app.bsky.graph.defs#curatelist` | Curated | Used as a feed source (`app.bsky.feed.getListFeed`) |
| `app.bsky.graph.defs#modlist` | MOD | Used for moderation actions (mute-list, block-list) |

**A starter pack** (`app.bsky.graph.starterpack`) is a separate record that
references a curated list by AT URI and adds a name, description, and creator
attribution. Starter packs are intended for new-user onboarding: sharing a
starter pack URL lets newcomers follow all the members of the attached list in
one tap. A starter pack is always backed by exactly one list; the list can exist
independently. Deleting the list does not delete the starter pack record (though
the pack will no longer have member data).

---

## ListsScreen

`ListsScreen` shows all lists owned by a given actor and provides create and
swipe-to-delete actions.

```swift
public struct ListsScreen: View {
    public init(
        actorDID: String,
        network: any NetworkClient,
        accountStore: any AccountStore
    )
}
```

### Behavior

- On appear and on pull-to-refresh, `viewModel.loadLists(actorDID:)` fetches up
  to 50 lists via `app.bsky.graph.getLists`.
- Each cell is a `NavigationLink` that pushes `ListDetailScreen`.
- Last-cell `.onAppear` triggers `viewModel.loadMore(actorDID:)` for infinite
  scroll.
- Swipe-to-delete calls `viewModel.deleteList(uri:)` for each index-set
  position.
- The `+` toolbar button presents `ListCreateSheet` as a sheet.

### PurposeBadge

The private `PurposeBadge` view renders a small colored capsule:

- `app.bsky.graph.defs#modlist` → orange "MOD" badge
- Anything else → blue "Curated" badge

---

## ListsViewModel

```swift
@Observable
public final class ListsViewModel {
    public var lists: [ListView] { get }
    public var isLoading: Bool { get }
    public var error: String? { get }

    public init(network: any NetworkClient, accountStore: any AccountStore)

    public func loadLists(actorDID: String) async
    public func loadMore(actorDID: String) async
    public func createList(name: String, description: String?,
                           purpose: String = "app.bsky.graph.defs#curatelist") async
    public func deleteList(uri: ATURI) async
    public func addMember(listURI: ATURI, subjectDID: DID, repo: String) async
    public func removeMember(itemURI: ATURI, repo: String) async
    public func createStarterPack(name: String, description: String?, listURI: ATURI) async
    public func clearError()
}
```

`ListsViewModel` also exposes `currentDID() async throws -> String?` which
delegates to `accountStore.loadCurrentDID()`. This is used by
`StarterPackCreateSheet`'s embedded `ListPickerView`.

---

## ListsStore

`ListsStore` is the authoritative I/O layer for the lists inbox and all
starter-pack operations that share the same store.

```swift
public protocol ListsStoring: AnyObject, Observable, Sendable {
    var lists: [ListView] { get }
    var starterPack: StarterPackView? { get }
    var isLoading: Bool { get }
    var error: String? { get }

    func loadLists(actorDID: String) async
    func loadMore(actorDID: String) async
    func createList(name: String, description: String?, purpose: String) async
    func deleteList(uri: ATURI) async
    func addMember(listURI: ATURI, subjectDID: DID, repo: String) async
    func removeMember(itemURI: ATURI, repo: String) async
    func createStarterPack(name: String, description: String?, listURI: ATURI) async
    func loadStarterPack(uri: ATURI) async
    func followAll(pack: StarterPackView) async
    func clearError()
}
```

### Lexicon calls

| Method | Lexicon | Notes |
|--------|---------|-------|
| `loadLists(actorDID:)` | `app.bsky.graph.getLists` | limit 50; resets cursor |
| `loadMore(actorDID:)` | `app.bsky.graph.getLists` | Passes cursor; appends |
| `createList(...)` | `com.atproto.repo.createRecord` | collection `app.bsky.graph.list`; calls `loadLists` on success |
| `deleteList(uri:)` | `com.atproto.repo.deleteRecord` | Optimistic: removes from `lists` before call; collection `app.bsky.graph.list` |
| `addMember(...)` | `com.atproto.repo.createRecord` | collection `app.bsky.graph.listitem` |
| `removeMember(...)` | `com.atproto.repo.deleteRecord` | collection `app.bsky.graph.listitem`; uses `uri.rkey` |
| `createStarterPack(...)` | `com.atproto.repo.createRecord` | collection `app.bsky.graph.starterpack` |
| `loadStarterPack(uri:)` | `app.bsky.graph.getStarterPack` | Populates `starterPack` |
| `followAll(pack:)` | `com.atproto.repo.createRecord` × N | collection `app.bsky.graph.follow`; iterates `listItemsSample`; stops on first error |

### DID resolution pattern

All mutating operations resolve the viewer's DID via
`accountStore.loadCurrentDID()`. They return silently (without error) if the
DID is unavailable, treating it as a precondition failure rather than an
unexpected error.

### Delete optimism

`deleteList(uri:)` removes the item from `lists` before the network call,
giving immediate feedback. No rollback is implemented on failure; the list is
restored on the next full `loadLists`.

---

## ListCreateSheet

`ListCreateSheet` is an internal `Form`-based sheet. It is not `public` in the
module but is used directly by `ListsScreen`.

```swift
struct ListCreateSheet: View {
    public init(onCreate: @escaping (String, String, String?) -> Void)
    // callback signature: (name, purpose, description?)
}
```

### Fields

| Field | Type | Notes |
|-------|------|-------|
| List Name | `TextField` | Required; Create button disabled when blank |
| Type | `Picker` (menu) | Curated List or Moderation List |
| Description | `TextEditor` | Optional; trimmed to `nil` if empty |

The `onCreate` closure receives the trimmed name, the selected purpose string,
and an optional description. `ListsScreen` invokes `viewModel.createList(...)`,
then closes the sheet.

---

## ListDetailScreen

`ListDetailScreen` provides two tabs for a given list AT URI: a **Members** tab
(the accounts in the list) and a **Feed** tab (recent posts from those accounts).

```swift
struct ListDetailScreen: View {
    init(listURI: ATURI, network: any NetworkClient)
}
```

The screen is internal (no `public` modifier). Navigation is handled by the
`NavigationLink` in `ListsScreen`.

### Layout

```
[Segmented picker: Members | Feed]
└─ Members tab:
   List of MemberRow (avatar, displayName, @handle, description excerpt)
   Infinite scroll via last-cell onAppear → loadMore()
└─ Feed tab:
   List of PostCard items
   Infinite scroll via last-cell onAppear → loadMoreFeed()
   Lazy-loaded on first tab switch
```

The feed tab is not loaded until the user switches to it for the first time:
`onChange(of: selectedTab)` triggers `viewModel.loadFeed()` only when
`viewModel.feed.isEmpty`.

### Navigation title

Set to `viewModel.list?.name ?? "List"`. Because `list` is loaded asynchronously,
the title may start as "List" and update once the first `getList` response
arrives.

---

## ListDetailViewModel

```swift
@Observable
final class ListDetailViewModel {
    var list: ListView? { get }
    var members: [ListItemView] { get }
    var feed: [FeedViewPost] { get }
    var isLoading: Bool { get }
    var error: String? { get }

    init(network: any NetworkClient)

    func load(listURI: ATURI) async
    func loadMore() async
    func loadFeed() async
    func loadMoreFeed() async
}
```

All calls delegate 1:1 to `ListDetailStoring`.

---

## ListDetailStore

`ListDetailStore` manages member and feed paging for a single list. It is
separate from `ListsStore` so it carries its own independent cursors.

```swift
public protocol ListDetailStoring: AnyObject, Observable, Sendable {
    var list: ListView? { get }
    var members: [ListItemView] { get }
    var feed: [FeedViewPost] { get }
    var isLoading: Bool { get }
    var error: String? { get }

    func load(listURI: ATURI) async
    func loadMore() async
    func loadFeed() async
    func loadMoreFeed() async
}
```

### Lexicon calls

| Method | Lexicon | Notes |
|--------|---------|-------|
| `load(listURI:)` | `app.bsky.graph.getList` | limit 50; sets `list`, `members`, `membersCursor` |
| `loadMore()` | `app.bsky.graph.getList` | Appends to `members`; requires `membersCursor` |
| `loadFeed()` | `app.bsky.feed.getListFeed` | limit 50; requires stored `listURI` |
| `loadMoreFeed()` | `app.bsky.feed.getListFeed` | Appends to `feed`; requires `feedCursor` |

### Cursor state

`ListDetailStore` keeps two independent cursors:

- `membersCursor` — progresses as the user scrolls the Members tab
- `feedCursor` — progresses as the user scrolls the Feed tab

Both are `nil` before the corresponding initial fetch and become `nil` again
when the server returns no further cursor (end of data).

---

## StarterPackScreen

`StarterPackScreen` is the public read-only view of a starter pack. It uses an
inset-grouped `List` style on iOS and inset style on macOS.

```swift
public struct StarterPackScreen: View {
    public init(
        starterPackURI: ATURI,
        network: any NetworkClient,
        accountStore: any AccountStore
    )
}
```

### Layout

```
Section (pack header):
  - Pack name (title2, bold)
  - Creator avatar + "@handle"
  - "N joined this week" (from joinedWeekCount)
  - "N+ members" (from listItemsSample.count)
  - "Follow All" button (borderedProminent)

Section "Members":
  - ListItemView rows: avatar, displayName, @handle
```

The "Follow All" button calls `viewModel.followAll(pack:)`, which posts a
`app.bsky.graph.follow` record for each member in `listItemsSample` using the
`ListsStore.followAll(pack:)` method. The operation stops at the first error and
surfaces it via the alert.

---

## StarterPackViewModel

```swift
@Observable
public final class StarterPackViewModel {
    public var starterPack: StarterPackView? { get }
    public var isLoading: Bool { get }
    public var error: String? { get }

    public init(network: any NetworkClient, accountStore: any AccountStore)

    public func load(uri: ATURI) async
    public func followAll(pack: StarterPackView) async
    public func clearError()
}
```

`StarterPackViewModel` creates its own private `ListsStore` instance. This
means `starterPack` is isolated from the `lists` array that `ListsViewModel`
manages; the two stores do not share state.

---

## StarterPackCreateSheet

`StarterPackCreateSheet` is an internal form sheet. It reuses `ListsViewModel`
for both its list-picker sub-sheet and the eventual `createStarterPack` call.

```swift
struct StarterPackCreateSheet: View {
    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        onDismiss: @escaping () -> Void
    )
}
```

### Fields

| Field | Required | Notes |
|-------|----------|-------|
| Starter Pack Name | Yes | Create button disabled when blank |
| Description | No | Trimmed to `nil` if empty |
| Member List | Yes | Selected via embedded `ListPickerView` sheet |

### List picker sub-sheet

`ListPickerView` is a private helper view that binds to a `ListsViewModel`. It
loads the current user's lists via `viewModel.loadLists(actorDID:)` using the
DID resolved from `viewModel.currentDID()`. Tapping a row fires the `onSelect`
callback, which sets `selectedList` on `StarterPackCreateSheet` and dismisses
the picker.

### Create flow

On confirmation, `StarterPackCreateSheet.createStarterPack()`:

1. Trims name and description.
2. Calls `viewModel.createStarterPack(name:description:listURI:)`, which posts
   a `app.bsky.graph.starterpack` record via `com.atproto.repo.createRecord`.
3. Dismisses the sheet and calls `onDismiss`.

---

## Data types (BlueskyCore)

| Type | Description |
|------|-------------|
| `ListView` | `uri: ATURI`, `name`, `purpose`, `description?`, `avatar?`, `creator: ProfileBasic` |
| `ListItemView` | `uri: ATURI`, `subject: ProfileView` (includes `displayName`, `handle`, `avatar`, `description`) |
| `StarterPackView` | `uri: ATURI`, `creator: ProfileBasic`, `list: ListView?`, `listItemsSample: [ListItemView]?`, `joinedWeekCount: Int?` |
| `FeedViewPost` | A post as it appears in a feed, used by the Feed tab |
| `ListRecord` | Encodable record for `app.bsky.graph.list` |
| `ListItemRecord` | Encodable record for `app.bsky.graph.listitem` with `list` + `subject` |
| `StarterPackRecord` | Encodable record for `app.bsky.graph.starterpack` with `name`, `description?`, `list` |
| `FollowRecord` | Encodable record for `app.bsky.graph.follow` |

---

## Usage example

```swift
// Browse your own lists
NavigationStack {
    ListsScreen(
        actorDID: session.did.rawValue,
        network: myNetworkClient,
        accountStore: myAccountStore
    )
}

// View a starter pack from a deep link
NavigationStack {
    StarterPackScreen(
        starterPackURI: ATURI(rawValue: "at://did:plc:xxx/app.bsky.graph.starterpack/yyy")!,
        network: myNetworkClient,
        accountStore: myAccountStore
    )
}

// Create a new starter pack (typically inside a host view's toolbar or menu)
StarterPackCreateSheet(
    network: myNetworkClient,
    accountStore: myAccountStore,
    onDismiss: { showSheet = false }
)
```
