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

    /// Whether the loaded list is a curation list (`app.bsky.graph.defs#curatelist`).
    /// Curate lists show Posts / People / About. Moderation lists show Members / About.
    private var isCurateList: Bool {
        viewModel.list?.purpose == "app.bsky.graph.defs#curatelist"
    }

    /// Tabs for the current list. Order mirrors RN's `sectionTitlesCurate`
    /// (`Posts`, `People`) for curate lists, plus the SwiftUI-specific About
    /// tab tracked by #0126. Mod lists drop the feed tab — RN renders only
    /// the members section for mod lists.
    private var tabs: [String] {
        isCurateList ? ["Posts", "People", "About"] : ["Members", "About"]
    }

    /// Index in `tabs` for the feed/posts content. Curate-only.
    private var feedTabIndex: Int? { isCurateList ? 0 : nil }
    /// Index in `tabs` for the members list.
    private var membersTabIndex: Int { isCurateList ? 1 : 0 }
    /// Index in `tabs` for the About metadata content.
    private var aboutTabIndex: Int { isCurateList ? 2 : 1 }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.list != nil {
                header
            }

            Picker("Tab", selection: $selectedTab) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, title in
                    Text(title).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if selectedTab == feedTabIndex {
                feedTab
            } else if selectedTab == membersTabIndex {
                membersTab
            } else if selectedTab == aboutTabIndex, let list = viewModel.list {
                aboutTab(for: list)
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
            if newValue == feedTabIndex && viewModel.feed.isEmpty {
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

    // MARK: - About Tab

    /// About tab — surfaces the list metadata that doesn't fit in the header:
    /// full description, creator handle, member count, creation date, copyable
    /// list URI, and (for moderation lists) the labels applied by the list.
    /// Mirrors the spirit of RN's metadata layout in `ProfileSubpageHeader` +
    /// `Header.tsx` — RN packs everything into the header; SwiftUI splits the
    /// long-form bits into a dedicated tab so the header stays compact.
    @ViewBuilder
    private func aboutTab(for list: ListView) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let desc = list.description, !desc.isEmpty {
                    aboutSection(title: "Description") {
                        Text(desc)
                            .font(Typography.body)
                            .foregroundStyle(theme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                aboutSection(title: "Creator") {
                    Button {
                        onProfileTap?(list.creator.did)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            AvatarView(
                                url: list.creator.avatar,
                                handle: list.creator.handle.rawValue,
                                size: 28
                            )
                            VStack(alignment: .leading, spacing: 0) {
                                if let displayName = list.creator.displayName,
                                   !displayName.isEmpty {
                                    Text(displayName)
                                        .font(Typography.bodySmall.weight(.semibold))
                                        .foregroundStyle(theme.colors.textPrimary)
                                        .lineLimit(1)
                                }
                                Text("@\(list.creator.handle.rawValue)")
                                    .font(Typography.footnote)
                                    .foregroundStyle(theme.colors.link)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let count = list.listItemCount {
                    aboutSection(title: "Members") {
                        Text(memberCountLabel(count))
                            .font(Typography.body)
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                }

                if let indexedAt = list.indexedAt {
                    aboutSection(title: "Created") {
                        Text(indexedAt.formatted(date: .long, time: .omitted))
                            .font(Typography.body)
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                }

                aboutSection(title: "List URI") {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(list.uri.rawValue)
                            .font(Typography.bodySmall.monospaced())
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Spacer(minLength: Spacing.xs)

                        Button {
                            copyToClipboard(list.uri.rawValue)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .labelStyle(.iconOnly)
                                .font(Typography.bodySmall)
                                .foregroundStyle(theme.colors.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(theme.colors.backgroundSecondary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Copy list URI")
                    }
                }

                // Moderation lists publish labels via separate labeler records
                // (`app.bsky.label.defs#label`) — the appview does not surface a
                // labels-applied set on `app.bsky.graph.defs#listView`. RN's
                // header omits this view too. If the lexicon ever grows the
                // field, render it here. For now, expose any moderation
                // labels attached directly to the list record (e.g. `!hide`).
                if list.purpose == "app.bsky.graph.defs#modlist" && !list.labels.isEmpty {
                    aboutSection(title: "Labels") {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            ForEach(list.labels, id: \.self) { label in
                                Text(label.val)
                                    .font(Typography.bodySmall)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing._2xs)
                                    .background(theme.colors.backgroundSecondary)
                                    .clipShape(Capsule())
                                    .foregroundStyle(theme.colors.textPrimary)
                            }
                        }
                    }
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func aboutSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title.uppercased())
                .font(Typography.footnote.weight(.semibold))
                .foregroundStyle(theme.colors.textTertiary)
            content()
        }
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
