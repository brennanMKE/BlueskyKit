/// Carries a cached value together with its freshness status.
///
/// Callers can immediately display `value` (even if stale) and kick off a
/// background refresh when `isExpired` is `true` — the stale-while-revalidate pattern.
public struct CacheResult<T: Sendable>: Sendable {
    public let value: T
    /// `true` when the entry's TTL has elapsed since it was stored.
    public let isExpired: Bool

    public init(value: T, isExpired: Bool) {
        self.value = value
        self.isExpired = isExpired
    }
}
