import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

/// Shows pending DM requests from accounts the viewer does not yet follow.
///
/// Each row offers Accept / Reject actions and navigates into the existing
/// `MessageThreadScreen`. The list is populated from
/// `chat.bsky.convo.listConvos?status=request`. Accept calls
/// `chat.bsky.convo.acceptConvo`; reject calls `chat.bsky.convo.leaveConvo`.
public struct MessageRequestsScreen: View {

    private let network: any NetworkClient
    private let viewerDID: DID?

    /// Optional shared view model — when the parent already loaded request convos,
    /// passing it in avoids a duplicate network round-trip.
    @State private var viewModel: MessagesViewModel

    public init(
        network: any NetworkClient,
        viewerDID: DID? = nil
    ) {
        self.network = network
        self.viewerDID = viewerDID
        _viewModel = State(wrappedValue: MessagesViewModel(network: network))
    }

    public var body: some View {
        Group {
            if viewModel.requestConvos.isEmpty {
                emptyState
            } else {
                requestList
            }
        }
        .navigationTitle("Message Requests")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.loadRequests() }
    }

    // MARK: - List

    private var requestList: some View {
        List {
            ForEach(viewModel.requestConvos, id: \.id) { convo in
                NavigationLink(destination: MessageThreadScreen(
                    convo: convo,
                    network: network,
                    viewerDID: viewerDID
                )) {
                    RequestConvoRow(convo: convo, viewerDID: viewerDID)
                }
                .listRowInsets(EdgeInsets())
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Reject", role: .destructive) {
                        Task { await viewModel.rejectRequest(convo.id) }
                    }
                    Button("Accept") {
                        Task { await viewModel.acceptRequest(convo.id) }
                    }
                    .tint(.accentColor)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.loadRequests() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No message requests")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Request convo row

private struct RequestConvoRow: View {
    let convo: ConvoView
    let viewerDID: DID?

    var body: some View {
        HStack(spacing: 12) {
            avatarView
            VStack(alignment: .leading, spacing: 3) {
                Text(convoName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if let msg = convo.lastMessage {
                    Text(msg.text.isEmpty ? "(image)" : msg.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if convo.unreadCount > 0 {
                BadgeView(count: convo.unreadCount)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var convoName: String {
        let others = convo.members.filter { $0.did != viewerDID }
        if others.isEmpty { return convo.members.first?.handle.rawValue ?? "Conversation" }
        return others.map { $0.displayName ?? $0.handle.rawValue }.joined(separator: ", ")
    }

    private var avatarView: some View {
        let others = convo.members.filter { $0.did != viewerDID }
        let first = others.first ?? convo.members.first
        return AvatarView(
            url: first?.avatar,
            handle: first?.handle.rawValue ?? "",
            size: 44
        )
    }
}

// MARK: - Previews

#Preview("MessageRequestsScreen — Light") {
    NavigationStack {
        MessageRequestsScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.light)
}

#Preview("MessageRequestsScreen — Dark") {
    NavigationStack {
        MessageRequestsScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.dark)
}
