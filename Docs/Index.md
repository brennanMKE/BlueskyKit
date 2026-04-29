# BlueskyKit Documentation

BlueskyKit is a Swift package that implements a full Bluesky client as reusable, independently-importable modules. All modules target iOS 18+, macOS 15+, tvOS 18+, and watchOS 11+, and are written in Swift 6 strict concurrency mode.

Start with [Concepts.md](Concepts.md) if you are new to AT Protocol or to this codebase's architecture. Then read the foundation modules (BlueskyCore, BlueskyKit) before diving into feature modules.

---

## Foundation

| Doc | Module | Purpose |
|-----|--------|---------|
| [Concepts.md](Concepts.md) | — | Shared vocabulary: AT Protocol fundamentals, Bluesky constructs, codebase architecture patterns |
| [BlueskyCore.md](BlueskyCore.md) | `BlueskyCore` | Pure value-type data model — identifiers, posts, profiles, feeds, embeds, rich text, errors. No actor isolation; types decode on any thread. |
| [BlueskyKit.md](BlueskyKit.md) | `BlueskyKit` | Protocol contracts consumed by every module — `SessionManaging`, `AccountStore`, `NetworkClient`, `PreferencesStore`, `CacheStore`, `BlueskyEnvironment`. Depends only on `BlueskyCore`. |

---

## Infrastructure

| Doc | Module | Purpose |
|-----|--------|---------|
| [BlueskyAuth.md](BlueskyAuth.md) | `BlueskyAuth` | Session lifecycle — `SessionManager`, `LoginView`, `AccountPickerView`. Auth endpoints hit URLSession directly, bypassing `NetworkClient`. |
| [BlueskyDataStore.md](BlueskyDataStore.md) | `BlueskyDataStore` | Concrete persistence — `KeychainAccountStore` (custom actor), `SwiftDataCacheStore` (@Model), `UserDefaultsPreferencesStore`. No `@MainActor` default isolation. |
| [BlueskyNetworking.md](BlueskyNetworking.md) | `BlueskyNetworking` | AT Protocol HTTP client — `ATProtoClient` (custom actor), bearer-auth injection, single-retry 401 token refresh, XRPC URL construction. |
| [BlueskyUI.md](BlueskyUI.md) | `BlueskyUI` | Shared SwiftUI component library — design tokens, `PostCard`, `AvatarView`, `RichTextView`, `PostEmbedView`, `FeedCard`, `ListCard`. Depends only on `BlueskyCore`. |

---

## Feature Modules

All feature modules depend on `BlueskyKit`, `BlueskyCore`, and `BlueskyUI`. Each follows the Store / ViewModel / View layering described in [Concepts.md](Concepts.md).

| Doc | Module | Purpose |
|-----|--------|---------|
| [BlueskyFeed.md](BlueskyFeed.md) | `BlueskyFeed` | Home feed, thread view, saved feeds, video feed, bookmarks |
| [BlueskyProfile.md](BlueskyProfile.md) | `BlueskyProfile` | User profile screen, profile header, edit-profile sheet, follow/unfollow |
| [BlueskySearch.md](BlueskySearch.md) | `BlueskySearch` | Search for people, posts, and feeds with debounced typeahead |
| [BlueskyNotifications.md](BlueskyNotifications.md) | `BlueskyNotifications` | Activity feed — likes, reposts, follows, mentions, replies; unread count |
| [BlueskyMessages.md](BlueskyMessages.md) | `BlueskyMessages` | Direct messages — conversation inbox and per-thread chat UI |
| [BlueskyComposer.md](BlueskyComposer.md) | `BlueskyComposer` | Post creation — rich-text facet detection, image attachments, reply/quote |
| [BlueskyModeration.md](BlueskyModeration.md) | `BlueskyModeration` | Mutes, blocks, content filtering, labelers, report dialog |
| [BlueskySettings.md](BlueskySettings.md) | `BlueskySettings` | App settings — appearance, language, notifications, privacy, accessibility, app passwords, find contacts |
| [BlueskyLists.md](BlueskyLists.md) | `BlueskyLists` | User-created lists and starter packs |

---

## Dependency graph

```
BlueskyCore          (no dependencies)
    └── BlueskyKit   (BlueskyCore)
    └── BlueskyUI    (BlueskyCore)
            └── BlueskyAuth         (BlueskyKit, BlueskyCore)
            └── BlueskyDataStore    (BlueskyKit, BlueskyCore)
            └── BlueskyNetworking   (BlueskyKit, BlueskyCore)
            └── BlueskyFeed         (BlueskyKit, BlueskyCore, BlueskyUI)
            └── BlueskyProfile      (BlueskyKit, BlueskyCore, BlueskyUI)
            └── BlueskySearch       (BlueskyKit, BlueskyCore, BlueskyUI)
            └── BlueskyNotifications(BlueskyKit, BlueskyCore, BlueskyUI)
            └── BlueskyMessages     (BlueskyKit, BlueskyCore, BlueskyUI)
            └── BlueskyComposer     (BlueskyKit, BlueskyCore, BlueskyUI)
            └── BlueskyModeration   (BlueskyKit, BlueskyCore, BlueskyUI)
            └── BlueskySettings     (BlueskyKit, BlueskyCore, BlueskyUI)
            └── BlueskyLists        (BlueskyKit, BlueskyCore, BlueskyUI)
```

No feature module depends on another feature module. All cross-feature wiring happens in the host app via `BlueskyEnvironment`.
