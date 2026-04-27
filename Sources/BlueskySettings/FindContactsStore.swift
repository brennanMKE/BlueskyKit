import Foundation
import Contacts
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "FindContactsStore")

// MARK: - FindContactsStoring

public protocol FindContactsStoring: AnyObject, Observable, Sendable {
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    var followedDIDs: Set<String> { get }

    func sendCode(phone: String) async -> Bool
    func verifyCode(phone: String, otp: String) async -> String?
    func importContacts(phone: String, token: String) async -> [ProfileBasic]?
    func follow(profile: ProfileBasic) async
}

// MARK: - FindContactsStore

@Observable
public final class FindContactsStore: FindContactsStoring {

    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var followedDIDs: Set<String> = []

    private let network: any NetworkClient
    private let accountStore: any AccountStore

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.network = network
        self.accountStore = accountStore
    }

    public func sendCode(phone: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.contact.startPhoneVerification",
                body: StartPhoneVerificationRequest(phone: phone)
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func verifyCode(phone: String, otp: String) async -> String? {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let response: VerifyPhoneResponse = try await network.post(
                lexicon: "app.bsky.contact.verifyPhone",
                body: VerifyPhoneRequest(phone: phone, code: otp)
            )
            return response.token
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func importContacts(phone: String, token: String) async -> [ProfileBasic]? {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else {
                errorMessage = "Contacts access is required to find friends."
                return nil
            }
        } catch {
            errorMessage = "Contacts access was denied."
            return nil
        }

        let phoneNumbers = await Task.detached(priority: .userInitiated) {
            let s = CNContactStore()
            let keys = [CNContactPhoneNumbersKey as CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var numbers: [String] = []
            try? s.enumerateContacts(with: request) { contact, _ in
                for ph in contact.phoneNumbers {
                    numbers.append(ph.value.stringValue)
                }
            }
            return numbers
        }.value

        guard !phoneNumbers.isEmpty else {
            errorMessage = "No phone numbers found in your contacts."
            return nil
        }

        do {
            let importResp: ImportContactsResponse = try await network.post(
                lexicon: "app.bsky.contact.importContacts",
                body: ImportContactsRequest(token: token, contacts: Array(phoneNumbers.prefix(1000)))
            )
            if importResp.matchesAndContactIndexes.isEmpty {
                return []
            }
            let matchesResp: GetContactMatchesResponse = try await network.get(
                lexicon: "app.bsky.contact.getMatches",
                params: [:]
            )
            return matchesResp.matches
        } catch {
            logger.error("import contacts error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func follow(profile: ProfileBasic) async {
        guard let currentDID = try? await accountStore.loadCurrentDID() else { return }
        followedDIDs.insert(profile.did.rawValue)
        do {
            let _: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: CreateRecordRequest(
                    repo: currentDID.rawValue,
                    collection: "app.bsky.graph.follow",
                    record: FollowRecord(subject: profile.did)
                )
            )
        } catch {
            followedDIDs.remove(profile.did.rawValue)
        }
    }
}
