import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class ThreadViewModel {

    public var thread: ThreadViewPost?
    public var isLoading = false
    public var errorMessage: String?

    private let network: any NetworkClient
    private let uri: ATURI

    public init(network: any NetworkClient, uri: ATURI) {
        self.network = network
        self.uri = uri
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let params: [String: String] = [
                "uri": uri.rawValue,
                "depth": "6",
                "parentHeight": "80"
            ]
            let response: GetPostThreadResponse = try await network.get(
                lexicon: "app.bsky.feed.getPostThread",
                params: params
            )
            thread = response.thread
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
