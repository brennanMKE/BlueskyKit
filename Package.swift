// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Important: Use these settings for all libraries.
let swiftSettings: [SwiftSetting]? = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "BlueskyKit",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(name: "BlueskyKit", targets: ["BlueskyKit"]),
        .library(name: "BlueskyCore", targets: ["BlueskyCore"]),
        .library(name: "BlueskyAuth", targets: ["BlueskyAuth"]),
        .library(name: "BlueskyDataStore", targets: ["BlueskyDataStore"]),
        .library(name: "BlueskyUI", targets: ["BlueskyUI"]),
        .library(name: "BlueskyNetworking", targets: ["BlueskyNetworking"]),
        .library(name: "BlueskyFeed", targets: ["BlueskyFeed"]),
        .library(name: "BlueskyProfile", targets: ["BlueskyProfile"]),
        .library(name: "BlueskySearch", targets: ["BlueskySearch"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "BlueskyKit", dependencies: ["BlueskyCore"], swiftSettings: swiftSettings),
        // BlueskyCore is a pure data-model module. No actor isolation — types must be
        // decodable from any context (e.g. background networking tasks).
        .target(name: "BlueskyCore"),
        .target(name: "BlueskyAuth", dependencies: ["BlueskyKit", "BlueskyCore"], swiftSettings: swiftSettings),
        // BlueskyDataStore is an I/O module. No defaultIsolation — it contains custom actors
        // (KeychainAccountStore, SwiftDataCacheStore) and @Model classes that must be usable
        // from non-MainActor contexts.
        .target(name: "BlueskyDataStore", dependencies: ["BlueskyKit", "BlueskyCore"]),
        .target(name: "BlueskyUI", dependencies: ["BlueskyCore"], swiftSettings: swiftSettings),
        // BlueskyNetworking is a pure I/O module. No actor isolation — ATProtoClient is a custom actor,
        // and its private Decodable helpers must be nonisolated.
        .target(name: "BlueskyNetworking", dependencies: ["BlueskyKit", "BlueskyCore"]),
        .target(name: "BlueskyFeed", dependencies: ["BlueskyKit", "BlueskyCore", "BlueskyUI"], swiftSettings: swiftSettings),
        .target(name: "BlueskyProfile", dependencies: ["BlueskyKit", "BlueskyCore", "BlueskyUI"], swiftSettings: swiftSettings),
        .target(name: "BlueskySearch", dependencies: ["BlueskyKit", "BlueskyCore", "BlueskyUI"], swiftSettings: swiftSettings),
        .testTarget(
            name: "BlueskyKitTests",
            dependencies: ["BlueskyKit", "BlueskyCore", "BlueskyDataStore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
