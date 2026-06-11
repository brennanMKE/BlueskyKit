import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

/// Search-based add/remove-members sheet for an owned list. Mirrors RN's
/// `ListAddRemoveUsersDialog` (`src/components/dialogs/lists/`): a
/// typeahead-backed people list where each row carries an Add / Remove
/// toggle reflecting the profile's membership in the list. Mutations go
/// through `ListDetailViewModel` (`app.bsky.graph.listitem`
/// createRecord / deleteRecord) so the People tab behind the sheet updates
/// optimistically.
struct ListAddMemberSheet: View {

    let viewModel: ListDetailViewModel

    @State private var query = ""
    /// DIDs with an in-flight add/remove so the row button can disable
    /// itself (RN disables the button while the mutation is pending).
    @State private var busyDIDs: Set<DID> = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.blueskyTheme) private var theme

    var body: some View {
        NavigationStack {
            List {
                if viewModel.searchResults.isEmpty {
                    if viewModel.isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    } else {
                        ContentUnavailableView(
                            query.trimmingCharacters(in: .whitespaces).isEmpty
                                ? "Search for people"
                                : "No Results",
                            systemImage: "person.crop.circle.badge.plus",
                            description: Text(
                                query.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? "Search for people to add to this list."
                                    : "No people found for \"\(query)\"."
                            )
                        )
                        .listRowSeparator(.hidden)
                    }
                } else {
                    ForEach(viewModel.searchResults, id: \.did) { profile in
                        resultRow(for: profile)
                    }
                }
            }
            .listStyle(.plain)
            #if os(iOS)
            // Keep the field permanently visible inside the sheet — the
            // default drawer placement starts collapsed under a sheet's
            // navigation bar.
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search for people"
            )
            #else
            .searchable(text: $query, prompt: "Search for people")
            #endif
            .onChange(of: query) { _, newValue in
                viewModel.searchMembers(query: newValue)
            }
            .navigationTitle("Add people to list")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("list-add-member-done")
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func resultRow(for profile: ProfileBasic) -> some View {
        let membershipURI = viewModel.membershipItemURI(for: profile.did)
        let isBusy = busyDIDs.contains(profile.did)

        HStack(spacing: Spacing.md) {
            AvatarView(
                url: profile.avatar,
                handle: profile.handle.rawValue,
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                if let displayName = profile.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(Typography.bodySmall.weight(.semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                }
                Text("@\(profile.handle.rawValue)")
                    .font(Typography.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            Button {
                toggleMembership(for: profile, membershipURI: membershipURI)
            } label: {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 52)
                } else {
                    Text(membershipURI == nil ? "Add" : "Remove")
                        .font(Typography.bodySmall.weight(.semibold))
                        .frame(minWidth: 52)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .clipShape(Capsule())
            .disabled(isBusy)
            .accessibilityIdentifier(
                membershipURI == nil
                    ? "list-add-member-\(profile.handle.rawValue)"
                    : "list-remove-member-\(profile.handle.rawValue)"
            )
            .accessibilityLabel(
                membershipURI == nil ? "Add user to list" : "Remove user from list"
            )
        }
        .padding(.vertical, 4)
    }

    private func toggleMembership(for profile: ProfileBasic, membershipURI: ATURI?) {
        busyDIDs.insert(profile.did)
        Task {
            if let membershipURI {
                _ = await viewModel.removeMember(itemURI: membershipURI)
            } else {
                _ = await viewModel.addMember(profile)
            }
            busyDIDs.remove(profile.did)
        }
    }
}

// MARK: - Previews

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

#Preview("ListAddMemberSheet — Light") {
    ListAddMemberSheet(viewModel: ListDetailViewModel(network: PreviewNoOpNetwork()))
        .preferredColorScheme(.light)
}

#Preview("ListAddMemberSheet — Dark") {
    ListAddMemberSheet(viewModel: ListDetailViewModel(network: PreviewNoOpNetwork()))
        .preferredColorScheme(.dark)
}
