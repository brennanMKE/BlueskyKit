import Foundation
import OSLog
import Security
import BlueskyCore
import BlueskyKit

nonisolated private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "KeychainAccountStore"
)

/// Keychain-backed implementation of `AccountStore`.
///
/// Each `StoredAccount` is stored as a JSON blob under `kSecClassGenericPassword`,
/// keyed `"account:<did>"`. The active DID is stored separately under `"current-did"`.
/// `kSecAttrAccessibleAfterFirstUnlock` allows session restore during background fetch.
public actor KeychainAccountStore: AccountStore {

    private let service: String
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(service: String = "app.bsky") {
        self.service = service
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - AccountStore (nonisolated wrappers hop to actor executor)

    public nonisolated func save(_ account: StoredAccount) async throws {
        try await _save(account)
    }

    public nonisolated func loadAll() async throws -> [StoredAccount] {
        try await _loadAll()
    }

    public nonisolated func load(did: DID) async throws -> StoredAccount? {
        try await _load(did: did)
    }

    public nonisolated func remove(did: DID) async throws {
        try await _remove(did: did)
    }

    public nonisolated func setCurrentDID(_ did: DID?) async throws {
        try await _setCurrentDID(did)
    }

    public nonisolated func loadCurrentDID() async throws -> DID? {
        try await _loadCurrentDID()
    }

    // MARK: - Actor-isolated implementation

    private func _save(_ account: StoredAccount) throws {
        let key = accountKey(for: account.account.did)
        let data = try encoder.encode(account)
        logger.debug("saving account key=\(key, privacy: .public)")

        if try _load(did: account.account.did) != nil {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key
            ]
            let update: [CFString: Any] = [kSecValueData: data]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            logger.debug("SecItemUpdate status=\(status, privacy: .public)")
            guard status == errSecSuccess else { throw KeychainError.updateFailed(status) }
        } else {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            logger.debug("SecItemAdd status=\(status, privacy: .public)")
            guard status == errSecSuccess else { throw KeychainError.addFailed(status) }
        }
    }

    private func _loadAll() throws -> [StoredAccount] {
        // On macOS, kSecMatchLimitAll + kSecReturnData returns errSecParam (-50).
        // Fetch attributes only first, then load each account's data individually.
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        logger.debug("_loadAll SecItemCopyMatching status=\(status, privacy: .public)")

        if status == errSecItemNotFound {
            logger.debug("_loadAll: no items found in keychain")
            return []
        }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            logger.error("_loadAll read failed, status=\(status, privacy: .public)")
            throw KeychainError.readFailed(status)
        }

        let acctKey = kSecAttrAccount as String
        let accounts = try items.compactMap { item -> StoredAccount? in
            guard let accountAttr = item[acctKey] as? String,
                  accountAttr.hasPrefix("account:") else { return nil }
            let rawDID = String(accountAttr.dropFirst("account:".count))
            return try _load(did: DID(rawValue: rawDID))
        }
        logger.debug("_loadAll loaded \(accounts.count, privacy: .public) accounts")
        return accounts
    }

    private func _load(did: DID) throws -> StoredAccount? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: accountKey(for: did),
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.readFailed(status)
        }

        return try decoder.decode(StoredAccount.self, from: data)
    }

    private func _remove(did: DID) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: accountKey(for: did)
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    private func _setCurrentDID(_ did: DID?) throws {
        let key = "current-did"
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let did else {
            logger.debug("setCurrentDID: cleared current DID")
            return
        }

        let data = Data(did.rawValue.utf8)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        logger.debug("setCurrentDID SecItemAdd status=\(status, privacy: .public) did=\(did.rawValue, privacy: .public)")
        guard status == errSecSuccess else { throw KeychainError.addFailed(status) }
    }

    private func _loadCurrentDID() throws -> DID? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "current-did",
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        logger.debug("_loadCurrentDID SecItemCopyMatching status=\(status, privacy: .public)")

        if status == errSecItemNotFound {
            logger.debug("_loadCurrentDID: not found")
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let rawValue = String(data: data, encoding: .utf8) else {
            logger.error("_loadCurrentDID read failed, status=\(status, privacy: .public)")
            throw KeychainError.readFailed(status)
        }

        logger.debug("_loadCurrentDID found did=\(rawValue, privacy: .public)")
        return DID(rawValue: rawValue)
    }

    private func accountKey(for did: DID) -> String {
        "account:\(did.rawValue)"
    }
}

// MARK: - KeychainError

public enum KeychainError: Error, Sendable {
    case addFailed(OSStatus)
    case updateFailed(OSStatus)
    case deleteFailed(OSStatus)
    case readFailed(OSStatus)
}
