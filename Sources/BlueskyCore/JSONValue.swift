import Foundation

// MARK: - JSONValue

/// A loss-preserving representation of an arbitrary JSON value.
///
/// Used wherever the client must round-trip server data it does not model —
/// most importantly the `app.bsky.actor.getPreferences` →
/// `app.bsky.actor.putPreferences` cycle (#0201): `putPreferences` **replaces**
/// the account's entire `app.bsky` preference namespace, so every preference
/// entry the app doesn't understand (new lexicon types, other clients' prefs)
/// must survive the read-modify-write untouched. Decoding the raw
/// `preferences` array into `[JSONValue]` preserves the exact key set and
/// values of every entry so the merged put body carries them verbatim.
///
/// Numbers decode as `Int64` when the payload carries an integral value and
/// fall back to `Double` otherwise, so integers re-encode without a decimal
/// point.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? c.decode(Double.self) {
            self = .number(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? c.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Value is not a supported JSON type"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .integer(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }

    // MARK: Accessors

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var integerValue: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    /// The `$type` discriminator carried by AT Proto union objects, if this
    /// value is an object that has one. `nil` for non-objects and for objects
    /// without a `$type` key.
    public var typeDiscriminator: String? {
        objectValue?["$type"]?.stringValue
    }
}
