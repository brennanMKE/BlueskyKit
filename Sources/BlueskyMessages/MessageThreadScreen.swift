import SwiftUI
import OSLog
import PhotosUI
import BlueskyCore
import BlueskyKit
import BlueskyUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(Translation)
import Translation
#endif

private let messageThreadScreenLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "MessageThreadScreen")

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

/// Chat thread view — scrollable bubble list with a compose bar at the bottom.
public struct MessageThreadScreen: View {

    private let convo: ConvoView
    private let network: any NetworkClient
    private let viewerDID: DID?
    /// Invoked when the user taps an embedded quoted post inside a message
    /// bubble. Routed up to the host so the existing `threadURI` navigation
    /// destination can push a `ThreadView`. RN parity: tapping a quote post
    /// inside a DM opens the post.
    private let onPostTap: ((ATURI) -> Void)?

    @State private var viewModel: MessageThreadViewModel
    @State private var draftText: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageLoadErrorMessage: String?
    /// The message the user has asked to delete via the context menu, awaiting
    /// confirmation. `nil` when no confirmation dialog is shown.
    @State private var pendingDeleteMessage: MessageView?

    /// Whether the user is currently parked within `Self.atBottomThreshold` of
    /// the bottom of the message list. Drives the conditional auto-scroll
    /// behaviour (RN's `isAtBottom` shared value in `MessagesList.tsx`):
    /// when true we pull new messages into view; when false we leave the
    /// reader's scroll position alone and surface a "Jump to newest" pill.
    @State private var isAtBottom: Bool = true

    /// The latest message ID we've already auto-scrolled to. Used so that
    /// `onChange(of: viewModel.messages.count)` only triggers exactly once per
    /// new message — without this guard, a `messages` mutation that reuses
    /// the same final ID (e.g. an optimistic-then-replaced send) can fire the
    /// scroll twice.
    @State private var lastAutoScrolledMessageID: String?

    /// Distance, in points, from the bottom of the message list within which
    /// the reader is considered "at bottom" for auto-scroll purposes. Matches
    /// the order of magnitude of RN's 100pt threshold (we use 50pt to feel
    /// snappier on the smaller iOS message column).
    private static let atBottomThreshold: CGFloat = 50

    public init(
        convo: ConvoView,
        network: any NetworkClient,
        viewerDID: DID? = nil,
        onPostTap: ((ATURI) -> Void)? = nil
    ) {
        self.convo = convo
        self.network = network
        self.viewerDID = viewerDID
        self.onPostTap = onPostTap
        _viewModel = State(wrappedValue: MessageThreadViewModel(
            convoId: convo.id, viewerDID: viewerDID, network: network
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            messageScrollView
            Divider()
            composeBar
        }
        .navigationTitle(convoTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.load() }
        .alert("Could not send image",
               isPresented: Binding(
                    get: { imageLoadErrorMessage != nil },
                    set: { if !$0 { imageLoadErrorMessage = nil } }
               )
        ) {
            Button("OK") { imageLoadErrorMessage = nil }
        } message: {
            Text(imageLoadErrorMessage ?? "")
        }
        // Delete-for-me confirmation, mirrors RN's `Prompt.Basic` in
        // `MessageContextMenu.tsx`. Title and body match the upstream copy.
        .confirmationDialog(
            "Delete message",
            isPresented: Binding(
                get: { pendingDeleteMessage != nil },
                set: { if !$0 { pendingDeleteMessage = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteMessage
        ) { message in
            Button("Delete", role: .destructive) {
                let id = message.id
                pendingDeleteMessage = nil
                Task { await viewModel.deleteMessage(id) }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteMessage = nil
            }
        } message: { _ in
            Text("Are you sure you want to delete this message? The message will be deleted for you, but not for the other participants.")
        }
    }

    // MARK: - Message scroll view

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if viewModel.hasOlderMessages {
                            Button("Load older messages") {
                                Task { await viewModel.loadOlder() }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                        }
                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                            if shouldShowDateDivider(at: index) {
                                DateDivider(date: message.sentAt)
                                    .padding(.top, 8)
                            }
                            // RN's `MessagesList.tsx` renders a centered
                            // "New messages" divider above the first
                            // message that arrived while the user was
                            // scrolled away from the bottom. We anchor it
                            // by message ID so `LazyVStack` can position
                            // it exactly above the right bubble.
                            if message.id == viewModel.firstUnreadID {
                                NewMessagesDivider()
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                            }
                            MessageBubble(
                                message: message,
                                isOwn: viewModel.isOwn(message),
                                isGroup: isGroup,
                                isFirstInRun: isFirstInRun(at: index),
                                isLastInRun: isLastInRun(at: index),
                                timestampLabel: isLastInRun(at: index)
                                    ? Self.bubbleTimestamp(for: message.sentAt, now: Date())
                                    : nil,
                                senderProfile: senderProfile(for: message),
                                onDeleteRequested: { pendingDeleteMessage = message },
                                onPostTap: onPostTap
                            )
                            .id(message.id)
                        }
                        // Bottom sentinel — used by the GeometryReader below
                        // to determine whether the user is "at bottom" by
                        // comparing this row's frame to the scroll view's
                        // bounds. Zero-height so it doesn't add visual space.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomSentinelID)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: BottomSentinelOffsetKey.self,
                                        value: geo.frame(in: .named(Self.scrollCoordinateSpace)).maxY
                                    )
                                }
                            )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollViewportHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
                }
                .coordinateSpace(name: Self.scrollCoordinateSpace)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollViewportHeightKey.self,
                            value: geo.size.height
                        )
                    }
                )
                .onPreferenceChange(BottomSentinelOffsetKey.self) { sentinelMaxY in
                    updateAtBottom(sentinelMaxY: sentinelMaxY)
                }
                .onPreferenceChange(ScrollViewportHeightKey.self) { height in
                    viewportHeight = height
                }
                .onChange(of: viewModel.messages.count) { oldCount, newCount in
                    handleMessageCountChange(
                        oldCount: oldCount,
                        newCount: newCount,
                        proxy: proxy
                    )
                }

                // Floating "Jump to newest" pill — RN's `NewMessagesPill`
                // anchored at the bottom-right of the scroll view, above
                // the compose bar. Only visible when the reader is
                // scrolled away from the bottom.
                if !isAtBottom {
                    JumpToNewestPill(
                        unreadCount: viewModel.unreadCount,
                        action: { jumpToBottom(proxy: proxy) }
                    )
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isAtBottom)
        }
    }

    // MARK: - Scroll-state plumbing

    /// Stable ID for the zero-height sentinel row at the very bottom of the
    /// message stack. Used both for `proxy.scrollTo` and as the anchor we
    /// measure against in the GeometryReader to detect "at bottom".
    private static let bottomSentinelID = "__bottom_sentinel__"

    /// Coordinate space name used by the scroll-position GeometryReader so
    /// that bubble frames are reported relative to the scroll view's own
    /// content area, not the screen.
    private static let scrollCoordinateSpace = "messageScroll"

    /// The most recent measured viewport height for the message list. Stored
    /// in a `@State` so `updateAtBottom` can compare the bottom sentinel's
    /// position against it without re-laying out.
    @State private var viewportHeight: CGFloat = 0

    /// Recalculates `isAtBottom` whenever the bottom sentinel's offset
    /// inside the scroll view changes. The sentinel sits at the very end of
    /// the `LazyVStack`, so when the user is scrolled to the bottom its
    /// `maxY` (in scroll-view coords) sits within `atBottomThreshold` of the
    /// viewport height. When the user has scrolled up, `maxY` exceeds the
    /// viewport height by the amount of off-screen content.
    private func updateAtBottom(sentinelMaxY: CGFloat) {
        guard viewportHeight > 0 else { return }
        let distanceFromBottom = sentinelMaxY - viewportHeight
        let nowAtBottom = distanceFromBottom <= Self.atBottomThreshold
        if nowAtBottom != isAtBottom {
            isAtBottom = nowAtBottom
        }
        if nowAtBottom {
            // Reader caught up — clear the divider/pill state so a fresh
            // run of unread messages starts a new divider next time.
            if viewModel.firstUnreadID != nil || viewModel.unreadCount != 0 {
                viewModel.clearUnread()
            }
        }
    }

    /// Reacts to a change in `viewModel.messages.count`. Auto-scrolls to the
    /// newest message only when the reader is already at the bottom; when
    /// they are scrolled up, records the first unread message so the divider
    /// and pill appear instead of yanking them out of context.
    private func handleMessageCountChange(
        oldCount: Int,
        newCount: Int,
        proxy: ScrollViewProxy
    ) {
        guard let last = viewModel.messages.last else { return }
        // Older-page prepend or no-op: don't auto-scroll, don't mark unread.
        guard newCount > oldCount, last.id != lastAutoScrolledMessageID else {
            // Update anchor even if we skip scroll, so an immediate user-sent
            // message (which we *do* want to follow) doesn't get suppressed.
            return
        }

        if isAtBottom || viewModel.isOwn(last) {
            // RN parity: a message *the viewer just sent* always pulls them
            // to the bottom regardless of where they were scrolled, so the
            // input doesn't appear to swallow the message.
            withAnimation { proxy.scrollTo(Self.bottomSentinelID, anchor: .bottom) }
            lastAutoScrolledMessageID = last.id
            // Sender messages count as catching up.
            if viewModel.isOwn(last) {
                viewModel.clearUnread()
            }
        } else {
            // Reader is scrolled up — surface the new-messages affordances
            // and leave their position alone.
            viewModel.noteNewUnread(messageID: last.id)
        }
    }

    /// Scrolls to the bottom and clears unread state. Bound to the FAB pill.
    private func jumpToBottom(proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(Self.bottomSentinelID, anchor: .bottom) }
        viewModel.clearUnread()
        lastAutoScrolledMessageID = viewModel.messages.last?.id
        isAtBottom = true
    }

    // MARK: - Run clustering / member lookup

    /// RN's `parseConvoView` treats >2 members (self + 2+ others) as a group chat.
    private var isGroup: Bool {
        members.count > 2
    }

    /// Members from the freshest convo we have — view-model may have refreshed it.
    private var members: [ProfileBasic] {
        viewModel.convo?.members ?? convo.members
    }

    /// First message in a "run" of consecutive messages from the same sender.
    /// Mirrors RN's `isFirstInCluster` (without the 5-minute time gate, which
    /// our model does not currently surface in the UI).
    private func isFirstInRun(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = viewModel.messages[index - 1]
        let curr = viewModel.messages[index]
        return prev.sender.did != curr.sender.did
    }

    /// Last message in a "run" of consecutive messages from the same sender —
    /// the bubble that should anchor the per-message timestamp. Mirrors RN's
    /// `isLastInCluster` from `MessageItem.tsx`.
    private func isLastInRun(at index: Int) -> Bool {
        let messages = viewModel.messages
        guard index + 1 < messages.count else { return true }
        return messages[index].sender.did != messages[index + 1].sender.did
    }

    /// Whether a date divider should appear above the message at `index`.
    /// Always shows for the first message; otherwise only when the calendar
    /// day differs from the previous message — matching RN's `DateDivider`
    /// rendering in `MessageItem.tsx`.
    private func shouldShowDateDivider(at index: Int) -> Bool {
        let messages = viewModel.messages
        guard index > 0 else { return true }
        let prev = messages[index - 1].sentAt
        let curr = messages[index].sentAt
        return !Calendar.current.isDate(prev, inSameDayAs: curr)
    }

    private func senderProfile(for message: MessageView) -> ProfileBasic? {
        members.first(where: { $0.did == message.sender.did })
    }

    /// Per-bubble timestamp matching RN's `niceDate` short-form behaviour.
    /// - Today: short time only ("3:42 PM")
    /// - Yesterday: "Yesterday 3:42 PM"
    /// - Older: short date + time ("Mar 4, 3:42 PM"; year added if not current)
    /// Public-static so it stays pure and trivially testable.
    static func bubbleTimestamp(for date: Date, now: Date) -> String {
        let cal = Calendar.current

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")
        let time = timeFormatter.string(from: date)

        if cal.isDate(date, inSameDayAs: now) {
            return time
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday \(time)"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        } else {
            dateFormatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        }
        return "\(dateFormatter.string(from: date)) \(time)"
    }

    // MARK: - Compose bar

    private var composeBar: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task { await sendImage(newItem) }
            }

            TextField("Message…", text: $draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))

            Button {
                let text = draftText
                draftText = ""
                Task { await viewModel.sendMessage(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(draftText.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? Color.secondary : Color.accentColor)
            }
            .disabled(draftText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Image sending

    private func sendImage(_ item: PhotosPickerItem) async {
        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            messageThreadScreenLogger.error("loadTransferable image failed: \(error.localizedDescription, privacy: .public)")
            imageLoadErrorMessage = "Could not load the selected photo: \(error.localizedDescription)"
            selectedPhoto = nil
            return
        }
        guard let data else {
            imageLoadErrorMessage = "Could not load the selected photo."
            selectedPhoto = nil
            return
        }
        let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
        await viewModel.sendImageAttachment(data: data, mimeType: mimeType)
        selectedPhoto = nil
    }

    // MARK: - Title

    private var convoTitle: String {
        let others = convo.members.filter { $0.did != viewerDID }
        if others.isEmpty { return convo.members.first?.handle.rawValue ?? "Chat" }
        return others.map { $0.displayName ?? $0.handle.rawValue }.joined(separator: ", ")
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: MessageView
    let isOwn: Bool
    var isGroup: Bool = false
    var isFirstInRun: Bool = true
    /// Whether this is the *last* bubble in a run from the same sender. RN
    /// anchors the per-message timestamp on the last bubble of the cluster.
    var isLastInRun: Bool = true
    /// Pre-formatted timestamp string to render beneath the bubble; only set
    /// when `isLastInRun` is true (parent decides). `nil` suppresses the row.
    var timestampLabel: String? = nil
    var senderProfile: ProfileBasic? = nil
    /// Invoked when the user picks "Delete for me" from the context menu.
    /// The parent screen owns the confirmation prompt and the actual delete
    /// call; this closure simply surfaces the request upwards.
    var onDeleteRequested: (() -> Void)? = nil
    /// Invoked when the user taps an embedded quoted post inside the bubble.
    /// The parent screen routes this to the host's `threadURI` navigation
    /// destination so the existing `ThreadView` push reuses the same plumbing
    /// as feed/profile post taps.
    var onPostTap: ((ATURI) -> Void)? = nil

    /// Whether the system Translate sheet is currently presented for this bubble.
    @State private var isTranslating: Bool = false

    /// System link opener — used to launch link-card URLs from `external`
    /// embeds. Mirrors RN's behaviour of handing off external links to the
    /// platform browser/in-app browser.
    @Environment(\.openURL) private var openURL

    private static let avatarSize: CGFloat = 24
    private static let avatarGutter: CGFloat = 6

    /// Show the small "Display Name @handle" label above the first bubble in a
    /// non-self run inside a group chat. Matches RN's `showDisplayName` rule.
    private var showSenderHeader: Bool {
        isGroup && !isOwn && isFirstInRun
    }

    /// Show the avatar beside the first bubble in a non-self run in a group
    /// chat. RN places it at the bottom of the cluster; we use the top so it
    /// pairs visually with the sender header introduced above the bubble.
    private var showAvatar: Bool {
        isGroup && !isOwn && isFirstInRun
    }

    /// Reserve gutter width on every non-self bubble in a group so subsequent
    /// bubbles in the run line up under the first one (matches RN's stack).
    private var avatarGutterWidth: CGFloat {
        (isGroup && !isOwn) ? Self.avatarSize + Self.avatarGutter : 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isOwn {
                Spacer(minLength: 60)
            } else if isGroup {
                // Avatar gutter: shown only on the first bubble of a run; an
                // empty spacer on subsequent bubbles keeps them aligned.
                if showAvatar, let profile = senderProfile {
                    AvatarView(
                        url: profile.avatar,
                        handle: profile.handle.rawValue,
                        size: Self.avatarSize
                    )
                    .padding(.trailing, Self.avatarGutter)
                } else {
                    Color.clear
                        .frame(width: avatarGutterWidth, height: 1)
                }
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 2) {
                if showSenderHeader, let profile = senderProfile {
                    senderHeader(profile)
                }
                if let images = embeddedImages, !images.isEmpty {
                    imageStack(images)
                }
                // Rich embed — link card (`external`) or quoted post
                // (`record` / `recordWithMedia`). RN renders these with the
                // same component used by feed posts (see `MessageItemEmbed.tsx`
                // → `<Embed …/>`); we reuse `PostEmbedView` from BlueskyUI for
                // parity. The images half of `recordWithMedia` is already
                // drawn above by `imageStack`, so we only render the quote
                // half here to avoid showing the same images twice.
                if let richEmbed = richEmbedForRender {
                    PostEmbedView(
                        embed: richEmbed,
                        onLinkTap: { url in openURL(url) },
                        onRecordTap: { uri in onPostTap?(uri) }
                    )
                    .frame(maxWidth: 280, alignment: .leading)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(isOwn ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isOwn ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
                // Per-message timestamp — RN renders it beneath the *last*
                // bubble in a same-sender cluster (see MessageItem.tsx →
                // `effectiveLastInCluster && <MessageItemMetadata …/>`).
                if isLastInRun, let stamp = timestampLabel {
                    Text(stamp)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 1)
                        .accessibilityLabel("Sent \(stamp)")
                }
            }

            if !isOwn { Spacer(minLength: 60) }
        }
        // Per-message context menu — long-press on iOS, right-click on macOS.
        // Mirrors RN's `MessageContextMenu.tsx` ordering: Translate, Copy,
        // (divider), Delete, Report. Reactions are deferred to #0110; the
        // message-subject Report wiring is deferred (`ReportDialog` does not
        // accept a chat-message subject yet — see issue Gotchas).
        .contextMenu {
            messageContextMenu
        }
        .translationPresentation(isPresented: $isTranslating, text: message.text)
    }

    @ViewBuilder
    private var messageContextMenu: some View {
        if !message.text.isEmpty {
            Button {
                isTranslating = true
            } label: {
                Label("Translate", systemImage: "character.bubble")
            }

            Button {
                copyToPasteboard(message.text)
            } label: {
                Label("Copy message text", systemImage: "doc.on.doc")
            }

            Divider()
        }

        if isOwn {
            Button(role: .destructive) {
                onDeleteRequested?()
            } label: {
                Label("Delete for me", systemImage: "trash")
            }
        }
        // Report wiring is deferred — see issue 0106 Gotchas.
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #endif
    }

    @ViewBuilder
    private func senderHeader(_ profile: ProfileBasic) -> some View {
        let displayName = profile.displayName?.trimmingCharacters(in: .whitespaces)
        let nameText = (displayName?.isEmpty == false ? displayName! : profile.handle.rawValue)
        (Text(nameText).font(.caption).fontWeight(.semibold)
         + Text(" @\(profile.handle.rawValue)").font(.caption))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 4)
            .padding(.bottom, 1)
    }

    private var embeddedImages: [EmbedImageView]? {
        guard let embed = message.embed else { return nil }
        switch embed {
        case .images(let images): return images
        case .recordWithMedia(_, let media):
            if case .images(let images) = media { return images }
            return nil
        default:
            return nil
        }
    }

    /// The portion of `message.embed` that should flow through `PostEmbedView`
    /// rather than the bubble's own `imageStack`. For pure image embeds we
    /// return nil (the bubble draws those itself with rounded chat-styled
    /// frames). For `recordWithMedia` we strip the media half and just hand
    /// `PostEmbedView` the quoted record so the images are not rendered
    /// twice. Returns nil for `video` (deferred — DMs cannot send videos in
    /// RN today) and `unknown`.
    private var richEmbedForRender: BlueskyCore.EmbedView? {
        guard let embed = message.embed else { return nil }
        switch embed {
        case .external:
            return embed
        case .record:
            return embed
        case .recordWithMedia(let record, _):
            // Drop the media half — `imageStack` already drew it. Render the
            // quote post inline beneath.
            return .record(record)
        case .images, .video, .unknown:
            return nil
        }
    }

    @ViewBuilder
    private func imageStack(_ images: [EmbedImageView]) -> some View {
        VStack(spacing: 4) {
            ForEach(images.indices, id: \.self) { idx in
                let img = images[idx]
                AsyncImage(url: img.thumb) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Color.secondary.opacity(0.15)
                    case .empty:
                        Color.secondary.opacity(0.1)
                            .overlay(ProgressView())
                    @unknown default:
                        Color.secondary.opacity(0.15)
                    }
                }
                .frame(maxWidth: 220, maxHeight: 220)
                .aspectRatio(
                    img.aspectRatio.map { CGFloat($0.width) / CGFloat($0.height) } ?? 1.0,
                    contentMode: .fit
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(img.alt.isEmpty ? "Image" : img.alt)
            }
        }
    }
}

// MARK: - Date divider

/// Centered date pill rendered between groups of messages from different days.
/// Mirrors RN's `DateDivider` (`components/dms/DateDivider.tsx`) which renders
/// "Today at 3:42 PM", "Yesterday at 3:42 PM", or "Mon, March 4 at 3:42 PM".
private struct DateDivider: View {
    let date: Date

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Messages from \(label)")
    }

    /// "Today at 3:42 PM" / "Yesterday at 3:42 PM" / "Mon, Mar 4 at 3:42 PM".
    /// Uses the localized "j" hour-cycle template so 12/24-hour follows the
    /// user's locale, matching RN's `Intl.DateTimeFormat({timeStyle:'short'})`.
    private var label: String {
        let now = Date()
        let cal = Calendar.current

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")
        let time = timeFormatter.string(from: date)

        let dayString: String
        if cal.isDateInToday(date) {
            dayString = "Today"
        } else if cal.isDateInYesterday(date) {
            dayString = "Yesterday"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale.current
            // Within a week → weekday only ("Monday"); otherwise short date.
            // Mirrors RN's branch on `timestamp < oneWeekAgo`.
            let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now
            if date >= oneWeekAgo {
                dateFormatter.setLocalizedDateFormatFromTemplate("EEEE")
            } else if cal.component(.year, from: date) == cal.component(.year, from: now) {
                dateFormatter.setLocalizedDateFormatFromTemplate("EEEMMMMd")
            } else {
                dateFormatter.setLocalizedDateFormatFromTemplate("EEEMMMMdyyyy")
            }
            dayString = dateFormatter.string(from: date)
        }

        return "\(dayString) at \(time)"
    }
}

// MARK: - New messages divider

/// Centered "New messages" divider rendered above the first message that
/// arrived while the reader was scrolled away from the bottom. Matches the
/// affordance RN renders inside its message list (paired with the
/// `NewMessagesPill` floating button) so the reader can see exactly where
/// they left off when they catch up.
private struct NewMessagesDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.5))
                .frame(height: 1)
            Text("New messages")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .fixedSize()
            Rectangle()
                .fill(Color.accentColor.opacity(0.5))
                .frame(height: 1)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New messages")
    }
}

// MARK: - Jump to newest pill

/// Floating "Jump to newest" pill anchored to the bottom-right of the
/// message scroll view. Mirrors RN's `NewMessagesPill` (`components/dms/
/// NewMessagesPill.tsx`) — a small rounded pill that surfaces only when
/// the reader is scrolled away from the bottom and a new message arrives.
/// Tapping it scrolls the list back to the latest message and dismisses
/// the pill.
private struct JumpToNewestPill: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.regularMaterial)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unreadCount > 0
                            ? "Jump to newest, \(unreadCount) new"
                            : "Jump to newest")
    }
}

// MARK: - Scroll preference keys

/// Reports the bottom sentinel row's `maxY` (in scroll-view-local coords)
/// up to the parent so it can compute "is the reader at the bottom?". The
/// reducer takes the last value seen in a given pass — there is only one
/// sentinel row, so the choice is moot, but `nextValue()` is required.
private struct BottomSentinelOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Reports the scroll view's viewport height up to the parent so the
/// at-bottom calculation has both numbers it needs in one place.
private struct ScrollViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Previews

private let previewConvo = ConvoView(
    id: "convo-preview-1",
    rev: "1",
    members: [
        ProfileBasic(
            did: DID(rawValue: "did:plc:alice"),
            handle: Handle(rawValue: "alice.bsky.social"),
            displayName: "Alice",
            avatar: nil
        )
    ],
    lastMessage: .message(MessageView(
        id: "msg-1",
        rev: "1",
        text: "Hey! How are you?",
        embed: nil,
        sender: MessageSender(did: DID(rawValue: "did:plc:alice")),
        sentAt: Date(timeIntervalSinceNow: -60)
    )),
    unreadCount: 1,
    muted: false
)

#Preview("MessageThreadScreen — Light") {
    NavigationStack {
        MessageThreadScreen(
            convo: previewConvo,
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("MessageThreadScreen — Dark") {
    NavigationStack {
        MessageThreadScreen(
            convo: previewConvo,
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.dark)
}
