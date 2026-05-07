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

// MARK: - com.atproto.server.describeServer

/// Output of `com.atproto.server.describeServer`. Used by the signup flow to
/// determine whether the chosen PDS requires invite codes, captchas, or has a
/// non-standard handle suffix.
public struct DescribeServerResponse: Decodable, Sendable {
    public let did: String?
    public let availableUserDomains: [String]
    public let inviteCodeRequired: Bool?
    public let phoneVerificationRequired: Bool?
    public let links: Links?
    public let contact: Contact?

    public struct Links: Decodable, Sendable {
        public let privacyPolicy: String?
        public let termsOfService: String?
    }

    public struct Contact: Decodable, Sendable {
        public let email: String?
    }

    public init(
        did: String?,
        availableUserDomains: [String],
        inviteCodeRequired: Bool?,
        phoneVerificationRequired: Bool?,
        links: Links?,
        contact: Contact?
    ) {
        self.did = did
        self.availableUserDomains = availableUserDomains
        self.inviteCodeRequired = inviteCodeRequired
        self.phoneVerificationRequired = phoneVerificationRequired
        self.links = links
        self.contact = contact
    }
}

// MARK: - com.atproto.server.createAccount

public struct CreateAccountRequest: Encodable, Sendable {
    public let email: String
    public let handle: String
    public let password: String
    public let inviteCode: String?
    public let verificationCode: String?
    public let verificationPhone: String?

    public init(
        email: String,
        handle: String,
        password: String,
        inviteCode: String? = nil,
        verificationCode: String? = nil,
        verificationPhone: String? = nil
    ) {
        self.email = email
        self.handle = handle
        self.password = password
        self.inviteCode = inviteCode
        self.verificationCode = verificationCode
        self.verificationPhone = verificationPhone
    }
}

public struct CreateAccountResponse: Decodable, Sendable {
    public let did: String
    public let handle: String
    public let accessJwt: String
    public let refreshJwt: String
}

// MARK: - com.atproto.server.requestPasswordReset

/// Request body for `com.atproto.server.requestPasswordReset`. The server
/// emails a reset code to the supplied address; the response body is empty
/// on success (use `EmptyResponse`).
public struct RequestPasswordResetRequest: Encodable, Sendable {
    public let email: String
    public init(email: String) {
        self.email = email
    }
}

// MARK: - com.atproto.server.resetPassword

/// Request body for `com.atproto.server.resetPassword`. Caller supplies the
/// reset code received by email plus the new password; the response body is
/// empty on success (use `EmptyResponse`).
public struct ResetPasswordRequest: Encodable, Sendable {
    public let token: String
    public let password: String
    public init(token: String, password: String) {
        self.token = token
        self.password = password
    }
}

// MARK: - Password reset helpers

public enum PasswordResetValidation {
    /// Trims whitespace and uppercases the supplied reset code, then verifies
    /// it matches the canonical base32 `XXXXX-XXXXX` shape used by Bluesky
    /// password reset emails. If the user pasted a 10-character code without
    /// the hyphen, inserts the hyphen automatically. Mirrors RN
    /// `checkAndFormatResetCode` in `lib/strings/password.ts`.
    ///
    /// Returns the formatted code on success, or `nil` if the input is not a
    /// well-formed reset code.
    public static func checkAndFormatResetCode(_ value: String) -> String? {
        var fixed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Strip any internal whitespace the user may have pasted.
        fixed = fixed.filter { !$0.isWhitespace }
        // Insert the hyphen if the user pasted 10 chars without one.
        if fixed.count == 10 {
            let mid = fixed.index(fixed.startIndex, offsetBy: 5)
            fixed = String(fixed[..<mid]) + "-" + String(fixed[mid...])
        }
        // Bluesky reset codes are RFC 4648 base32 (A-Z, 2-7).
        let pattern = #"^[A-Z2-7]{5}-[A-Z2-7]{5}$"#
        guard fixed.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        return fixed
    }
}

// MARK: - Signup helpers

public enum SignupValidation {
    /// `com.atproto.identity` rules: 3..253 chars total, only a-z 0-9 and `-`,
    /// no leading/trailing hyphen on the user-domain portion, max 18 chars in
    /// the front segment to match Bluesky's UI validation.
    public static let maxFrontHandleLength = 18
    public static let maxFullHandleLength = 253
    public static let minPasswordLength = 8
    public static let minSignupAge = 13

    /// Joins a username with a service domain like `bsky.social` into a full
    /// handle. Mirrors RN `createFullHandle`.
    public static func createFullHandle(_ username: String, _ domain: String) -> String {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let dom = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if user.isEmpty { return dom }
        if dom.isEmpty { return user }
        return "\(user).\(dom)"
    }

    public struct HandleCheck: Sendable, Equatable {
        public let frontLengthNotTooLong: Bool
        public let totalLength: Bool
        public let handleChars: Bool
        public let hyphenStartOrEnd: Bool
        public var overall: Bool {
            frontLengthNotTooLong && totalLength && handleChars && hyphenStartOrEnd
                && !isEmpty
        }
        public let isEmpty: Bool
    }

    public static func validateServiceHandle(_ username: String, _ domain: String) -> HandleCheck {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = createFullHandle(user, domain)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let charsOk = !user.isEmpty &&
            user.unicodeScalars.allSatisfy { allowed.contains($0) }
        let hyphenOk = !user.hasPrefix("-") && !user.hasSuffix("-")
        let frontLenOk = user.count <= maxFrontHandleLength
        let totalLenOk = full.count <= maxFullHandleLength && full.count >= 3
        return HandleCheck(
            frontLengthNotTooLong: frontLenOk,
            totalLength: totalLenOk,
            handleChars: charsOk,
            hyphenStartOrEnd: hyphenOk,
            isEmpty: user.isEmpty
        )
    }

    /// Returns true if the date-of-birth indicates age >= `minimumYears`.
    public static func isOverAge(_ birthDate: Date, minimumYears: Int = minSignupAge, now: Date = Date()) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        guard let years = calendar.dateComponents([.year], from: birthDate, to: now).year else {
            return false
        }
        return years >= minimumYears
    }

    /// Loose RFC-5322-ish email check, mirroring what RN's `email-validator`
    /// accepts for signup.
    public static func isLikelyEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Local@domain.tld with at least one `.` in the domain portion
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}
