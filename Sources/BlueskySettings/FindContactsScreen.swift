import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

private final class PreviewNoOpAccountStore: AccountStore, @unchecked Sendable {
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { [] }
    nonisolated func load(did: DID) async throws -> StoredAccount? { nil }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { nil }
}

struct FindContactsScreen: View {

    @State private var viewModel: FindContactsViewModel

    init(network: any NetworkClient, accountStore: any AccountStore) {
        _viewModel = State(initialValue: FindContactsViewModel(network: network, accountStore: accountStore))
    }

    var body: some View {
        Group {
            switch viewModel.step {
            case .phoneInput:
                phoneInputStep
            case .verifyCode(let ph):
                verifyCodeStep(phone: ph)
            case .requestContacts(let ph, let tok):
                requestContactsStep(phone: ph, token: tok)
            case .viewMatches(let list):
                viewMatchesStep(matches: list)
            }
        }
    }

    // MARK: - Step 1: Phone Input

    private var phoneInputStep: some View {
        Form {
            Section {
                Text("Enter your phone number to find friends who are already on Bluesky.")
                    .foregroundStyle(.secondary)
            }

            Section(
                header: Text("Phone Number"),
                footer: Text("A verification code will be sent to confirm your number.")
            ) {
                TextField("+1 555 000 0000", text: $viewModel.phone)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    #endif
            }

            if let msg = viewModel.errorMessage {
                Section {
                    Label(msg, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await viewModel.sendCode() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading { ProgressView() } else { Text("Send Code") }
                        Spacer()
                    }
                }
                .disabled(viewModel.phone.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading)
            }
        }
        .navigationTitle("Find Friends")
    }

    // MARK: - Step 2: Verify Code

    private func verifyCodeStep(phone: String) -> some View {
        Form {
            Section {
                Text("Enter the 6-digit code sent to \(phone).")
                    .foregroundStyle(.secondary)
            }

            Section("Verification Code") {
                TextField("000000", text: $viewModel.otp)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    #endif
                    .multilineTextAlignment(.center)
                    .font(.title3.monospaced())
            }

            if let msg = viewModel.errorMessage {
                Section {
                    Label(msg, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await viewModel.verifyCode(phone: phone) }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading { ProgressView() } else { Text("Verify") }
                        Spacer()
                    }
                }
                .disabled(viewModel.otp.count < 6 || viewModel.isLoading)
            }

            Spacer()
        }
        .navigationTitle("Find Friends")
    }

    // MARK: - Step 3: Request Contacts

    private func requestContactsStep(phone: String, token: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Find Your Contacts")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Allow access to your contacts to find friends already on Bluesky.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if viewModel.isLoading {
                ProgressView()
            } else {
                Button("Allow Contacts Access") {
                    Task { await viewModel.importContacts(phone: phone, token: token) }
                }
                .buttonStyle(.borderedProminent)
            }
            if let msg = viewModel.errorMessage {
                Text(msg).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("Find Friends")
    }

    // MARK: - Step 4: View Matches

    private func viewMatchesStep(matches: [ProfileBasic]) -> some View {
        Group {
            if matches.isEmpty {
                ContentUnavailableView(
                    "No Matches Found",
                    systemImage: "person.2.slash",
                    description: Text("None of your contacts are on Bluesky yet.")
                )
            } else {
                List(matches, id: \.did) { profile in
                    HStack(spacing: Spacing.sm) {
                        AvatarView(url: profile.avatar, handle: profile.handle.rawValue, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            if let name = profile.displayName {
                                Text(name).fontWeight(.semibold)
                            }
                            Text("@\(profile.handle.rawValue)")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        Spacer()
                        let isFollowing = viewModel.followedDIDs.contains(profile.did.rawValue)
                        Button(isFollowing ? "Following" : "Follow") {
                            Task { await viewModel.follow(profile: profile) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isFollowing)
                    }
                }
            }
        }
        .navigationTitle("People You Know")
    }
}

// MARK: - Previews

#Preview("FindContactsScreen — Light") {
    NavigationStack {
        FindContactsScreen(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("FindContactsScreen — Dark") {
    NavigationStack {
        FindContactsScreen(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.dark)
}
