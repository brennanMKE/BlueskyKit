import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

/// Full-page profile view: banner + avatar header, tab strip, post feed.
public struct ProfileScreen: View {

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private let viewerDID: DID?

    @State private var viewModel: ProfileViewModel
    @State private var selectedTab: ProfileTab = .posts
    @State private var showEditProfile = false
    @State private var threadURI: ATURI?

    public init(
        actorDID: DID,
        network: any NetworkClient,
        accountStore: any AccountStore,
        viewerDID: DID? = nil
    ) {
        self.network = network
        self.accountStore = accountStore
        self.viewerDID = viewerDID
        _viewModel = State(wrappedValue: ProfileViewModel(
            network: network,
            accountStore: accountStore,
            actorDID: actorDID
        ))
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    feedContent
                } header: {
                    profileHeader
                    tabStrip
                }
            }
        }
        .navigationTitle(viewModel.profile?.handle.rawValue ?? "Profile")
        .task {
            await viewModel.loadProfile()
            await loadCurrentTab(selectedTab)
        }
        .onChange(of: selectedTab) { _, newTab in
            Task { await loadCurrentTab(newTab) }
        }
        .navigationDestination(isPresented: Binding(
            get: { threadURI != nil },
            set: { if !$0 { threadURI = nil } }
        )) {
            if let uri = threadURI {
                ThreadPlaceholder(uri: uri)
            }
        }
        .sheet(isPresented: $showEditProfile) {
            if let profile = viewModel.profile {
                EditProfileSheet(
                    displayName: profile.displayName ?? "",
                    description: profile.description ?? "",
                    onSave: { name, desc in
                        Task { try? await viewModel.updateProfile(displayName: name, description: desc) }
                    }
                )
            }
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        ProfileHeaderView(
            profile: viewModel.profile,
            isOwnProfile: viewModel.actorDID == viewerDID,
            knownFollowers: viewModel.knownFollowers,
            onFollow:      { Task { await viewModel.follow() } },
            onUnfollow:    { Task { await viewModel.unfollow() } },
            onBlock:       { Task { await viewModel.block() } },
            onUnblock:     { Task { await viewModel.unblock() } },
            onMute:        { Task { await viewModel.mute() } },
            onUnmute:      { Task { await viewModel.unmute() } },
            onEditProfile: { showEditProfile = true }
        )
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        Picker("", selection: $selectedTab) {
            ForEach(ProfileTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Tab loading

    private func loadCurrentTab(_ tab: ProfileTab) async {
        switch tab {
        case .feeds:
            await viewModel.loadFeeds()
        case .lists:
            await viewModel.loadLists()
        default:
            await viewModel.loadFeed(tab: tab)
        }
    }

    // MARK: - Feed content

    @ViewBuilder
    private var feedContent: some View {
        switch selectedTab {
        case .feeds:
            feedsTabContent
        case .lists:
            listsTabContent
        default:
            postsTabContent
        }
    }

    @ViewBuilder
    private var postsTabContent: some View {
        let posts = viewModel.posts(for: selectedTab)
        if posts.isEmpty && viewModel.isLoadingFeed(for: selectedTab) {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(40)
        } else if posts.isEmpty {
            Text("No posts")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(40)
        } else {
            ForEach(posts, id: \.post.uri) { item in
                PostCard(item: item, actions: postActions(for: item))
                Divider()
                    .onAppear {
                        if item.post.uri == posts.last?.post.uri {
                            Task { await viewModel.loadMoreFeed(tab: selectedTab) }
                        }
                    }
            }
            if viewModel.isLoadingFeed(for: selectedTab) {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            }
        }
    }

    @ViewBuilder
    private var feedsTabContent: some View {
        if viewModel.actorFeeds.isEmpty {
            Text("No feeds")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(40)
        } else {
            ForEach(viewModel.actorFeeds, id: \.uri) { feed in
                FeedCard(feed: feed)
                Divider()
            }
        }
    }

    @ViewBuilder
    private var listsTabContent: some View {
        if viewModel.actorLists.isEmpty {
            Text("No lists")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(40)
        } else {
            ForEach(viewModel.actorLists, id: \.uri) { list in
                ListCard(list: list)
                Divider()
            }
        }
    }

    private func postActions(for item: FeedViewPost) -> PostCard.Actions {
        var a = PostCard.Actions()
        a.onTap = { post in threadURI = post.uri }
        return a
    }
}

// MARK: - Thread placeholder (avoids circular dependency on BlueskyFeed)

private struct ThreadPlaceholder: View {
    let uri: ATURI
    var body: some View {
        Text("Thread: \(uri.rawValue)")
            .navigationTitle("Thread")
    }
}
