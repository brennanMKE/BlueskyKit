import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "ThreadStore")

// MARK: - ThreadStoring

public protocol ThreadStoring: AnyObject, Observable, Sendable {
    var thread: ThreadViewPost? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func load(uri: ATURI) async
}

// MARK: - ThreadStore

@Observable
public final class ThreadStore: ThreadStoring {

    public private(set) var thread: ThreadViewPost?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    public func load(uri: ATURI) async {
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
                lexicon: "app.bsky.feed.getPostThread", params: params
            )
            thread = response.thread
        } catch {
            logger.error("thread fetch error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
