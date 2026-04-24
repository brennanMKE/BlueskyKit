import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class MessagesViewModel {

    public var convos: [ConvoView] = []
    public var cursor: String?
    public var isLoading = false
    public var errorMessage: String?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    public func loadInitial() async {
        guard !isLoading, convos.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let resp: ListConvosResponse = try await network.get(
                lexicon: "chat.bsky.convo.listConvos", params: ["limit": "50"]
            )
            convos = resp.convos
            cursor = resp.cursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadMore() async {
        guard !isLoading, let cursor else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: ListConvosResponse = try await network.get(
                lexicon: "chat.bsky.convo.listConvos",
                params: ["limit": "50", "cursor": cursor]
            )
            convos.append(contentsOf: resp.convos)
            self.cursor = resp.cursor
        } catch {}
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let resp: ListConvosResponse = try await network.get(
                lexicon: "chat.bsky.convo.listConvos", params: ["limit": "50"]
            )
            convos = resp.convos
            cursor = resp.cursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func leaveConvo(_ convoId: String) async {
        convos.removeAll { $0.id == convoId }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "chat.bsky.convo.leaveConvo",
                body: ConvoIDRequest(convoId: convoId)
            )
        } catch {
            await refresh()
        }
    }

    public func muteConvo(_ convoId: String, muted: Bool) async {
        if let idx = convos.firstIndex(where: { $0.id == convoId }) {
            let original = convos[idx]
            convos[idx] = ConvoView(
                id: original.id, rev: original.rev, members: original.members,
                lastMessage: original.lastMessage, unreadCount: original.unreadCount,
                muted: muted
            )
        }
        do {
            let lexicon = muted ? "chat.bsky.convo.muteConvo" : "chat.bsky.convo.unmuteConvo"
            let resp: ConvoResponse = try await network.post(
                lexicon: lexicon, body: ConvoIDRequest(convoId: convoId)
            )
            if let idx = convos.firstIndex(where: { $0.id == convoId }) {
                convos[idx] = resp.convo
            }
        } catch {}
    }
}
