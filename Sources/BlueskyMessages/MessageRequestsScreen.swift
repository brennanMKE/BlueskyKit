import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

/// Shows pending DM requests from accounts not yet followed.
///
/// Each row navigates into the existing `MessageThreadScreen`.
/// The list is populated from `chat.bsky.convo.listConvos?status=request`.
public struct MessageRequestsScreen: View {

    let convos: [ConvoView]
    let network: any NetworkClient
    let viewerDID: DID?

    public init(convos: [ConvoView], network: any NetworkClient, viewerDID: DID? = nil) {
        self.convos = convos
        self.network = network
        self.viewerDID = viewerDID
    }

    public var body: some View {
        Group {
            if convos.isEmpty {
                emptyState
            } else {
                requestList
            }
        }
        .navigationTitle("Message Requests")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - List

    private var requestList: some View {
        List {
            ForEach(convos, id: \.id) { convo in
                NavigationLink(destination: MessageThreadScreen(
                    convo: convo,
                    network: network,
                    viewerDID: viewerDID
                )) {
                    RequestConvoRow(convo: convo, viewerDID: viewerDID)
                }
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
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
                    Text(msg.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
