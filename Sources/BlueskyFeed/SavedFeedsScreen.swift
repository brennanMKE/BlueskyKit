import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

private final class PreviewNoOpCache: CacheStore, @unchecked Sendable {
    nonisolated func store<T: Codable & Sendable>(_ value: T, for key: String, ttl: TimeInterval?) async throws {}
    nonisolated func fetch<T: Codable & Sendable>(_ type: T.Type, for key: String) async throws -> CacheResult<T>? { nil }
    nonisolated func evict(for key: String) async throws {}
    nonisolated func evictAll() async throws {}
}

public struct SavedFeedsScreen: View {
    @State private var viewModel: SavedFeedsViewModel
    @State private var hasChanges = false

    public init(network: any NetworkClient, cache: any CacheStore) {
        _viewModel = State(initialValue: SavedFeedsViewModel(network: network, cache: cache))
    }

    public var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.feeds.isEmpty {
                ContentUnavailableView(
                    "No Saved Feeds",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Feeds you save will appear here.")
                )
            } else {
                Section("Pinned") {
                    ForEach(viewModel.feeds.filter(\.pinned)) { feed in
                        feedRow(feed)
                    }
                    .onMove { from, to in
                        movePinned(from: from, to: to)
                        hasChanges = true
                    }
                }

                Section("Saved") {
                    ForEach(viewModel.feeds.filter { !$0.pinned }) { feed in
                        feedRow(feed)
                    }
                    .onDelete { indices in
                        let unpinned = viewModel.feeds.filter { !$0.pinned }
                        let idsToRemove = Set(indices.map { unpinned[$0].id })
                        viewModel.feeds.removeAll { idsToRemove.contains($0.id) }
                        hasChanges = true
                    }
                }
            }
        }
        .navigationTitle("My Feeds")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if hasChanges {
                    Button("Save") {
                        Task {
                            await viewModel.save()
                            hasChanges = false
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
            #endif
        }
        .task { await viewModel.load() }
    }

    private func feedRow(_ feed: SavedFeed) -> some View {
        HStack {
            Image(systemName: iconName(for: feed))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: feed))
                    .fontWeight(.medium)
                Text(feed.type.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.togglePin(id: feed.id)
                hasChanges = true
            } label: {
                Image(systemName: feed.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(feed.pinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func iconName(for feed: SavedFeed) -> String {
        switch feed.type {
        case "timeline": return "house"
        case "list": return "list.bullet"
        default: return "sparkles"
        }
    }

    private func displayName(for feed: SavedFeed) -> String {
        if feed.type == "timeline" { return "Following" }
        // AT-URI last path component is the rkey (human-readable feed slug)
        return feed.value.components(separatedBy: "/").last ?? feed.value
    }

    private func movePinned(from: IndexSet, to: Int) {
        var pinned = viewModel.feeds.filter(\.pinned)
        pinned.move(fromOffsets: from, toOffset: to)
        let unpinned = viewModel.feeds.filter { !$0.pinned }
        viewModel.feeds = pinned + unpinned
    }
}

// MARK: - Previews

#Preview("SavedFeedsScreen — Light") {
    NavigationStack {
        SavedFeedsScreen(
            network: PreviewNoOpNetwork(),
            cache: PreviewNoOpCache()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("SavedFeedsScreen — Dark") {
    NavigationStack {
        SavedFeedsScreen(
            network: PreviewNoOpNetwork(),
            cache: PreviewNoOpCache()
        )
    }
    .preferredColorScheme(.dark)
}
