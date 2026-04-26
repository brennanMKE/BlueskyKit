import SwiftUI
import Contacts
import BlueskyCore
import BlueskyKit
import BlueskyUI

struct FindContactsScreen: View {
    private enum FlowStep {
        case phoneInput
        case verifyCode(phone: String)
        case requestContacts(phone: String, token: String)
        case viewMatches([ProfileBasic])
    }

    @State private var step: FlowStep = .phoneInput
    @State private var phone = ""
    @State private var otp = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var followedDIDs: Set<String> = []

    let network: any NetworkClient
    let accountStore: any AccountStore

    var body: some View {
        Group {
            switch step {
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
                TextField("+1 555 000 0000", text: $phone)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    #endif
            }

            if let msg = errorMessage {
                Section {
                    Label(msg, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await sendCode() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading { ProgressView() } else { Text("Send Code") }
                        Spacer()
                    }
                }
                .disabled(phone.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
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
                TextField("000000", text: $otp)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    #endif
                    .multilineTextAlignment(.center)
                    .font(.title3.monospaced())
            }

            if let msg = errorMessage {
                Section {
                    Label(msg, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await verifyCode(phone: phone) }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading { ProgressView() } else { Text("Verify") }
                        Spacer()
                    }
                }
                .disabled(otp.count < 6 || isLoading)

                Button("Resend Code") {
                    Task { await sendCode() }
                }
                .disabled(isLoading)
            }
        }
        .navigationTitle("Verify Number")
    }

    // MARK: - Step 3: Import Contacts

    private func requestContactsStep(phone: String, token: String) -> some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            VStack(spacing: Spacing.sm) {
                Text("Find People You Know")
                    .font(.title2.bold())

                Text("Bluesky hashes your contacts' phone numbers and checks for matches. Names and other contact info are never uploaded.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.xl)
            }

            if let msg = errorMessage {
                Text(msg)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }

            Button {
                Task { await importContacts(phone: phone, token: token) }
            } label: {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Find Friends from Contacts", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, Spacing.xl)
            .disabled(isLoading)

            Spacer()
        }
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
                        let isFollowing = followedDIDs.contains(profile.did.rawValue)
                        Button(isFollowing ? "Following" : "Follow") {
                            Task { await follow(profile: profile) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isFollowing)
                    }
                }
            }
        }
        .navigationTitle("People You Know")
    }

    // MARK: - Network Actions

    private func sendCode() async {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.contact.startPhoneVerification",
                body: StartPhoneVerificationRequest(phone: trimmed)
            )
            step = .verifyCode(phone: trimmed)
            otp = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyCode(phone: String) async {
        let code = otp.trimmingCharacters(in: .whitespaces)
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let response: VerifyPhoneResponse = try await network.post(
                lexicon: "app.bsky.contact.verifyPhone",
                body: VerifyPhoneRequest(phone: phone, code: code)
            )
            step = .requestContacts(phone: phone, token: response.token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importContacts(phone: String, token: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else {
                errorMessage = "Contacts access is required to find friends."
                return
            }
        } catch {
            errorMessage = "Contacts access was denied."
            return
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
            return
        }

        do {
            let importResp: ImportContactsResponse = try await network.post(
                lexicon: "app.bsky.contact.importContacts",
                body: ImportContactsRequest(token: token, contacts: Array(phoneNumbers.prefix(1000)))
            )
            if importResp.matchesAndContactIndexes.isEmpty {
                step = .viewMatches([])
            } else {
                let matchesResp: GetContactMatchesResponse = try await network.get(
                    lexicon: "app.bsky.contact.getMatches",
                    params: [:]
                )
                step = .viewMatches(matchesResp.matches)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func follow(profile: ProfileBasic) async {
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
