import SwiftUI
import BlueskyCore
import BlueskyKit

/// Displays all accounts stored on the device and lets the user switch or sign in to one.
///
/// Presented when the app has at least one stored account. The user can tap an account
/// to resume it, or tap "Use a different account" to fall through to `LoginView`.
public struct AccountPickerView: View {

    private let session: SessionManager
    private let onAccountSelected: () -> Void
    private let onAddAccount: () -> Void

    @State private var isLoading: DID? = nil
    @State private var errorMessage: String? = nil

    public init(
        session: SessionManager,
        onAccountSelected: @escaping () -> Void,
        onAddAccount: @escaping () -> Void
    ) {
        self.session = session
        self.onAccountSelected = onAccountSelected
        self.onAddAccount = onAddAccount
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            accountList
            Divider()
            footer
        }
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
            Text("Choose an account")
                .font(.title3.bold())
            Text("Select an account to sign in")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 20)
    }

    private var accountList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(session.accounts) { account in
                    AccountRow(
                        account: account,
                        isCurrent: session.currentAccount?.did == account.did,
                        isLoading: isLoading == account.did,
                        onSelect: { Task { await select(account: account) } },
                        onRemove: { Task { await remove(account: account) } }
                    )
                    Divider()
                        .padding(.leading, 64)
                }
            }
        }
        .frame(maxHeight: 360)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }
            Button(action: onAddAccount) {
                Label("Use a different account", systemImage: "plus.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.top, 16)
    }

    // MARK: - Actions

    @MainActor
    private func select(account: Account) async {
        isLoading = account.did
        errorMessage = nil
        defer { isLoading = nil }

        do {
            try await session.switchAccount(to: account.did)
            onAccountSelected()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func remove(account: Account) async {
        do {
            try await session.removeAccount(did: account.did)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - AccountRow

private struct AccountRow: View {
    let account: Account
    let isCurrent: Bool
    let isLoading: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            avatarView
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName ?? account.handle.rawValue)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("@\(account.handle.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove account", systemImage: "trash")
            }
        }
    }

    private var avatarView: some View {
        Group {
            if let url = account.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        Circle()
            .fill(.blue.gradient)
            .overlay(
                Text(initials)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    private var initials: String {
        let name = account.displayName ?? account.handle.rawValue
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Previews

private final class PreviewMultiAccountStore: AccountStore, @unchecked Sendable {
    private let stub: [StoredAccount] = [
        StoredAccount(
            account: Account(
                did: DID(rawValue: "did:plc:alice"),
                handle: Handle(rawValue: "alice.bsky.social"),
                displayName: "Alice",
                avatarURL: nil,
                serviceEndpoint: URL(string: "https://bsky.social")!,
                email: "alice@example.com",
                emailConfirmed: true
            ),
            accessJwt: "", refreshJwt: ""
        ),
        StoredAccount(
            account: Account(
                did: DID(rawValue: "did:plc:bob"),
                handle: Handle(rawValue: "bob.bsky.social"),
                displayName: "Bob",
                avatarURL: nil,
                serviceEndpoint: URL(string: "https://bsky.social")!,
                email: nil,
                emailConfirmed: nil
            ),
            accessJwt: "", refreshJwt: ""
        ),
    ]
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { stub }
    nonisolated func load(did: DID) async throws -> StoredAccount? { stub.first { $0.account.did == did } }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { DID(rawValue: "did:plc:alice") }
}

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

#Preview("AccountPickerView — Light") {
    let session = SessionManager(accountStore: PreviewMultiAccountStore(), network: PreviewNoOpNetwork())
    AccountPickerView(session: session, onAccountSelected: {}, onAddAccount: {})
        .task { await session.restoreLastSession() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .preferredColorScheme(.light)
}

#Preview("AccountPickerView — Dark") {
    let session = SessionManager(accountStore: PreviewMultiAccountStore(), network: PreviewNoOpNetwork())
    AccountPickerView(session: session, onAccountSelected: {}, onAddAccount: {})
        .task { await session.restoreLastSession() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .preferredColorScheme(.dark)
}
