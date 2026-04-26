import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class SavedFeedsViewModel {
    public var feeds: [SavedFeed] = []
    public var isLoading = false
    public var isSaving = false
    public var error: String?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let prefs: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            feeds = prefs.savedFeeds
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.actor.putPreferences",
                body: PutPreferencesRequest(savedFeeds: feeds)
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func togglePin(id: String) {
        guard let index = feeds.firstIndex(where: { $0.id == id }) else { return }
        feeds[index].pinned.toggle()
    }

    public func move(fromOffsets: IndexSet, toOffset: Int) {
        feeds.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    public func remove(atOffsets: IndexSet) {
        feeds.remove(atOffsets: atOffsets)
    }
}
