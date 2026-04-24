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
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "BlueskyKit", dependencies: ["BlueskyCore"], swiftSettings: swiftSettings),
        // BlueskyCore is a pure data-model module. No actor isolation — types must be
        // decodable from any context (e.g. background networking tasks).
        .target(name: "BlueskyCore"),
        .target(name: "BlueskyAuth", dependencies: ["BlueskyKit", "BlueskyCore"], swiftSettings: swiftSettings),
        .target(name: "BlueskyDataStore", dependencies: ["BlueskyKit", "BlueskyCore"], swiftSettings: swiftSettings),
        .target(name: "BlueskyUI", swiftSettings: swiftSettings),
        .testTarget(
            name: "BlueskyKitTests",
            dependencies: ["BlueskyKit", "BlueskyCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
