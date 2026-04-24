import Foundation

// MARK: - com.atproto.moderation.createReport

/// Subject pointing to an entire account (repo).
public struct ReportSubjectRepo: Encodable, Sendable {
    public let did: DID

    private enum CodingKeys: String, CodingKey {
        case type = "$type", did
    }

    public init(did: DID) {
        self.did = did
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("com.atproto.admin.defs#repoRef", forKey: .type)
        try c.encode(did, forKey: .did)
    }
}

/// Subject pointing to a specific record.
public struct ReportSubjectRecord: Encodable, Sendable {
    public let uri: ATURI
    public let cid: CID

    private enum CodingKeys: String, CodingKey {
        case type = "$type", uri, cid
    }

    public init(uri: ATURI, cid: CID) {
        self.uri = uri
        self.cid = cid
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("com.atproto.repo.strongRef", forKey: .type)
        try c.encode(uri, forKey: .uri)
        try c.encode(cid, forKey: .cid)
    }
}

public struct CreateReportRequest: Encodable, Sendable {
    /// e.g. `"com.atproto.moderation.defs#reasonSpam"` or `"#reasonViolation"`.
    public let reasonType: String
    public let reason: String?
    public let subject: AnyEncodable

    public init(reasonType: String, reason: String? = nil, subject: some Encodable & Sendable) {
        self.reasonType = reasonType
        self.reason = reason
        self.subject = AnyEncodable(subject)
    }
}

public struct CreateReportResponse: Codable, Sendable {
    public let id: Int
    public let reasonType: String
    public let reason: String?
    public let reportedBy: DID
    public let createdAt: Date

    public init(id: Int, reasonType: String, reason: String?, reportedBy: DID, createdAt: Date) {
        self.id = id
        self.reasonType = reasonType
        self.reason = reason
        self.reportedBy = reportedBy
        self.createdAt = createdAt
    }
}

// MARK: - app.bsky.labeler.defs#labelerView

/// A labeler service view returned by `app.bsky.labeler.getServices`.
public struct LabelerView: Codable, Sendable {
    public let uri: ATURI
    public let cid: CID
    public let creator: ProfileView
    public let likeCount: Int?
    public let labels: [Label]
    public let indexedAt: Date

    public init(
        uri: ATURI,
        cid: CID,
        creator: ProfileView,
        likeCount: Int?,
        labels: [Label] = [],
        indexedAt: Date
    ) {
        self.uri = uri
        self.cid = cid
        self.creator = creator
        self.likeCount = likeCount
        self.labels = labels
        self.indexedAt = indexedAt
    }
}
