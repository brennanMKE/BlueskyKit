import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class AppPasswordsViewModel {
    public var passwords: [AppPasswordView] = []
    public var isLoading = false
    public var isCreating = false
    public var error: String?
    public var newPassword: String?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: ListAppPasswordsResponse = try await network.get(
                lexicon: "com.atproto.server.listAppPasswords",
                params: [:]
            )
            passwords = response.passwords
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func create(name: String) async {
        isCreating = true
        defer { isCreating = false }
        do {
            let response: CreateAppPasswordResponse = try await network.post(
                lexicon: "com.atproto.server.createAppPassword",
                body: CreateAppPasswordRequest(name: name)
            )
            newPassword = response.password
            passwords.append(AppPasswordView(name: response.name, createdAt: response.createdAt, privileged: response.privileged))
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func revoke(name: String) async {
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.server.revokeAppPassword",
                body: RevokeAppPasswordRequest(name: name)
            )
            passwords.removeAll { $0.name == name }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
