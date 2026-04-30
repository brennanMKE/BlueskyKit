import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class SearchViewModel {

    public var actors: [ProfileView] { store.actors }
    public var posts: [PostView] { store.posts }
    public var suggestedFeeds: [GeneratorView] { store.suggestedFeeds }
    public var suggestedActors: [ProfileView] { store.suggestedActors }
    public var trendingTopics: [TrendingTopic] { store.trendingTopics }
    public var actorsCursor: String? { store.actorsCursor }
    public var postsCursor: String? { store.postsCursor }
    public var isLoading: Bool { store.isLoading }
    public var errorMessage: String? { store.errorMessage }

    public var query: String = ""
    public var activeTab: SearchTab = .people

    private let store: any SearchStoring
    private var debounceTask: Task<Void, Never>?

    public init(network: any NetworkClient) {
        self.store = SearchStore(network: network)
    }

    // MARK: - Debounced search trigger

    public func onQueryChange() {
        debounceTask?.cancel()
        let q = query
        let tab = activeTab
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            await store.search(query: q, tab: tab, fresh: true)
        }
    }

    public func search(fresh: Bool) async {
        await store.search(query: query, tab: activeTab, fresh: fresh)
    }

    public func loadMore() async {
        await store.search(query: query, tab: activeTab, fresh: false)
    }

    public func loadSuggestions() async {
        await store.loadSuggestions()
        await store.loadTrending()
    }

    public func loadTrending() async {
        await store.loadTrending()
    }

    public func clearResults() {
        store.clearResults()
    }
}
