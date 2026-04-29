# BlueskyModeration

The `BlueskyModeration` module provides all screens and data-management logic for the moderation section of the Bluesky client: mutes, blocks, content-filter settings, moderation lists, labeler profiles, and the report dialog.

## Module Overview

```
Sources/BlueskyModeration/
  ModerationScreen.swift
  ModerationStore.swift
  ModerationViewModel.swift
  MutesScreen.swift
  BlocksScreen.swift
  ModerationListsScreen.swift
  ContentFilterSettingsScreen.swift
  LabelerProfileScreen.swift
  LabelerProfileStore.swift
  LabelerProfileViewModel.swift
  ReportDialog.swift
```

All types in this module use `@MainActor` default isolation (enabled via `swiftSettings` in `Package.swift`). Network I/O is delegated to the `NetworkClient` protocol, keeping Views and ViewModels free of URLSession details.

---

## Architecture

This module follows the three-tier Store / ViewModel / View pattern used throughout BlueskyKit:

| Tier | Responsibility |
|------|---------------|
| **Store** | Owns all mutable state; calls `NetworkClient` for remote I/O; publishes `@Published` properties |
| **ViewModel** | Adapts store state to view-ready presentation types; contains no networking code |
| **View** | Reads from ViewModel; dispatches user actions to the store |

`ModerationStore` is the single root store for the hub and its list-based sub-screens. `LabelerProfileStore` is a separate store scoped to a single labeler, instantiated on demand when a labeler profile is opened.

---

## ModerationScreen

Entry point for the moderation section. Renders a navigation list with links to:

- Muted accounts
- Blocked accounts
- Moderation lists
- Content filter settings
- Any subscribed labelers

`ModerationScreen` observes `ModerationViewModel`, which derives its display data from `ModerationStore`.

---

## ModerationStore

`ModerationStore` is the primary data owner for the moderation hub.

### State

| Property | Type | Description |
|----------|------|-------------|
| `mutedAccounts` | `[Profile]` | Accounts the current user has muted |
| `blockedAccounts` | `[Profile]` | Accounts the current user has blocked |
| `moderationLists` | `[ModerationList]` | Lists the current user subscribes to |
| `contentFilterPreferences` | `ContentFilterPreferences` | Visibility settings for content categories |
| `isLoading` | `Bool` | Unified loading flag for initial fetches |
| `error` | `Error?` | Last network or decode error |

### Key Actions

```swift
func loadAll() async
func unmute(_ did: DID) async
func unblock(_ did: DID) async
func unsubscribeFromList(_ uri: ATURI) async
func updateContentFilter(_ preference: ContentFilterPreference) async
```

`loadAll()` fires parallel fetches for muted accounts, blocked accounts, and moderation lists. Each individual action optimistically updates local state before the network call completes, then reconciles on success or rolls back on failure.

---

## ModerationViewModel

Transforms raw `ModerationStore` state into presentation-ready values.

- Groups muted/blocked accounts alphabetically for section display
- Maps `ContentFilterPreferences` to human-readable label/description pairs
- Exposes a sorted list of moderation lists with subscriber counts formatted as locale-aware strings

---

## MutesScreen

Displays a scrollable list of muted accounts. Each row shows the account avatar, display name, and handle. A swipe-to-delete gesture calls `ModerationStore.unmute(_:)`.

Cursor-based pagination is supported: when the user scrolls near the bottom of the list the screen requests the next page from the store, which appends results to `mutedAccounts`.

---

## BlocksScreen

Mirrors `MutesScreen` in structure but operates on blocked accounts. Swipe-to-delete triggers `ModerationStore.unblock(_:)`. Pagination works identically.

---

## ModerationListsScreen

Lists all moderation lists the current user subscribes to. Each row displays:

- List name
- Creator handle
- Subscriber count

Tapping a row navigates to a detail view showing member profiles. An unsubscribe button calls `ModerationStore.unsubscribeFromList(_:)`.

### Moderation List vs. User List

A **moderation list** (`app.bsky.graph.listitem` with purpose `mod`) is a curated set of accounts whose content a user wants to filter or block in bulk. A **user list** (purpose `curate`) is simply a collection of accounts for organizational purposes (similar to a Twitter list). Both share the same AT Protocol record type; the `purpose` field distinguishes them. `ModerationListsScreen` shows only mod-purpose lists.

---

## ContentFilterSettingsScreen

Renders the full content filtering panel. Each content category (e.g., adult content, graphic media, spam) is shown with:

- A label and description sourced from `ModerationViewModel`
- A segmented control or picker for visibility: `show`, `warn`, `hide`

Changing a setting calls `ModerationStore.updateContentFilter(_:)`. Changes are persisted on the server via the `app.bsky.actor.putPreferences` lexicon.

### ContentFilterPreference

```swift
struct ContentFilterPreference {
    let label: String          // e.g. "adult-content", "graphic-media"
    var visibility: Visibility // .show | .warn | .hide
}
```

Labels are AT Protocol label values defined by the Bluesky labeler network. Custom labelers can introduce additional label values beyond the built-in set.

---

## LabelerProfileScreen

Shows a single labeler's profile page, including:

- Display name and description
- Number of labels applied by this labeler
- Per-label visibility controls (identical in structure to `ContentFilterSettingsScreen` but scoped to the labeler's label definitions)
- Subscribe / unsubscribe toggle

`LabelerProfileScreen` owns its own `LabelerProfileStore` instance, injected at construction time with the labeler's DID.

---

## LabelerProfileStore

Scoped store for a single labeler. Fetches the labeler's `app.bsky.labeler.getService` record and the current user's subscription status.

### State

| Property | Type | Description |
|----------|------|-------------|
| `labeler` | `LabelerView?` | Decoded labeler service record |
| `isSubscribed` | `Bool` | Whether the current user subscribes |
| `labelPreferences` | `[ContentFilterPreference]` | Per-label visibility settings for this labeler |
| `isLoading` | `Bool` | Fetch-in-progress flag |
| `error` | `Error?` | Last error |

### Key Actions

```swift
func load() async
func subscribe() async
func unsubscribe() async
func updateLabelPreference(_ preference: ContentFilterPreference) async
```

---

## LabelerProfileViewModel

Adapts `LabelerProfileStore` state for display:

- Formats the labeler's label count as a localized string
- Produces `LabelRow` presentation types pairing each label's raw value with a user-facing description sourced from the labeler's policy document

---

## ReportDialog

A modal sheet used to report a post, account, or list to a moderation service. The dialog:

1. Lets the user choose a reason category (e.g., spam, misleading, sexual content)
2. Accepts an optional free-text additional details field
3. Lets the user choose which moderation service to report to (defaults to Bluesky's built-in service)

On submission, the dialog calls `com.atproto.moderation.createReport` via `NetworkClient`. A `@Binding<Bool>` controls presentation so the parent view dismisses the sheet after a successful report.

```swift
ReportDialog(
    subject: .post(uri: postURI, cid: postCID),
    isPresented: $showReport
)
```

### ReportSubject

```swift
enum ReportSubject {
    case post(uri: ATURI, cid: CID)
    case account(did: DID)
    case list(uri: ATURI, cid: CID)
}
```

The subject determines which AT Protocol record type is embedded in the `createReport` request body.

---

## Core Types Used

These types are defined in `BlueskyCore` and used throughout this module:

| Type | Source | Notes |
|------|--------|-------|
| `DID` | `Identifiers.swift` | Decentralized identifier for an account |
| `ATURI` | `Identifiers.swift` | AT-URI pointing to a specific record |
| `CID` | `Identifiers.swift` | Content-addressed record version identifier |
| `Profile` | `Graph.swift` | Public profile fields for an account |
| `ModerationList` | `Graph.swift` | Moderation or curation list record |

---

## Dependencies

| Dependency | Role |
|-----------|------|
| `BlueskyCore` | Value types: `DID`, `ATURI`, `CID`, `Profile`, `ModerationList`, `ContentFilterPreference` |
| `BlueskyKit` | `NetworkClient` protocol for all remote calls; `SessionManaging` for the current user's DID |

No UI framework beyond SwiftUI is imported. All network paths go through `NetworkClient` so that unit tests can inject a mock without spinning up a live server.
