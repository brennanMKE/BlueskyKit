import Foundation

// MARK: - com.atproto.richtext.facet

/// A byte-range annotation on post text (mention, link, or hashtag).
public struct RichTextFacet: Codable, Sendable {
    public let index: ByteSlice
    public let features: [FacetFeature]

    public init(index: ByteSlice, features: [FacetFeature]) {
        self.index = index
        self.features = features
    }
}

/// UTF-8 byte range within post text.
public struct ByteSlice: Codable, Sendable {
    public let byteStart: Int
    public let byteEnd: Int

    public init(byteStart: Int, byteEnd: Int) {
        self.byteStart = byteStart
        self.byteEnd = byteEnd
    }
}

/// The type of annotation applied to a byte range.
public enum FacetFeature: Codable, Sendable {
    case mention(did: DID)
    case link(uri: String)
    case tag(tag: String)
    /// An unrecognized feature type — preserved for forward compatibility.
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case did, uri, tag
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "app.bsky.richtext.facet#mention":
            let did = try container.decode(DID.self, forKey: .did)
            self = .mention(did: did)
        case "app.bsky.richtext.facet#link":
            let uri = try container.decode(String.self, forKey: .uri)
            self = .link(uri: uri)
        case "app.bsky.richtext.facet#tag":
            let tag = try container.decode(String.self, forKey: .tag)
            self = .tag(tag: tag)
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mention(let did):
            try container.encode("app.bsky.richtext.facet#mention", forKey: .type)
            try container.encode(did, forKey: .did)
        case .link(let uri):
            try container.encode("app.bsky.richtext.facet#link", forKey: .type)
            try container.encode(uri, forKey: .uri)
        case .tag(let tag):
            try container.encode("app.bsky.richtext.facet#tag", forKey: .type)
            try container.encode(tag, forKey: .tag)
        case .unknown(let t):
            try container.encode(t, forKey: .type)
        }
    }
}
