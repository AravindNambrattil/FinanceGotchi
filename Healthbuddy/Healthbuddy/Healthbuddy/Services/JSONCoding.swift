import Foundation

/// Shared JSON configuration for the network layer and the on-disk goal store.
///
/// The backend stores timestamps with SQLite's `datetime('now')` (`"2026-09-19 11:23:00"`) and goal
/// deadlines as date-only strings (`"2026-12-15"`), neither of which `.iso8601` accepts. The decoder
/// below takes all three shapes so a real backend response and a locally persisted file decode the same way.
nonisolated enum JSONCoding {
    static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unrecognized date: \(raw)"
                ))
            }
            return date
        }
        return decoder
    }

    /// Accepts `2026-09-19T11:23:00Z`, `2026-09-19 11:23:00` (SQLite, UTC) and `2026-09-19`.
    static func parseDate(_ raw: String) -> Date? {
        let sqlite = Date.ISO8601FormatStyle()
            .year().month().day()
            .dateTimeSeparator(.space)
            .time(includingFractionalSeconds: false)
        let dateOnly = Date.ISO8601FormatStyle().year().month().day()

        return (try? Date(raw, strategy: .iso8601))
            ?? (try? Date(raw, strategy: sqlite))
            ?? (try? Date(raw, strategy: dateOnly))
    }
}
