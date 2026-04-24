import Foundation

/// Unified error type for AT Protocol / XRPC operations.
public enum ATError: Error, Sendable {
    /// A transport-level URL error.
    case network(URLError)
    /// An unexpected HTTP status code (not 200/4xx XRPC).
    case httpStatus(Int)
    /// No session is active; user must log in.
    case unauthenticated
    /// The access token has expired and could not be refreshed.
    case sessionExpired
    /// The server returned an XRPC error envelope (`error` + `message`).
    case xrpc(code: String, message: String)
    /// Response payload could not be decoded.
    case decodingFailed(String)
    /// Any other error; carries a human-readable description.
    case unknown(String)
}
