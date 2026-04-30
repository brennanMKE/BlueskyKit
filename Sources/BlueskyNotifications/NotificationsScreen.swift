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
        let groups = viewModel.groupedNotifications
        return List {
            ForEach(groups) { group in
                GroupedNotificationRow(group: group, onTap: { uri in
                    threadURI = uri
                })
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .onAppear {
                    if group.id == groups.last?.id {
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

// MARK: - Grouped notification row

private struct GroupedNotificationRow: View {
    let group: GroupedNotification
    let onTap: (ATURI) -> Void

    var body: some View {
        Button {
            if let subject = group.reasonSubject {
                onTap(subject)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                reasonIcon
                VStack(alignment: .leading, spacing: 4) {
                    actorAvatarStack
                    HStack(spacing: 4) {
                        Text(actorSummary)
                            .font(.subheadline).fontWeight(.semibold)
                            .lineLimit(2)
                        if !group.isRead {
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
                Text(group.indexedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Up to 3 overlapping avatars.
    private var actorAvatarStack: some View {
        let visible = Array(group.actors.prefix(3))
        return HStack(spacing: -8) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, actor in
                AvatarView(
                    url: actor.avatar,
                    handle: actor.handle.rawValue,
                    size: 28
                )
                .overlay(
                    Circle()
                        .stroke(Color.uiCompatibleSystemBackground, lineWidth: 1.5)
                )
            }
        }
    }

    private var reasonIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 16))
            .foregroundStyle(iconColor)
            .frame(width: 24)
    }

    private var iconName: String {
        switch group.reason {
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
        switch group.reason {
        case "like":    return .pink
        case "repost":  return .green
        case "follow":  return .blue
        default:        return .secondary
        }
    }

    /// "Alice", "Alice and Bob", "Alice, Bob, and 3 others"
    private var actorSummary: String {
        let actors = group.actors
        let name: (ProfileBasic) -> String = { a in
            a.displayName ?? "@\(a.handle.rawValue)"
        }
        switch actors.count {
        case 0:  return ""
        case 1:  return name(actors[0])
        case 2:  return "\(name(actors[0])) and \(name(actors[1]))"
        default:
            let extra = actors.count - 2
            return "\(name(actors[0])), \(name(actors[1])), and \(extra) other\(extra == 1 ? "" : "s")"
        }
    }

    private var reasonText: String {
        switch group.reason {
        case "like":    return "liked your post"
        case "repost":  return "reposted your post"
        case "follow":  return "followed you"
        case "mention": return "mentioned you"
        case "reply":   return "replied to your post"
        case "quote":   return "quoted your post"
        default:        return group.reason
        }
    }
}

// MARK: - Platform color helper

private extension Color {
    /// `UIColor.systemBackground` on iOS, `NSColor.windowBackgroundColor` on macOS.
    static var uiCompatibleSystemBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}
