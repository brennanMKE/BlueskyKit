# BlueskyKit — Session Context

This is a Swift package implementing a full Bluesky client as reusable modules.
It is being built as a module-by-module migration from a React Native app.

## Migration docs (read these first)

All planning, checklists, and progress live in `../Bluesky-Migration/`:

- **`../Bluesky-Migration/Progress.md`** — current status, active item, up-next checklist, completion log, session notes. **Start here.**
- **`../Bluesky-Migration/Migrate-ReactNative-to-SwiftUI.md`** — full module-by-module migration plan with checkboxes.
- **`../Bluesky-Migration/ModularArchitecture.md`** — Swift architecture principles.
- **`../Bluesky-Migration/ProjectStructure.md`** — repository layout.

## Quick orientation

| Module | Location | Status |
|--------|----------|--------|
| `BlueskyCore` | `Sources/BlueskyCore/` | ✅ Done — shared value types (identifiers, errors, pagination, Account, Profile, Post, RichText, Embed) |
| `BlueskyKit` | `Sources/BlueskyKit/` | ✅ Done — public protocol contracts (SessionManaging, AccountStore, PreferencesStore, NetworkClient, BlueskyEnvironment) |
| `BlueskyAuth` | `Sources/BlueskyAuth/` | ✅ Done — SessionManager, LoginView, AccountPickerView |
| `BlueskyDataStore` | `Sources/BlueskyDataStore/` | ✅ Done — KeychainAccountStore |
| `BlueskyUI` | `Sources/BlueskyUI/` | ⬜ Not started |

## Current active work

**Module 1 gate** is blocked on the `Bluesky-SwiftUI` Xcode app target (not in this repo).
**Start Module 2** — `BlueskyNetworking`: `ATProtoClient` with URLSession + bearer auth + 401 auto-refresh.

See `../Bluesky-Migration/Progress.md` → "Up Next" for the exact checklist.

## Key architecture decisions

- **`BlueskyCore` has NO actor isolation** — data types must decode from any context (networking tasks). Do NOT add `swiftSettings` to the BlueskyCore target.
- **All other modules** use `defaultIsolation(MainActor.self)` via the shared `swiftSettings` in `Package.swift`.
- **`nonisolated` on I/O protocol requirements** (`AccountStore`, `PreferencesStore`, `NetworkClient`) — lets implementations be actors.
- **`SessionManaging` stays `@MainActor`** — it owns UI-visible session state.
- **`@MainActor` protocol mocks** → `@MainActor final class`. **`nonisolated` protocol mocks** → `final class, @unchecked Sendable`.
- **Private `Decodable` structs in `@MainActor` modules** — their conformances are `@MainActor`-isolated. Avoid `T: Decodable & Sendable` constraints from `@MainActor` callers; use `T: Decodable` only.
- **Auth endpoints** (`createSession`, `refreshSession`, `deleteSession`) use URLSession directly in `SessionManager` — they need no-auth or refreshJwt bearer, not the access-token `NetworkClient`.

## Running tests

```
swift build
swift test
```

9 tests pass (BlueskyKit protocols, BlueskyCore Codable round-trips).
