import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

/// Conversation inbox — list of direct message conversations.
public struct ConversationListScreen: View {

    private let network: any NetworkClient
    private let viewerDID: DID?
    private let onConvoTap: ((ConvoView) -> Void)?

    @State private var viewModel: MessagesViewModel
    @State private var selectedConvoID: String?
    @State private var selectedConvo: ConvoView?
    @State private var showingRequests = false

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
        .navigationDestination(isPresented: $showingRequests) {
            MessageRequestsScreen(
                network: network,
                viewerDID: viewerDID
            )
        }
    }

    // MARK: - List

    private var convoList: some View {
        List {
            if !viewModel.requestConvos.isEmpty {
                Button {
                    showingRequests = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(.secondary)
                        Text("Message Requests")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        BadgeView(count: viewModel.requestConvos.count)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
            }
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
        HStack(alignment: .top, spacing: 12) {
            avatarStack
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(convoName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let stamp = relativeTimestamp {
                        Text(stamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                previewLine
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if convo.unreadCount > 0 {
                BadgeView(count: convo.unreadCount)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var isGroup: Bool {
        // RN's parseConvoView treats >2 members (i.e. self + 2+ others) as a group.
        convo.members.count > 2
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

    /// Short-form timestamp ("now", "2h", "Yesterday", "Mar 4") matching RN's
    /// `useTimeAgo` helper. Returns `nil` when there's no timestamp to show.
    private var relativeTimestamp: String? {
        guard let sentAt = convo.lastMessage?.sentAt else { return nil }
        return Self.shortTimeAgo(from: sentAt, now: Date())
    }

    /// The body text — handles all four variants: regular message, deleted
    /// placeholder, group sender prefix, and the empty "no messages" case.
    private var previewLine: Text {
        switch convo.lastMessage {
        case .none:
            return Text("No messages yet").italic()
        case .deleted:
            return Text("Message deleted").italic()
        case .message(let msg):
            let body = msg.text.isEmpty ? "(image)" : msg.text
            if isGroup, let prefix = senderPrefix(for: msg) {
                // Slightly bolder sender prefix; body inherits the secondary tint.
                return Text(prefix).fontWeight(.semibold) + Text(body)
            } else {
                return Text(body)
            }
        }
    }

    /// Returns "@<handle>: " for the sender of a group-chat message, or `nil`
    /// when the sender is the viewer (in which case RN suppresses the prefix).
    private func senderPrefix(for msg: MessageView) -> String? {
        if msg.sender.did == viewerDID { return "You: " }
        guard let member = convo.members.first(where: { $0.did == msg.sender.did }) else {
            return nil
        }
        return "@\(member.handle.rawValue): "
    }

    /// Mirrors RN's short-form "time ago" output. Public-static so it's
    /// testable and stays pure.
    static func shortTimeAgo(from date: Date, now: Date) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "now" }
        if delta < 3600 { return "\(Int(delta / 60))m" }
        if delta < 86_400 { return "\(Int(delta / 3600))h" }

        let cal = Calendar.current
        if cal.isDateInYesterday(date) { return "Yesterday" }

        let days = Int(delta / 86_400)
        if days < 7 { return "\(days)d" }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        }
        return formatter.string(from: date)
    }
}

// MARK: - Previews

#Preview("ConversationListScreen — Light") {
    NavigationStack {
        ConversationListScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.light)
}

#Preview("ConversationListScreen — Dark") {
    NavigationStack {
        ConversationListScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.dark)
}
