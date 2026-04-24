import Foundation

public struct DID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct Handle: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// An AT-URI of the form `at://repo/collection/rkey`.
public struct ATURI: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    private var pathComponents: [Substring] {
        let stripped = rawValue.hasPrefix("at://") ? rawValue.dropFirst(5) : rawValue[...]
        return stripped.split(separator: "/", maxSplits: 2)
    }

    public var repo: String? { pathComponents.first.map(String.init) }
    public var collection: String? { pathComponents.count > 1 ? String(pathComponents[1]) : nil }
    public var rkey: String? { pathComponents.count > 2 ? String(pathComponents[2]) : nil }
}

/// A content identifier (CID) — an opaque string client-side; no crypto operations needed.
public typealias CID = String
