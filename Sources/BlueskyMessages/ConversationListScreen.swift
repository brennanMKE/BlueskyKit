import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

/// Conversation inbox — list of direct message conversations.
public struct ConversationListScreen: View {

    private let network: any NetworkClient
    private let viewerDID: DID?
    private let onConvoTap: ((ConvoView) -> Void)?

    @State private var viewModel: MessagesViewModel
    @State private var selectedConvoID: String?
    @State private var selectedConvo: ConvoView?

    public init(
        network: any NetworkClient,
        viewerDID: DID? = nil,
        onConvoTap: ((ConvoView) -> Void)? = nil
    ) {
        self.network = network
        self.viewerDID = viewerDID
        self.onConvoTap = onConvoTap
        _viewModel = State(wrappedValue: MessagesViewModel(network: network))
    }

    public var body: some View {
        Group {
            if viewModel.convos.isEmpty && viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.convos.isEmpty && viewModel.errorMessage == nil {
                emptyState
            } else if let msg = viewModel.errorMessage, viewModel.convos.isEmpty {
                errorView(msg)
            } else {
                convoList
            }
        }
        .navigationTitle("Messages")
        .task { await viewModel.loadInitial() }
        .navigationDestination(isPresented: Binding(
            get: { selectedConvo != nil },
            set: { if !$0 { selectedConvo = nil } }
        )) {
            if let convo = selectedConvo {
                MessageThreadScreen(convo: convo, network: network, viewerDID: viewerDID)
            }
        }
    }

    // MARK: - List

    private var convoList: some View {
        List {
            ForEach(viewModel.convos, id: \.id) { convo in
                Button {
                    if let onConvoTap { onConvoTap(convo) }
                    else {
                        selectedConvoID = convo.id
                        selectedConvo = convo
                    }
                } label: {
                    ConvoRow(convo: convo, viewerDID: viewerDID)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .swipeActions(edge: .trailing) {
                    Button("Leave", role: .destructive) {
                        Task { await viewModel.leaveConvo(convo.id) }
                    }
                    Button(convo.muted ? "Unmute" : "Mute") {
                        Task { await viewModel.muteConvo(convo.id, muted: !convo.muted) }
                    }
                    .tint(.orange)
                }
                .onAppear {
                    if convo.id == viewModel.convos.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
            }
            if viewModel.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Empty / error

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No messages yet")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.refresh() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Convo row

private struct ConvoRow: View {
    let convo: ConvoView
    let viewerDID: DID?

    var body: some View {
        HStack(spacing: 12) {
            avatarStack
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(convoName).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                    Spacer()
                    if convo.unreadCount > 0 {
                        BadgeView(count: convo.unreadCount)
                    }
                }
                if let msg = convo.lastMessage {
                    Text(msg.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

    private var avatarStack: some View {
        let others = convo.members.filter { $0.did != viewerDID }
        let first = others.first ?? convo.members.first
        return AvatarView(
            url: first?.avatar,
            handle: first?.handle.rawValue ?? "",
            size: 44
        )
    }
}

