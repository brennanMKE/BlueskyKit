# BlueskyKit

A modular Swift package for building a native Bluesky client with SwiftUI.

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
