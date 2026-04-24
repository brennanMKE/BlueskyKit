# BlueskyKit

A modular Swift package for building a native Bluesky client with SwiftUI. BlueskyKit contains the bulk of the application logic and is consumed by the Mac app Xcode project, which will later be extended to also run on iOS and iPadOS.

## Migration Docs

This package is part of a React Native → SwiftUI migration. Planning documents live in [`../Bluesky-Migration/`](../Bluesky-Migration/):

| Document | Description |
|---|---|
| [`Migrate-ReactNative-to-SwiftUI.md`](../Bluesky-Migration/Migrate-ReactNative-to-SwiftUI.md) | Migration goals, approach, and module-by-module checklist |
| [`ModularArchitecture.md`](../Bluesky-Migration/ModularArchitecture.md) | Architecture principles and module API design guidelines |
| [`ProjectStructure.md`](../Bluesky-Migration/ProjectStructure.md) | Overview of the sibling repositories and how they fit together |

## Architecture

BlueskyKit is organized into focused libraries with a clear dependency direction: `BlueskyCore` sits at the base, `BlueskyKit` defines the public API contracts, and implementation modules fulfill those contracts.

```
BlueskyUI  BlueskyAuth  BlueskyDataStore  (future: BlueskyNetworking, ...)
     \            |            /
              BlueskyKit  (protocols + bootstrap)
                   |
              BlueskyCore  (shared models)
```

### Libraries

| Library | Role |
|---|---|
| `BlueskyCore` | Shared data types — structs, enums, and value types usable across all modules |
| `BlueskyKit` | Public API protocols for all subsystems (Auth, DataStore, Networking, UI) plus bootstrapping logic |
| `BlueskyAuth` | Authentication implementation |
| `BlueskyDataStore` | Persistence implementation (JSON → SQLite → SwiftData) |
| `BlueskyUI` | SwiftUI views and components |

### Design Principles

**Protocol-first.** `BlueskyKit` defines protocols that implementation modules conform to. App code depends on the protocols, not the implementations, making it straightforward to swap or add implementations.

**Layered implementations.** Modules like `BlueskyDataStore` can ship multiple backends under one API — starting with simple JSON file storage, then adding SQLite, then SwiftData — without breaking callers.

**No upward dependencies.** `BlueskyCore` does not import any other BlueskyKit library. Implementation modules import `BlueskyKit` (for protocols) and `BlueskyCore` (for shared types) but not each other.

## Requirements

- Swift 6.0+
- iOS 18+ / macOS 15+ / tvOS 18+ / watchOS 11+

## Adding BlueskyKit to a Project

```swift
// In your Package.swift
dependencies: [
    .package(url: "https://github.com/your-org/BlueskyKit", from: "1.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "BlueskyKit", package: "BlueskyKit"),
            .product(name: "BlueskyUI", package: "BlueskyKit"),
        ]
    )
]
```

## Planned Modules

- `BlueskyNetworking` — AT Protocol / XRPC networking implementation
