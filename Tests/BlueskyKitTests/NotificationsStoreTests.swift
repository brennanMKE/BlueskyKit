import Testing
import Foundation
@testable import BlueskyNotifications
import BlueskyCore
import BlueskyKit

// MARK: - Mock network

/// Scriptable `NetworkClient` for store-level unread-badge tests (#0196).
///
/// `@unchecked Sendable` with plain vars is safe here: each test awaits the
/// store call before inspecting state, so the mock is never touched
/// concurrently.
private final class MockNotificationsNetwork: NetworkClient, @unchecked Sendable {
    /// Count the next `getUnreadCount` call reports. `updateSeen` zeroes it,
    /// mirroring the server's behavior.
    var unreadCount = 0
    var failGetUnreadCount = false
    private(set) var getUnreadCountCalls = 0
    private(set) var updateSeenCalls = 0

    nonisolated func get<Response: Decodable & Sendable>(
        lexicon: String,
        params: [String: String]
    ) async throws -> Response {
        switch lexicon {
        case "app.bsky.notification.getUnreadCount":
            getUnreadCountCalls += 1
            if failGetUnreadCount { throw ATError.unknown("mock unread failure") }
            let json = #"{"count": \#(unreadCount)}"#
            return try JSONDecoder().decode(Response.self, from: Data(json.utf8))
        default:
            throw ATError.unknown("unexpected GET \(lexicon)")
        }
    }

    nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String,
        body: Body
    ) async throws -> Response {
        switch lexicon {
        case "app.bsky.notification.updateSeen":
            updateSeenCalls += 1
            unreadCount = 0
            return try JSONDecoder().decode(Response.self, from: Data("{}".utf8))
        default:
            throw ATError.unknown("unexpected POST \(lexicon)")
        }
    }

    nonisolated func upload<Response: Decodable & Sendable>(
        lexicon: String,
        data: Data,
        mimeType: String
    ) async throws -> Response {
        throw ATError.unknown("unexpected upload \(lexicon)")
    }
}

// MARK: - Tests

@MainActor
@Suite("NotificationsStore unread badge (#0196)")
struct NotificationsStoreTests {

    @Test("fetchUnreadCount populates unreadCount from getUnreadCount")
    func fetchUnreadCountPopulatesState() async {
        let network = MockNotificationsNetwork()
        network.unreadCount = 7
        let store = NotificationsStore(network: network)
        #expect(store.unreadCount == 0)

        await store.fetchUnreadCount()

        #expect(store.unreadCount == 7)
        #expect(network.getUnreadCountCalls == 1)
    }

    @Test("fetchUnreadCount keeps the previous count when the call fails")
    func fetchUnreadCountKeepsCountOnError() async {
        let network = MockNotificationsNetwork()
        network.unreadCount = 5
        let store = NotificationsStore(network: network)
        await store.fetchUnreadCount()
        #expect(store.unreadCount == 5)

        network.failGetUnreadCount = true
        await store.fetchUnreadCount()

        // A transient poll failure must not flicker the badge to zero.
        #expect(store.unreadCount == 5)
        #expect(network.getUnreadCountCalls == 2)
    }

    @Test("markSeen posts updateSeen and zeroes the badge")
    func markSeenZeroesBadge() async {
        let network = MockNotificationsNetwork()
        network.unreadCount = 3
        let store = NotificationsStore(network: network)
        await store.fetchUnreadCount()
        #expect(store.unreadCount == 3)

        await store.markSeen()

        #expect(store.unreadCount == 0)
        #expect(network.updateSeenCalls == 1)
    }

    @Test("poll cycle: refetch after markSeen stays at zero")
    func pollCycleAfterMarkSeen() async {
        let network = MockNotificationsNetwork()
        network.unreadCount = 4
        let store = NotificationsStore(network: network)

        // Shell poll tick sees unread → badge populated.
        await store.fetchUnreadCount()
        #expect(store.unreadCount == 4)

        // User opens the Notifications tab → markSeen zeroes server + local.
        await store.markSeen()
        #expect(store.unreadCount == 0)

        // Next shell poll tick must not resurrect the badge.
        await store.fetchUnreadCount()
        #expect(store.unreadCount == 0)
        #expect(network.getUnreadCountCalls == 2)
        #expect(network.updateSeenCalls == 1)
    }
}
