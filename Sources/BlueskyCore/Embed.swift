import Foundation

// MARK: - Shared helpers

/// Aspect ratio hint used by images and videos.
public struct AspectRatio: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// An IPLD blob reference as stored in a post record.
///
/// AT Protocol encodes the CID as `{ "ref": { "$link": "<cid>" }, "mimeType": "...", "size": N }`.
public struct BlobRef: Codable, Hashable, Sendable {
    public let cid: CID
    public let mimeType: String
    public let size: Int

    public init(cid: CID, mimeType: String, size: Int) {
        self.cid = cid
        self.mimeType = mimeType
        self.size = size
    }

    private struct IPLDLink: Codable {
        let link: String
        enum CodingKeys: String, CodingKey { case link = "$link" }
    }

    private enum CodingKeys: String, CodingKey { case ref, mimeType, size }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ref = try c.decode(IPLDLink.self, forKey: .ref)
        self.cid = ref.link
        self.mimeType = try c.decode(String.self, forKey: .mimeType)
        self.size = try c.decode(Int.self, forKey: .size)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(IPLDLink(link: cid), forKey: .ref)
        try c.encode(mimeType, forKey: .mimeType)
        try c.encode(size, forKey: .size)
    }
}

// MARK: - Embed payload types (stored in post records)

public struct EmbedImage: Codable, Sendable {
    public let image: BlobRef
    public let alt: String
    public let aspectRatio: AspectRatio?

    public init(image: BlobRef, alt: String, aspectRatio: AspectRatio?) {
        self.image = image
        self.alt = alt
        self.aspectRatio = aspectRatio
    }
}

public struct EmbedExternal: Codable, Sendable {
    public let uri: String
    public let title: String
    public let description: String
    public let thumb: BlobRef?

    public init(uri: String, title: String, description: String, thumb: BlobRef?) {
        self.uri = uri
        self.title = title
        self.description = description
        self.thumb = thumb
    }
}

public struct EmbedVideo: Codable, Sendable {
    public let video: BlobRef
    public let captions: [VideoCaption]?
    public let alt: String?
    public let aspectRatio: AspectRatio?

    public init(video: BlobRef, captions: [VideoCaption]?, alt: String?, aspectRatio: AspectRatio?) {
        self.video = video
        self.captions = captions
        self.alt = alt
        self.aspectRatio = aspectRatio
    }
}

public struct VideoCaption: Codable, Sendable {
    public let lang: String
    public let file: BlobRef

    public init(lang: String, file: BlobRef) {
        self.lang = lang
        self.file = file
    }
}

/// A reference to another post record used in quote-post embeds.
public struct EmbedRecordRef: Codable, Sendable {
    public let uri: ATURI
    public let cid: CID

    public init(uri: ATURI, cid: CID) {
        self.uri = uri
        self.cid = cid
    }
}

// MARK: - Embed (discriminated union for outgoing post records)

/// The embed attached to a post record, identified by `$type`.
public indirect enum Embed: Codable, Sendable {
    case images([EmbedImage])
    case external(EmbedExternal)
    case record(EmbedRecordRef)
    case recordWithMedia(record: EmbedRecordRef, media: Embed)
    case video(EmbedVideo)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case images, external, record, media, video
        case alt, captions, aspectRatio
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "app.bsky.embed.images":
            let images = try c.decode([EmbedImage].self, forKey: .images)
            self = .images(images)
        case "app.bsky.embed.external":
            let external = try c.decode(EmbedExternal.self, forKey: .external)
            self = .external(external)
        case "app.bsky.embed.record":
            let record = try c.decode(EmbedRecordRef.self, forKey: .record)
            self = .record(record)
        case "app.bsky.embed.recordWithMedia":
            let record = try c.decode(EmbedRecordRef.self, forKey: .record)
            let media = try c.decode(Embed.self, forKey: .media)
            self = .recordWithMedia(record: record, media: media)
        case "app.bsky.embed.video":
            let video = try c.decode(EmbedVideo.self, forKey: .video)
            self = .video(video)
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .images(let images):
            try c.encode("app.bsky.embed.images", forKey: .type)
            try c.encode(images, forKey: .images)
        case .external(let ext):
            try c.encode("app.bsky.embed.external", forKey: .type)
            try c.encode(ext, forKey: .external)
        case .record(let ref):
            try c.encode("app.bsky.embed.record", forKey: .type)
            try c.encode(ref, forKey: .record)
        case .recordWithMedia(let record, let media):
            try c.encode("app.bsky.embed.recordWithMedia", forKey: .type)
            try c.encode(record, forKey: .record)
            try c.encode(media, forKey: .media)
        case .video(let video):
            try c.encode("app.bsky.embed.video", forKey: .type)
            try c.encode(video, forKey: .video)
        case .unknown(let t):
            try c.encode(t, forKey: .type)
        }
    }
}

// MARK: - EmbedView types (resolved views returned by the API)

public struct EmbedImageView: Codable, Sendable {
    public let thumb: URL
    public let fullsize: URL
    public let alt: String
    public let aspectRatio: AspectRatio?

    public init(thumb: URL, fullsize: URL, alt: String, aspectRatio: AspectRatio?) {
        self.thumb = thumb
        self.fullsize = fullsize
        self.alt = alt
        self.aspectRatio = aspectRatio
    }
}

public struct EmbedExternalView: Codable, Sendable {
    public let uri: String
    public let title: String
    public let description: String
    public let thumb: URL?

    public init(uri: String, title: String, description: String, thumb: URL?) {
        self.uri = uri
        self.title = title
        self.description = description
        self.thumb = thumb
    }
}

public struct EmbedVideoView: Codable, Sendable {
    public let cid: CID
    /// HLS playlist URL.
    public let playlist: URL
    public let thumbnail: URL?
    public let alt: String?
    public let aspectRatio: AspectRatio?

    public init(cid: CID, playlist: URL, thumbnail: URL?, alt: String?, aspectRatio: AspectRatio?) {
        self.cid = cid
        self.playlist = playlist
        self.thumbnail = thumbnail
        self.alt = alt
        self.aspectRatio = aspectRatio
    }
}

/// The resolved content of an embedded record.
public enum EmbedRecordContent: Codable, Sendable {
    case post(EmbedViewRecord)
    case notFound(uri: ATURI)
    case blocked(uri: ATURI)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case uri, cid, author, value, labels, indexedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "app.bsky.embed.record#viewRecord":
            let record = try EmbedViewRecord(from: decoder)
            self = .post(record)
        case "app.bsky.embed.record#viewNotFound":
            let uri = try c.decode(ATURI.self, forKey: .uri)
            self = .notFound(uri: uri)
        case "app.bsky.embed.record#viewBlocked":
            let uri = try c.decode(ATURI.self, forKey: .uri)
            self = .blocked(uri: uri)
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .post(let record):
            try record.encode(to: encoder)
        case .notFound(let uri):
            try c.encode("app.bsky.embed.record#viewNotFound", forKey: .type)
            try c.encode(uri, forKey: .uri)
        case .blocked(let uri):
            try c.encode("app.bsky.embed.record#viewBlocked", forKey: .type)
            try c.encode(uri, forKey: .uri)
        case .unknown(let t):
            try c.encode(t, forKey: .type)
        }
    }
}

/// A fully resolved post record embedded as a quote.
public struct EmbedViewRecord: Codable, Sendable {
    public let uri: ATURI
    public let cid: CID
    public let author: ProfileBasic
    public let value: PostRecord
    public let labels: [Label]
    public let indexedAt: Date

    public init(uri: ATURI, cid: CID, author: ProfileBasic, value: PostRecord, labels: [Label], indexedAt: Date) {
        self.uri = uri
        self.cid = cid
        self.author = author
        self.value = value
        self.labels = labels
        self.indexedAt = indexedAt
    }
}

public struct EmbedRecordView: Codable, Sendable {
    public let record: EmbedRecordContent

    public init(record: EmbedRecordContent) {
        self.record = record
    }
}

// MARK: - EmbedView (discriminated union for API responses)

/// The resolved embed view returned inside a `PostView`.
public indirect enum EmbedView: Codable, Sendable {
    case images([EmbedImageView])
    case external(EmbedExternalView)
    case record(EmbedRecordView)
    case recordWithMedia(record: EmbedRecordView, media: EmbedView)
    case video(EmbedVideoView)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case images, external, record, media
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "app.bsky.embed.images#view":
            let images = try c.decode([EmbedImageView].self, forKey: .images)
            self = .images(images)
        case "app.bsky.embed.external#view":
            let external = try c.decode(EmbedExternalView.self, forKey: .external)
            self = .external(external)
        case "app.bsky.embed.record#view":
            let record = try c.decode(EmbedRecordView.self, forKey: .record)
            self = .record(record)
        case "app.bsky.embed.recordWithMedia#view":
            let record = try c.decode(EmbedRecordView.self, forKey: .record)
            let media = try c.decode(EmbedView.self, forKey: .media)
            self = .recordWithMedia(record: record, media: media)
        case "app.bsky.embed.video#view":
            let video = try EmbedVideoView(from: decoder)
            self = .video(video)
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .images(let images):
            try c.encode("app.bsky.embed.images#view", forKey: .type)
            try c.encode(images, forKey: .images)
        case .external(let ext):
            try c.encode("app.bsky.embed.external#view", forKey: .type)
            try c.encode(ext, forKey: .external)
        case .record(let view):
            try c.encode("app.bsky.embed.record#view", forKey: .type)
            try c.encode(view.record, forKey: .record)
        case .recordWithMedia(let record, let media):
            try c.encode("app.bsky.embed.recordWithMedia#view", forKey: .type)
            try c.encode(record.record, forKey: .record)
            try c.encode(media, forKey: .media)
        case .video(let video):
            try c.encode("app.bsky.embed.video#view", forKey: .type)
            try video.encode(to: encoder)
        case .unknown(let t):
            try c.encode(t, forKey: .type)
        }
    }
}
