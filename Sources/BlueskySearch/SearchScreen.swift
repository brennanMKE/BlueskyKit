import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

/// Search screen: typeahead search for people, posts, and feeds.
public struct SearchScreen: View {

    private let network: any NetworkClient
    private let onActorTap: ((ProfileView) -> Void)?
    private let onPostTap: ((PostView) -> Void)?
    private let onTopicTap: ((String) -> Void)?

    @State private var viewModel: SearchViewModel
    @State private var selectedHashtag: String?

    public init(
        network: any NetworkClient,
        onActorTap: ((ProfileView) -> Void)? = nil,
        onPostTap: ((PostView) -> Void)? = nil,
        onTopicTap: ((String) -> Void)? = nil
    ) {
        self.network = network
        self.onActorTap = onActorTap
        self.onPostTap = onPostTap
        self.onTopicTap = onTopicTap
        _viewModel = State(wrappedValue: SearchViewModel(network: network))
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
        }
        .navigationTitle("Search")
        .task { await viewModel.loadSuggestions() }
        .navigationDestination(item: $selectedHashtag) { hashtag in
            HashtagView(hashtag: hashtag, network: network)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search people, posts, feeds…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
                .onSubmit { Task { await viewModel.search(fresh: true) } }
                .onChange(of: viewModel.query) { viewModel.onQueryChange() }
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.clearResults()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Content switching

    @ViewBuilder
    private var content: some View {
        if viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
            suggestionsSection
        } else {
            tabStrip
            searchResults
        }
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !viewModel.trendingTopics.isEmpty {
                    Text("Trending")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    ForEach(viewModel.trendingTopics, id: \.topic) { topic in
                        Button {
                            let tag = topic.topic
                            if let onTopicTap {
                                onTopicTap(tag)
                            } else {
                                selectedHashtag = tag
                            }
                        } label: {
                            TrendingTopicRow(topic: topic)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                }
                if !viewModel.suggestedActors.isEmpty {
                    Text("Suggested")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    ForEach(viewModel.suggestedActors, id: \.did) { actor in
                        Button {
                            onActorTap?(actor)
                        } label: {
                            ActorRow(actor: actor)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 68)
                    }
                } else if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
        }
        .refreshable { await viewModel.loadSuggestions() }
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        Picker("", selection: $viewModel.activeTab) {
            ForEach(SearchTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: viewModel.activeTab) { _, _ in
            Task { await viewModel.search(fresh: true) }
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResults: some View {
        if viewModel.isLoading && viewModel.actors.isEmpty && viewModel.posts.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(40)
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            switch viewModel.activeTab {
            case .people: peopleResults
            case .posts:  postResults
            case .feeds:  feedResults
            }
        }
    }

    private var peopleResults: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.actors, id: \.did) { actor in
                    Button { onActorTap?(actor) } label: { ActorRow(actor: actor) }
                        .buttonStyle(.plain)
                    Divider().padding(.leading, 68)
                        .onAppear {
                            if actor.did == viewModel.actors.last?.did {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }
                if viewModel.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding()
                }
                if viewModel.actors.isEmpty && !viewModel.isLoading {
                    emptyState("No people found")
                }
            }
        }
        .refreshable { await viewModel.search(fresh: true) }
    }

    private var postResults: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.posts, id: \.uri) { post in
                    PostCard(
                        item: FeedViewPost(post: post, reply: nil, reason: nil),
                        actions: {
                            var a = PostCard.Actions()
                            a.onTap = { _ in onPostTap?(post) }
                            a.onHashtagTap = { tag in selectedHashtag = tag }
                            return a
                        }()
                    )
                    Divider()
                        .onAppear {
                            if post.uri == viewModel.posts.last?.uri {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }
                if viewModel.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding()
                }
                if viewModel.posts.isEmpty && !viewModel.isLoading {
                    emptyState("No posts found")
                }
            }
        }
        .refreshable { await viewModel.search(fresh: true) }
    }

    private var feedResults: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.suggestedFeeds, id: \.uri) { feed in
                    FeedCard(feed: feed)
                    Divider()
                }
                if viewModel.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding()
                }
                if viewModel.suggestedFeeds.isEmpty && !viewModel.isLoading {
                    emptyState("No feeds found")
                }
            }
        }
        .refreshable { await viewModel.search(fresh: true) }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(40)
    }
}

// MARK: - Trending topic row

private struct TrendingTopicRow: View {
    let topic: TrendingTopic

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.displayName ?? topic.topic)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                if let description = topic.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Actor row

private struct ActorRow: View {
    let actor: ProfileView

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: actor.avatar, handle: actor.handle.rawValue, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(actor.displayName ?? actor.handle.rawValue)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text("@\(actor.handle.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let desc = actor.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Previews

#Preview("SearchScreen — Light") {
    NavigationStack {
        SearchScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.light)
}

#Preview("SearchScreen — Dark") {
    NavigationStack {
        SearchScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.dark)
}
