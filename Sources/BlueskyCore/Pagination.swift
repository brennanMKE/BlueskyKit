/// Opaque server-side pagination cursor.
public typealias Cursor = String

/// A page of items returned from a cursor-paginated endpoint.
public struct PagedResult<T: Sendable>: Sendable {
    public let items: [T]
    /// Nil when there are no more pages.
    public let cursor: Cursor?

    public init(items: [T], cursor: Cursor?) {
        self.items = items
        self.cursor = cursor
    }
}
