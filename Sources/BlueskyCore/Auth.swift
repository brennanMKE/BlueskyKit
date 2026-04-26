import Foundation

// MARK: - com.atproto.server.listAppPasswords

public struct AppPasswordView: Decodable, Sendable {
    public let name: String
    public let createdAt: Date
    public let privileged: Bool?

    public init(name: String, createdAt: Date, privileged: Bool?) {
        self.name = name
        self.createdAt = createdAt
        self.privileged = privileged
    }
}

public struct ListAppPasswordsResponse: Decodable, Sendable {
    public let passwords: [AppPasswordView]
}

// MARK: - com.atproto.server.createAppPassword

public struct CreateAppPasswordRequest: Encodable, Sendable {
    public let name: String
    public let privileged: Bool?
    public init(name: String, privileged: Bool? = nil) {
        self.name = name
        self.privileged = privileged
    }
}

public struct CreateAppPasswordResponse: Decodable, Sendable {
    public let name: String
    public let password: String
    public let createdAt: Date
    public let privileged: Bool?
}

// MARK: - com.atproto.server.revokeAppPassword

public struct RevokeAppPasswordRequest: Encodable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}
