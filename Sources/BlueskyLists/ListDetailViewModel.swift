import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
final class ListDetailViewModel {

    // MARK: - State

    var list: ListView?
    var members: [ListItemView] = []
    var membersCursor: Cursor?
    var feed: [FeedViewPost] = []
    var feedCursor: Cursor?
    var isLoading = false
    var error: String?

    // MARK: - Dependencies

    private let network: any NetworkClient
    private var listURI: ATURI?

    init(network: any NetworkClient) {
        self.network = network
    }

    // MARK: - Load list + members

    func load(listURI: ATURI) async {
        self.listURI = listURI
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            let resp: GetListResponse = try await network.get(
                lexicon: "app.bsky.graph.getList",
                params: ["list": listURI.rawValue, "limit": "50"]
            )
            list = resp.list
            members = resp.items
            membersCursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard let listURI, let cursor = membersCursor else { return }
        do {
            let resp: GetListResponse = try await network.get(
                lexicon: "app.bsky.graph.getList",
                params: ["list": listURI.rawValue, "limit": "50", "cursor": cursor]
            )
            members.append(contentsOf: resp.items)
            membersCursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Load feed

    func loadFeed() async {
        guard let listURI else { return }
        do {
            let resp: GetListFeedResponse = try await network.get(
                lexicon: "app.bsky.feed.getListFeed",
                params: ["list": listURI.rawValue, "limit": "50"]
            )
            feed = resp.feed
            feedCursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMoreFeed() async {
        guard let listURI, let cursor = feedCursor else { return }
        do {
            let resp: GetListFeedResponse = try await network.get(
                lexicon: "app.bsky.feed.getListFeed",
                params: ["list": listURI.rawValue, "limit": "50", "cursor": cursor]
            )
            feed.append(contentsOf: resp.feed)
            feedCursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }
}
