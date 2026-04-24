import Foundation

// MARK: - Type-erased Encodable

/// Type-erases an `Encodable & Sendable` value so it can be stored in a concrete type.
public struct AnyEncodable: Encodable, Sendable {
    private let _encode: @Sendable (any Encoder) throws -> Void

    public init<T: Encodable & Sendable>(_ value: T) {
        _encode = { encoder in try value.encode(to: encoder) }
    }

    public func encode(to encoder: any Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - com.atproto.repo.uploadBlob

public struct UploadBlobResponse: Codable, Sendable {
    public let blob: BlobRef

    public init(blob: BlobRef) {
        self.blob = blob
    }
}

// MARK: - com.atproto.repo.applyWrites

/// A create-record write operation.
public struct WriteCreate: Encodable, Sendable {
    public let collection: String
    public let rkey: String?
    public let value: AnyEncodable

    private enum CodingKeys: String, CodingKey {
        case type = "$type", collection, rkey, value
    }

    public init(collection: String, rkey: String? = nil, value: some Encodable & Sendable) {
        self.collection = collection
        self.rkey = rkey
        self.value = AnyEncodable(value)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("com.atproto.repo.applyWrites#create", forKey: .type)
        try c.encode(collection, forKey: .collection)
        try c.encodeIfPresent(rkey, forKey: .rkey)
        try value.encode(to: c.superEncoder(forKey: .value))
    }
}

/// A delete-record write operation.
public struct WriteDelete: Encodable, Sendable {
    public let collection: String
    public let rkey: String

    private enum CodingKeys: String, CodingKey {
        case type = "$type", collection, rkey
    }

    public init(collection: String, rkey: String) {
        self.collection = collection
        self.rkey = rkey
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("com.atproto.repo.applyWrites#delete", forKey: .type)
        try c.encode(collection, forKey: .collection)
        try c.encode(rkey, forKey: .rkey)
    }
}

/// A union of write operations for `applyWrites`.
public enum WriteOp: Encodable, Sendable {
    case create(WriteCreate)
    case delete(WriteDelete)

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .create(let op): try op.encode(to: encoder)
        case .delete(let op): try op.encode(to: encoder)
        }
    }
}

public struct ApplyWritesRequest: Encodable, Sendable {
    public let repo: DID
    public let writes: [WriteOp]

    public init(repo: DID, writes: [WriteOp]) {
        self.repo = repo
        self.writes = writes
    }
}

public struct ApplyWritesResponse: Codable, Sendable {
    public let commit: RepoCommit?

    public init(commit: RepoCommit?) {
        self.commit = commit
    }
}

public struct RepoCommit: Codable, Sendable {
    public let cid: CID
    public let rev: String

    public init(cid: CID, rev: String) {
        self.cid = cid
        self.rev = rev
    }
}
