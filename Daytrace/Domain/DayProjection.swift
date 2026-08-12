import Foundation

struct DayInterval: Sendable {
    let start: Date
    let end: Date
    let timeZone: TimeZone

    init(containing date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        self.start = start
        self.end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        self.timeZone = timeZone
    }

    func intersects(start episodeStart: Date, end episodeEnd: Date?) -> Bool {
        let effectiveEnd = episodeEnd ?? .distantFuture
        return episodeStart < end && effectiveEnd > start
    }
}

enum TimelineFormatting {
    static func clock(_ date: Date, timeZoneIdentifier: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "H:mm"
        if let timeZoneIdentifier, let zone = TimeZone(identifier: timeZoneIdentifier) {
            formatter.timeZone = zone
        }
        return formatter.string(from: date)
    }

    static func duration(from start: Date, to end: Date?) -> String? {
        guard let end, end > start else { return nil }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        if minutes < 60 { return "約\(max(minutes, 1))分" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "約\(hours)時間" : "約\(hours)時間\(remainder)分"
    }
}
