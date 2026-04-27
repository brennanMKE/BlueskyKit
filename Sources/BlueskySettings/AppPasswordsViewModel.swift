import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class AppPasswordsViewModel {

    public var passwords: [AppPasswordView] { store.passwords }
    public var isLoading: Bool { store.isLoading }
    public var isCreating: Bool { store.isCreating }
    public var error: String? { store.error }
    public var newPassword: String? { store.newPassword }

    private let store: any AppPasswordsStoring

    public init(network: any NetworkClient) {
        self.store = AppPasswordsStore(network: network)
    }

    public func load() async { await store.load() }
    public func create(name: String) async { await store.create(name: name) }
    public func revoke(name: String) async { await store.revoke(name: name) }
    public func clearError() { store.clearError() }
    public func clearNewPassword() { store.clearNewPassword() }
}
