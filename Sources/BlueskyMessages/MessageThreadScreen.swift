import SwiftUI
import PhotosUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

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
                    ForEach(viewModel.messages, id: \.id) { message in
                        MessageBubble(message: message, isOwn: viewModel.isOwn(message))
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
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
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

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 60) }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(isOwn ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isOwn ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 16))
            if !isOwn { Spacer(minLength: 60) }
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
    lastMessage: MessageView(
        id: "msg-1",
        rev: "1",
        text: "Hey! How are you?",
        embed: nil,
        sender: MessageSender(did: DID(rawValue: "did:plc:alice")),
        sentAt: Date(timeIntervalSinceNow: -60)
    ),
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
