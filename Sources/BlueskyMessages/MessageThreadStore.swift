import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "MessageThreadStore")

// MARK: - MessageThreadStoring

public protocol MessageThreadStoring: AnyObject, Observable, Sendable {
    var messages: [MessageView] { get }
    var isLoading: Bool { get }
    var isSending: Bool { get }
    var errorMessage: String? { get }
    var convo: ConvoView? { get }
    var hasOlderMessages: Bool { get }

    func load(convoId: String) async
    func loadOlder(convoId: String) async
    func sendMessage(_ text: String, convoId: String) async
    func sendImageAttachment(data: Data, mimeType: String, convoId: String) async
}

// MARK: - MessageThreadStore

@Observable
public final class MessageThreadStore: MessageThreadStoring {

    public private(set) var messages: [MessageView] = []
    public private(set) var isLoading = false
    public private(set) var isSending = false
    public private(set) var errorMessage: String?
    public private(set) var convo: ConvoView?
    public var hasOlderMessages: Bool { cursor != nil }

    private var cursor: String?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    public func load(convoId: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let resp: GetMessagesResponse = try await network.get(
                lexicon: "chat.bsky.convo.getMessages",
                params: ["convoId": convoId, "limit": "50"]
            )
            messages = resp.messages.reversed()
            cursor = resp.cursor
            await markRead(convoId: convoId)
        } catch {
            logger.error("messages fetch error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func loadOlder(convoId: String) async {
        guard !isLoading, let cursor else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: GetMessagesResponse = try await network.get(
                lexicon: "chat.bsky.convo.getMessages",
                params: ["convoId": convoId, "limit": "50", "cursor": cursor]
            )
            messages.insert(contentsOf: resp.messages.reversed(), at: 0)
            self.cursor = resp.cursor
        } catch {}
    }

    public func sendMessage(_ text: String, convoId: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let req = SendMessageRequest(
                convoId: convoId,
                message: MessageInput(text: trimmed)
            )
            let sent: MessageView = try await network.post(
                lexicon: "chat.bsky.convo.sendMessage", body: req
            )
            messages.append(sent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func sendImageAttachment(data: Data, mimeType: String, convoId: String) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let uploadResp: UploadBlobResponse = try await network.upload(
                lexicon: "com.atproto.repo.uploadBlob",
                data: data,
                mimeType: mimeType
            )
            let blobRef = uploadResp.blob
            let embed = Embed.images([EmbedImage(image: blobRef, alt: "", aspectRatio: nil)])
            let req = SendMessageRequest(
                convoId: convoId,
                message: MessageInput(text: "", embed: embed)
            )
            let sent: MessageView = try await network.post(
                lexicon: "chat.bsky.convo.sendMessage", body: req
            )
            messages.append(sent)
        } catch {
            logger.error("image attachment send error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func markRead(convoId: String) async {
        do {
            let _: ConvoResponse = try await network.post(
                lexicon: "chat.bsky.convo.updateRead",
                body: UpdateReadRequest(convoId: convoId)
            )
        } catch {}
    }
}
