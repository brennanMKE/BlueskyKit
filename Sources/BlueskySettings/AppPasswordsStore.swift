import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "AppPasswordsStore")

// MARK: - AppPasswordsStoring

public protocol AppPasswordsStoring: AnyObject, Observable, Sendable {
    var passwords: [AppPasswordView] { get }
    var isLoading: Bool { get }
    var isCreating: Bool { get }
    var error: String? { get }
    var newPassword: String? { get }

    func load() async
    func create(name: String) async
    func revoke(name: String) async
    func clearError()
    func clearNewPassword()
}

// MARK: - AppPasswordsStore

@Observable
public final class AppPasswordsStore: AppPasswordsStoring {

    public private(set) var passwords: [AppPasswordView] = []
    public private(set) var isLoading = false
    public private(set) var isCreating = false
    public private(set) var error: String?
    public private(set) var newPassword: String?

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
            logger.error("app passwords load error: \(error, privacy: .public)")
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

    public func clearError() {
        error = nil
    }

    public func clearNewPassword() {
        newPassword = nil
    }
}
