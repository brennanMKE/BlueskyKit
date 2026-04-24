import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

/// Notification feed — likes, reposts, follows, mentions, quotes, replies.
public struct NotificationsScreen: View {

    private let network: any NetworkClient
    public var onUnreadCountChange: ((Int) -> Void)?

    @State private var viewModel: NotificationsViewModel
    @State private var threadURI: ATURI?

    public init(
        network: any NetworkClient,
        onUnreadCountChange: ((Int) -> Void)? = nil
    ) {
        self.network = network
        self.onUnreadCountChange = onUnreadCountChange
        _viewModel = State(wrappedValue: NotificationsViewModel(network: network))
    }

    public var body: some View {
        Group {
            if viewModel.notifications.isEmpty && viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.notifications.isEmpty, let msg = viewModel.errorMessage {
                errorView(msg)
            } else {
                notificationList
            }
        }
        .navigationTitle("Notifications")
        .task {
            await viewModel.loadInitial()
            await viewModel.markSeen()
        }
        .onChange(of: viewModel.unreadCount) { _, count in
            onUnreadCountChange?(count)
        }
        .navigationDestination(isPresented: Binding(
            get: { threadURI != nil },
            set: { if !$0 { threadURI = nil } }
        )) {
            if let uri = threadURI {
                Text("Thread: \(uri.rawValue)").navigationTitle("Thread")
            }
        }
    }

    // MARK: - List

    private var notificationList: some View {
        List {
            ForEach(viewModel.notifications, id: \.uri) { notification in
                NotificationRow(notification: notification, onTap: { uri in
                    threadURI = uri
                })
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .onAppear {
                    if notification.uri == viewModel.notifications.last?.uri {
                        Task { await viewModel.loadMore() }
                    }
                }
            }
            if viewModel.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Error

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

// MARK: - Notification row

private struct NotificationRow: View {
    let notification: NotificationView
    let onTap: (ATURI) -> Void

    var body: some View {
        Button {
            if let subject = notification.reasonSubject {
                onTap(subject)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                reasonIcon
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        AvatarView(
                            url: notification.author.avatar,
                            handle: notification.author.handle.rawValue,
                            size: 32
                        )
                        Text(authorName)
                            .font(.subheadline).fontWeight(.semibold)
                            .lineLimit(1)
                        if !notification.isRead {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                        }
                    }
                    Text(reasonText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(notification.indexedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var reasonIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 16))
            .foregroundStyle(iconColor)
            .frame(width: 24)
    }

    private var iconName: String {
        switch notification.reason {
        case "like":    return "heart.fill"
        case "repost":  return "arrow.2.squarepath"
        case "follow":  return "person.fill.badge.plus"
        case "mention": return "at"
        case "reply":   return "bubble.left.fill"
        case "quote":   return "quote.bubble.fill"
        default:        return "bell.fill"
        }
    }

    private var iconColor: Color {
        switch notification.reason {
        case "like":    return .pink
        case "repost":  return .green
        case "follow":  return .blue
        default:        return .secondary
        }
    }

    private var authorName: String {
        notification.author.displayName ?? "@\(notification.author.handle.rawValue)"
    }

    private var reasonText: String {
        switch notification.reason {
        case "like":    return "liked your post"
        case "repost":  return "reposted your post"
        case "follow":  return "followed you"
        case "mention": return "mentioned you"
        case "reply":   return "replied to your post"
        case "quote":   return "quoted your post"
        default:        return notification.reason
        }
    }
}
