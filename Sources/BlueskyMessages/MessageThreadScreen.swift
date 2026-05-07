import SwiftUI
import OSLog
import PhotosUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

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

    @State private var viewModel: MessageThreadViewModel
    @State private var draftText: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageLoadErrorMessage: String?

    public init(convo: ConvoView, network: any NetworkClient, viewerDID: DID? = nil) {
        self.convo = convo
        self.network = network
        self.viewerDID = viewerDID
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
    }

    // MARK: - Message scroll view

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
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
                        MessageBubble(
                            message: message,
                            isOwn: viewModel.isOwn(message),
                            isGroup: isGroup,
                            isFirstInRun: isFirstInRun(at: index),
                            senderProfile: senderProfile(for: message)
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
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

    private func senderProfile(for message: MessageView) -> ProfileBasic? {
        members.first(where: { $0.did == message.sender.did })
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
    var senderProfile: ProfileBasic? = nil

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
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(isOwn ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isOwn ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
            }

            if !isOwn { Spacer(minLength: 60) }
        }
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
