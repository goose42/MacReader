import Foundation

/// Publication dates as books write them: a full ISO date or timestamp, or just a year or a year and month.
enum EbookDate {
    static func parse(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime], [.withFullDate]] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: text) { return date }
        }
        guard let match = text.wholeMatch(of: /(\d{4})(?:-(\d{2}))?/), let year = Int(match.1) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: match.2.flatMap { Int($0) } ?? 1, day: 1))
    }
}
