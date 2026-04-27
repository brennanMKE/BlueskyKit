import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class SavedFeedsViewModel {
    public var feeds: [SavedFeed] {
        get { store.feeds }
        set { store.feeds = newValue }
    }
    public var isLoading: Bool { store.isLoading }
    public var isSaving: Bool { store.isSaving }
    public var error: String? { store.error }

    private let store: any SavedFeedsStoring

    public init(network: any NetworkClient, cache: any CacheStore) {
        self.store = SavedFeedsStore(network: network, cache: cache)
    }

    public func load() async { await store.load() }
    public func save() async { await store.save() }

    public func togglePin(id: String) {
        guard let index = store.feeds.firstIndex(where: { $0.id == id }) else { return }
        store.feeds[index].pinned.toggle()
    }

    public func move(fromOffsets: IndexSet, toOffset: Int) {
        store.feeds.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    public func remove(atOffsets: IndexSet) {
        store.feeds.remove(atOffsets: atOffsets)
    }
}
