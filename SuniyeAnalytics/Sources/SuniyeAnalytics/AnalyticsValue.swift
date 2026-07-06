import Foundation

/// A single analytics property value. The wire format only ever carries
/// numbers, booleans, and *controlled-vocabulary* strings — never free text.
///
/// There is deliberately no way to put arbitrary user content in here: the app
/// hands us typed `AnalyticsEvent` cases, the encoder turns those into these
/// values, and any string-shaped value must pass through `SafeLabel` first.
public enum AnalyticsValue: Codable, Equatable, Sendable {
    case int(Int)
    case double(Double)
    case bool(Bool)
    /// Always a controlled label (enum rawValue or `SafeLabel`), never free text.
    case label(String)

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .label(value): try container.encode(value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Order matters: JSON booleans must not be read as ints, and integers
        // must be tried before doubles so whole numbers round-trip as ints.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .label(try container.decode(String.self))
        }
    }
}

/// A sanitized, length-bounded identifier for open-ish vocabularies where a
/// closed enum is impractical (model ids, ASR family, language codes).
///
/// This is a structural privacy guard: even if the app mistakenly passes user
/// content where a model id is expected, `SafeLabel` strips it to a short slug
/// of `[a-z0-9._-]`, so a sentence or PII cannot survive as a label. Anything
/// that reduces to empty becomes `"unknown"`.
public struct SafeLabel: Encodable, Equatable, Sendable, CustomStringConvertible {
    public static let maxLength = 64
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")

    public let value: String

    public init(_ raw: String) {
        let lowered = raw.lowercased()
        var out = ""
        out.reserveCapacity(min(lowered.count, Self.maxLength))
        for scalar in lowered {
            guard out.count < Self.maxLength else { break }
            if Self.allowed.contains(scalar) {
                out.append(scalar)
            } else if scalar == " " || scalar == "/" || scalar == ":" {
                // Collapse common separators into a single dash rather than dropping,
                // so "Apple M3 Pro" -> "apple-m3-pro" stays readable.
                if out.last != "-" { out.append("-") }
            }
            // everything else (punctuation, unicode, control chars) is dropped
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        self.value = trimmed.isEmpty ? "unknown" : trimmed
    }

    public var description: String { value }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension AnalyticsValue {
    public static func label(_ safe: SafeLabel) -> AnalyticsValue { .label(safe.value) }
    public static func label<R: RawRepresentable>(_ raw: R) -> AnalyticsValue where R.RawValue == String {
        .label(raw.rawValue)
    }
}
