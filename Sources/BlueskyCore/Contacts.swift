import Foundation

// MARK: - app.bsky.contact.startPhoneVerification

public struct StartPhoneVerificationRequest: Encodable, Sendable {
    public let phone: String
    public init(phone: String) { self.phone = phone }
}

// MARK: - app.bsky.contact.verifyPhone

public struct VerifyPhoneRequest: Encodable, Sendable {
    public let phone: String
    public let code: String
    public init(phone: String, code: String) { self.phone = phone; self.code = code }
}

public struct VerifyPhoneResponse: Decodable, Sendable {
    public let token: String
}

// MARK: - app.bsky.contact.importContacts

public struct ImportContactsRequest: Encodable, Sendable {
    public let token: String
    public let contacts: [String]
    public init(token: String, contacts: [String]) { self.token = token; self.contacts = contacts }
}

public struct ContactMatchItem: Decodable, Sendable {
    public let matchIndex: Int
    public let did: String
}

public struct ImportContactsResponse: Decodable, Sendable {
    public let matchesAndContactIndexes: [ContactMatchItem]
}

// MARK: - app.bsky.contact.getMatches

public struct GetContactMatchesResponse: Decodable, Sendable {
    public let matches: [ProfileBasic]
    public let cursor: String?
}

// MARK: - app.bsky.contact.getSyncStatus

public struct ContactSyncStatus: Decodable, Sendable {
    public let matchesCount: Int?
    public let syncedAt: String?
}

public struct GetContactSyncStatusResponse: Decodable, Sendable {
    public let syncStatus: ContactSyncStatus?
}

// MARK: - app.bsky.contact.dismissMatch

public struct DismissMatchRequest: Encodable, Sendable {
    public let subject: String
    public init(subject: DID) { self.subject = subject.rawValue }
}
