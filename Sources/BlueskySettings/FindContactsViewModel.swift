import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class FindContactsViewModel {

    public enum FlowStep {
        case phoneInput
        case verifyCode(phone: String)
        case requestContacts(phone: String, token: String)
        case viewMatches([ProfileBasic])
    }

    public var step: FlowStep = .phoneInput
    public var phone = ""
    public var otp = ""
    public var isLoading: Bool { store.isLoading }
    public var errorMessage: String? { store.errorMessage }
    public var followedDIDs: Set<String> { store.followedDIDs }

    private let store: any FindContactsStoring

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.store = FindContactsStore(network: network, accountStore: accountStore)
    }

    public func sendCode() async {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if await store.sendCode(phone: trimmed) {
            step = .verifyCode(phone: trimmed)
            otp = ""
        }
    }

    public func verifyCode(phone: String) async {
        let code = otp.trimmingCharacters(in: .whitespaces)
        if let token = await store.verifyCode(phone: phone, otp: code) {
            step = .requestContacts(phone: phone, token: token)
        }
    }

    public func importContacts(phone: String, token: String) async {
        if let matches = await store.importContacts(phone: phone, token: token) {
            step = .viewMatches(matches)
        }
    }

    public func follow(profile: ProfileBasic) async {
        await store.follow(profile: profile)
    }
}
