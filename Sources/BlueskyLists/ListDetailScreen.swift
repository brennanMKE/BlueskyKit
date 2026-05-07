import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyModeration
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

struct ListDetailScreen: View {

    @State private var viewModel: ListDetailViewModel
    @State private var selectedTab = 0
    @State private var showSubscribeSheet = false
    @State private var showReportSheet = false
    private let listURI: ATURI
    private let network: any NetworkClient
    private let onProfileTap: ((DID) -> Void)?

    @Environment(\.blueskyTheme) private var theme

    init(
        listURI: ATURI,
        network: any NetworkClient,
        onProfileTap: ((DID) -> Void)? = nil
    ) {
        self.listURI = listURI
        self.network = network
        self.onProfileTap = onProfileTap
        _viewModel = State(initialValue: ListDetailViewModel(network: network))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.list != nil {
                header
            }

            Picker("Tab", selection: $selectedTab) {
                Text("Members").tag(0)
                Text("Feed").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if selectedTab == 0 {
                membersTab
            } else {
                feedTab
            }
        }
        .navigationTitle(viewModel.list?.name ?? "List")
        .overlay {
            if viewModel.isLoading && viewModel.list == nil {
                ProgressView()
            }
        }
        .task { await viewModel.load(listURI: listURI) }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 1 && viewModel.feed.isEmpty {
                Task { await viewModel.loadFeed() }
            }
        }
        .sheet(isPresented: $showReportSheet) {
            if let list = viewModel.list {
                ReportDialog(
                    subject: .record(uri: list.uri, cid: list.cid),
                    onSubmit: { reasonType, reason in
                        let req = CreateReportRequest(
                            reasonType: reasonType,
                            reason: reason,
                            subject: ReportSubjectRecord(uri: list.uri, cid: list.cid)
                        )
                        let _: CreateReportResponse = try await network.post(
                            lexicon: "com.atproto.moderation.createReport",
                            body: req
                        )
                    },
                    onDismiss: { showReportSheet = false }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        guard let list = viewModel.list else {
            return AnyView(EmptyView())
        }
        return AnyView(
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    AvatarView(url: list.avatar, handle: list.name, size: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: Spacing._2xs) {
                        HStack(spacing: Spacing.xs) {
                            Text(list.name)
                                .font(Typography.title)
                                .foregroundStyle(theme.colors.textPrimary)
                                .lineLimit(2)
                            PurposeBadge(purpose: list.purpose)
                        }

                        Button {
                            onProfileTap?(list.creator.did)
                        } label: {
                            Text("by @\(list.creator.handle.rawValue)")
                                .font(Typography.bodySmall)
                                .foregroundStyle(theme.colors.link)
                        }
                        .buttonStyle(.plain)

                        if let count = list.listItemCount {
                            Text(memberCountLabel(count))
                                .font(Typography.footnote)
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)

                if let desc = list.description, !desc.isEmpty {
                    Text(desc)
                        .font(Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                        .padding(.horizontal, Spacing.lg)
                }

                HStack(spacing: Spacing.sm) {
                    primaryActionButton(for: list)
                    moreOptionsMenu(for: list)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.sm)

                Divider()
            }
            .background(theme.colors.background)
        )
    }

    private func memberCountLabel(_ count: Int) -> String {
        count == 1 ? "1 user" : "\(count) users"
    }

    // MARK: - Primary action

    @ViewBuilder
    private func primaryActionButton(for list: ListView) -> some View {
        let isCurate = list.purpose == "app.bsky.graph.defs#curatelist"
        let isMod = list.purpose == "app.bsky.graph.defs#modlist"
        let isMuting = list.viewer?.muted == true

        if isCurate {
            // RN's `Header` toggles a saved-feed entry here. The SwiftUI app
            // does not yet propagate `preferences` into `ListDetailScreen`; the
            // Pin/Unpin wiring lands with the saved-feeds plumbing covered by
            // #0060. Show the affordance disabled so the slot is reserved.
            Button {
                // No-op until preferences flow into BlueskyLists.
            } label: {
                Label("Pin to home", systemImage: "pin")
                    .font(Typography.bodySmall.weight(.semibold))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(theme.colors.link)
            .clipShape(Capsule())
            .disabled(true)
            .help("Pin to home (coming with saved-feed preferences)")
        } else if isMod {
            if isMuting {
                Button {
                    Task { await viewModel.unsubscribeMute() }
                } label: {
                    Text("Unmute")
                        .font(Typography.bodySmall.weight(.semibold))
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .clipShape(Capsule())
            } else {
                Button {
                    showSubscribeSheet = true
                } label: {
                    Text("Subscribe")
                        .font(Typography.bodySmall.weight(.semibold))
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(theme.colors.link)
                .clipShape(Capsule())
                .confirmationDialog(
                    "Subscribe to this moderation list?",
                    isPresented: $showSubscribeSheet,
                    titleVisibility: .visible
                ) {
                    Button("Mute accounts on this list") {
                        Task { await viewModel.subscribeMute() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Muting is private. Muted accounts can interact with you, but you will not see their posts or receive notifications from them.")
                }
            }
        }
    }

    // MARK: - More options menu

    @ViewBuilder
    private func moreOptionsMenu(for list: ListView) -> some View {
        let shareURL = listShareURL(for: list)
        let isMod = list.purpose == "app.bsky.graph.defs#modlist"
        let isMuting = list.viewer?.muted == true

        Menu {
            if let url = shareURL {
                ShareLink(item: url) {
                    Label("Share list", systemImage: "square.and.arrow.up")
                }
                Button {
                    copyToClipboard(url.absoluteString)
                } label: {
                    Label("Copy link to list", systemImage: "link")
                }
            }

            Divider()

            if isMod && isMuting {
                Button {
                    Task { await viewModel.unsubscribeMute() }
                } label: {
                    Label("Unmute list", systemImage: "speaker.wave.2")
                }
            }

            Button(role: .destructive) {
                showReportSheet = true
            } label: {
                Label("Report list", systemImage: "flag")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 32, height: 32)
                .background(theme.colors.backgroundSecondary)
                .clipShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .help("More options")
    }

    private func listShareURL(for list: ListView) -> URL? {
        guard let rkey = list.uri.rkey else { return nil }
        let handle = list.creator.handle.rawValue.isEmpty
            ? list.creator.did.rawValue
            : list.creator.handle.rawValue
        return URL(string: "https://bsky.app/profile/\(handle)/lists/\(rkey)")
    }

    private func copyToClipboard(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #endif
    }

    // MARK: - Members Tab

    private var membersTab: some View {
        List {
            if viewModel.members.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Members",
                    systemImage: "person.3",
                    description: Text("This list has no members yet.")
                )
            } else {
                ForEach(viewModel.members, id: \.uri) { item in
                    MemberRow(item: item)
                        .onAppear {
                            if item.uri == viewModel.members.last?.uri {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Feed Tab

    private var feedTab: some View {
        List {
            if viewModel.feed.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Posts",
                    systemImage: "text.bubble",
                    description: Text("No posts from list members yet.")
                )
            } else {
                ForEach(viewModel.feed, id: \.post.uri) { feedPost in
                    PostCard(item: feedPost)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .onAppear {
                            if feedPost.post.uri == viewModel.feed.last?.post.uri {
                                Task { await viewModel.loadMoreFeed() }
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - PurposeBadge

private struct PurposeBadge: View {
    let purpose: String

    private var label: String {
        purpose == "app.bsky.graph.defs#modlist" ? "Moderation" : "Curate"
    }

    private var color: Color {
        purpose == "app.bsky.graph.defs#modlist" ? .orange : .blue
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - MemberRow

private struct MemberRow: View {
    let item: ListItemView

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: item.subject.avatar, handle: item.subject.handle.rawValue, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                if let displayName = item.subject.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text("@\(item.subject.handle.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let desc = item.subject.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("ListDetailScreen — Light") {
    NavigationStack {
        ListDetailScreen(
            listURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.graph.list/abc"),
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("ListDetailScreen — Dark") {
    NavigationStack {
        ListDetailScreen(
            listURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.graph.list/abc"),
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.dark)
}
