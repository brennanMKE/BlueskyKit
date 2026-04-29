# BlueskyMessages

`BlueskyMessages` is the direct-messaging module for BlueskyKit. It provides a
conversation inbox screen, a per-thread chat view, and the full store/view-model
stack that backs both. All network I/O goes through `NetworkClient` and targets
the `chat.bsky.convo.*` lexicon namespace.

## Module overview

```
BlueskyMessages
├── ConversationListScreen   — inbox of all DM conversations
├── MessagesViewModel        — thin @Observable façade over ConversationStore
├── ConversationStore        — network I/O for the inbox list
├── MessageThreadScreen      — scrollable bubble view + compose bar
├── MessageThreadViewModel   — thin @Observable façade over MessageThreadStore
└── MessageThreadStore       — network I/O for a single thread
```

### Dependencies

| Dependency | Role |
|------------|------|
| `BlueskyCore` | Value types: `DID`, `ConvoView`, `MessageView`, etc. |
| `BlueskyKit` | `NetworkClient` protocol |
| `BlueskyUI` | `AvatarView`, `BadgeView`, shared components |

---

## ConversationListScreen

`ConversationListScreen` is the messages inbox. It renders a plain `List` of
`ConvoView` items, showing the conversation name (derived from the other
participants), the last message preview, and an unread count badge.

```swift
public struct ConversationListScreen: View {
    public init(
        network: any NetworkClient,
        viewerDID: DID? = nil,
        onConvoTap: ((ConvoView) -> Void)? = nil
    )
}
```

### Parameters

| Parameter | Purpose |
|-----------|---------|
| `network` | `NetworkClient` used for all API calls |
| `viewerDID` | The signed-in user's DID; used to exclude the viewer from name/avatar derivation |
| `onConvoTap` | Optional override for navigation. When `nil` the screen pushes `MessageThreadScreen` via `NavigationDestination` |

### States

- **Loading (empty list)** — a centered `ProgressView`
- **Empty** — icon + "No messages yet" message
- **Error (empty list)** — icon + error text + Retry button that calls `refresh()`
- **Populated** — `List` with `ConvoRow` cells

### Swipe actions

Each row exposes two trailing swipe actions:

| Label | Action |
|-------|--------|
| Leave | Calls `viewModel.leaveConvo(_:)` (destructive) |
| Mute / Unmute | Calls `viewModel.muteConvo(_:muted:)` (orange tint) |

### Pagination

The last-cell `.onAppear` modifier calls `viewModel.loadMore()`, which appends
the next page only when a cursor is available. A `ProgressView` row is appended
to the list while loading is in progress.

### Convo name derivation

The `ConvoRow` private helper filters `convo.members` to exclude the viewer's
DID. It prefers `displayName` and falls back to `handle.rawValue`. Multiple
other participants are joined with `", "`.

---

## MessagesViewModel

`MessagesViewModel` is an `@Observable` façade that forwards all state reads and
async calls directly to the underlying `ConversationStoring` implementation.

```swift
@Observable
public final class MessagesViewModel {
    public var convos: [ConvoView] { get }
    public var isLoading: Bool { get }
    public var errorMessage: String? { get }

    public init(network: any NetworkClient)

    public func loadInitial() async
    public func loadMore() async
    public func refresh() async
    public func leaveConvo(_ convoId: String) async
    public func muteConvo(_ convoId: String, muted: Bool) async
}
```

The separation allows `ConversationListScreen` to hold the view model as
`@State` without requiring `ConversationStore` to be a `@State` value directly.
It also keeps the mock surface small: tests only need to implement
`ConversationStoring`.

---

## ConversationStore

`ConversationStore` owns the authoritative conversation list and all associated
network I/O. It conforms to `ConversationStoring`.

```swift
public protocol ConversationStoring: AnyObject, Observable, Sendable {
    var convos: [ConvoView] { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func loadInitial() async
    func loadMore() async
    func refresh() async
    func leaveConvo(_ convoId: String) async
    func muteConvo(_ convoId: String, muted: Bool) async
}

@Observable
public final class ConversationStore: ConversationStoring {
    public init(network: any NetworkClient)
}
```

### Lexicon calls

| Method | Lexicon | Notes |
|--------|---------|-------|
| `loadInitial()` | `chat.bsky.convo.listConvos` | Skips if already loading or list non-empty; limit 50 |
| `loadMore()` | `chat.bsky.convo.listConvos` | Requires `cursor`; appends to `convos` |
| `refresh()` | `chat.bsky.convo.listConvos` | Resets list; always runs regardless of current loading state |
| `leaveConvo(_:)` | `chat.bsky.convo.leaveConvo` | Optimistic: removes item first; re-fetches on failure |
| `muteConvo(_:muted:true)` | `chat.bsky.convo.muteConvo` | Optimistic local muted toggle; reconciles from response |
| `muteConvo(_:muted:false)` | `chat.bsky.convo.unmuteConvo` | Same pattern |

### Optimistic updates

`leaveConvo` removes the item from `convos` immediately before the network
call. If the call fails, `refresh()` is called to restore authoritative state.

`muteConvo` reconstructs the `ConvoView` value with the toggled `muted` flag
before the call, then overwrites it again with the server's returned `ConvoView`
on success. Errors are silently ignored (the temporary local state remains until
the next full refresh).

### Cursor management

`cursor` is reset to `nil` on `loadInitial()` / `refresh()` and updated after
every successful page fetch. `loadMore()` returns immediately when `cursor` is
`nil`, preventing over-fetching.

---

## MessageThreadScreen

`MessageThreadScreen` is the per-conversation chat view. It combines a
`ScrollViewReader`-driven bubble list with a multi-line compose bar at the
bottom.

```swift
public struct MessageThreadScreen: View {
    public init(
        convo: ConvoView,
        network: any NetworkClient,
        viewerDID: DID? = nil
    )
}
```

### Layout

```
NavigationTitle (derived from other participants)
┌────────────────────────────────────┐
│  [Load older messages button]      │  ← shown when hasOlderMessages
│  MessageBubble …                   │
│  MessageBubble …                   │
│  MessageBubble …                   │
├────────────────────────────────────┤
│  TextField("Message…")  [Send btn] │
└────────────────────────────────────┘
```

The `ScrollView` uses `onChange(of: viewModel.messages.count)` to animate-scroll
to the last message whenever a new message is appended (both after loading and
after sending).

### Message bubbles

The private `MessageBubble` view aligns own messages to the right
(`isOwn == true`) with accent-color fill and white text. Other participants'
messages align left with a neutral background. A `Spacer(minLength: 60)` on the
opposite side pushes each bubble away from that edge.

### Send bar behavior

- The `TextField` grows up to five lines before scrolling.
- The send button is disabled when `draftText` is whitespace-only or
  `viewModel.isSending` is `true`.
- On tap the draft is captured, the field is cleared immediately (optimistic UX),
  and `viewModel.sendMessage(_:)` is called in a detached `Task`.

### Initial load and mark-read

`.task` triggers `viewModel.load()`, which fetches the first 50 messages and
immediately fires `markRead` to clear the unread indicator on the inbox row.

---

## MessageThreadViewModel

```swift
@Observable
public final class MessageThreadViewModel {
    public let convoId: String

    public var messages: [MessageView] { get }
    public var isLoading: Bool { get }
    public var isSending: Bool { get }
    public var errorMessage: String? { get }
    public var convo: ConvoView? { get }
    public var hasOlderMessages: Bool { get }

    public init(convoId: String, viewerDID: DID? = nil, network: any NetworkClient)

    public func isOwn(_ message: MessageView) -> Bool
    public func load() async
    public func loadOlder() async
    public func sendMessage(_ text: String) async
}
```

The only view-specific logic is `isOwn(_:)`, which compares `message.sender.did`
to the `viewerDID` supplied at init time. When `viewerDID` is `nil` the method
returns `false`, so all bubbles appear as incoming.

---

## MessageThreadStore

`MessageThreadStore` owns all network I/O for a single conversation thread.

```swift
public protocol MessageThreadStoring: AnyObject, Observable, Sendable {
    var messages: [MessageView] { get }
    var isLoading: Bool { get }
    var isSending: Bool { get }
    var errorMessage: String? { get }
    var convo: ConvoView? { get }
    var hasOlderMessages: Bool { get }

    func load(convoId: String) async
    func loadOlder(convoId: String) async
    func sendMessage(_ text: String, convoId: String) async
}
```

### Lexicon calls

| Method | Lexicon | Notes |
|--------|---------|-------|
| `load(convoId:)` | `chat.bsky.convo.getMessages` | Fetches up to 50; reverses the array so oldest is at index 0 |
| `load(convoId:)` → mark read | `chat.bsky.convo.updateRead` | Called automatically after a successful load |
| `loadOlder(convoId:)` | `chat.bsky.convo.getMessages` | Passes cursor; inserts reversed page at index 0 |
| `sendMessage(_:convoId:)` | `chat.bsky.convo.sendMessage` | Appends the returned `MessageView` to `messages` on success |

### Pagination direction

Unlike the inbox, thread pagination goes backwards in time. `load` fetches the
newest messages (no cursor). `loadOlder` fetches the page before the current
oldest message using the stored cursor. Each page is reversed before being
inserted so the `messages` array is always in chronological order (oldest first).

`hasOlderMessages` is `true` as long as `cursor != nil`.

### Mark-read behavior

`markRead(convoId:)` is a `private` helper that posts to
`chat.bsky.convo.updateRead` immediately after a successful initial load. Errors
are silently suppressed; mark-read failures do not affect the UI.

---

## Data types (BlueskyCore)

| Type | Description |
|------|-------------|
| `ConvoView` | A conversation: `id`, `rev`, `members: [ProfileBasic]`, `lastMessage: MessageView?`, `unreadCount: Int`, `muted: Bool` |
| `MessageView` | A single message: `id`, `text`, `sender: SenderView` (carries `.did: DID`) |
| `ConvoIDRequest` | Request body for leave/mute/unmute calls |
| `SendMessageRequest` | Wraps `convoId` + `MessageInput(text:)` |
| `UpdateReadRequest` | Wraps `convoId` for the mark-read call |

---

## Usage example

```swift
// Embed the inbox in a NavigationStack
NavigationStack {
    ConversationListScreen(
        network: myNetworkClient,
        viewerDID: session.did
    )
}

// Navigate directly to a thread (e.g. from a deep link)
MessageThreadScreen(
    convo: convoView,
    network: myNetworkClient,
    viewerDID: session.did
)
```
