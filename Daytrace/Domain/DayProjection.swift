import Foundation

struct DayInterval: Sendable {
    let start: Date
    let end: Date
    let timeZone: TimeZone

    init(containing date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        if let interval = calendar.dateInterval(of: .day, for: date) {
            self.start = interval.start
            self.end = interval.end
        } else {
            let start = calendar.startOfDay(for: date)
            self.start = start
            self.end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        }
        self.timeZone = timeZone
    }

    func intersects(
        start episodeStart: Date,
        end episodeEnd: Date?,
        openEndedAt referenceDate: Date = .now
    ) -> Bool {
        let effectiveEnd = episodeEnd ?? referenceDate
        guard effectiveEnd > episodeStart else { return false }
        return episodeStart < end && effectiveEnd > start
    }
}

struct CalendarDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(containing date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 1
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }

    func date(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

struct CalendarMonthGrid: Sendable {
    static let weekdayTitles = ["月", "火", "水", "木", "金", "土", "日"]

    static func monthAnchor(containing date: Date, timeZone: TimeZone) -> Date {
        let calendar = gregorianCalendar(timeZone: timeZone)
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: components.year,
            month: components.month,
            day: 1,
            hour: 12
        )) ?? date
    }

    static func shiftedMonth(from date: Date, by amount: Int, timeZone: TimeZone) -> Date {
        let anchor = monthAnchor(containing: date, timeZone: timeZone)
        let calendar = gregorianCalendar(timeZone: timeZone)
        let shifted = calendar.date(byAdding: .month, value: amount, to: anchor) ?? anchor
        return monthAnchor(containing: shifted, timeZone: timeZone)
    }

    static func days(for displayedMonth: Date, timeZone: TimeZone) -> [Date?] {
        let calendar = gregorianCalendar(timeZone: timeZone)
        let anchor = monthAnchor(containing: displayedMonth, timeZone: timeZone)

        guard let interval = calendar.dateInterval(of: .month, for: anchor),
              let range = calendar.range(of: .day, in: .month, for: anchor)
        else { return [] }

        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let monthDates = range.compactMap { day in
            calendar.date(from: DateComponents(
                timeZone: timeZone,
                year: calendar.component(.year, from: interval.start),
                month: calendar.component(.month, from: interval.start),
                day: day,
                hour: 12
            ))
        }
        let trailing = max(0, 42 - leading - monthDates.count)
        return Array(repeating: nil, count: leading)
            + monthDates.map(Optional.some)
            + Array(repeating: nil, count: trailing)
    }

    private static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }
}

enum TimelineDayProjection {
    static func timeZone(identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? .current
    }

    /// A database-only candidate window for one civil day. Final membership must still
    /// be checked using each record's stored timezone. The one-day margin on both sides
    /// safely covers every timezone in Foundation's database without scanning years of data.
    static func queryEnvelope(for day: CalendarDay) -> DateInterval {
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let anchor = day.date(in: utc) ?? .now
        let utcDay = DayInterval(containing: anchor, timeZone: utc)
        let margin: TimeInterval = 24 * 60 * 60
        return DateInterval(
            start: utcDay.start.addingTimeInterval(-margin),
            end: utcDay.end.addingTimeInterval(margin)
        )
    }

    static func day(for episode: TimelineEpisode) -> CalendarDay {
        CalendarDay(
            containing: episode.startDate,
            timeZone: timeZone(identifier: episode.timeZoneIdentifier)
        )
    }

    static func day(for journal: JournalEntry) -> CalendarDay {
        CalendarDay(
            containing: journal.dayAnchor,
            timeZone: timeZone(identifier: journal.timeZoneIdentifier)
        )
    }

    static func episode(
        _ episode: TimelineEpisode,
        intersects day: CalendarDay,
        openEndedAt referenceDate: Date = .now
    ) -> Bool {
        let zone = timeZone(identifier: episode.timeZoneIdentifier)
        guard let date = day.date(in: zone) else { return false }
        let interval = DayInterval(containing: date, timeZone: zone)
        return interval.intersects(
            start: episode.startDate,
            end: episode.endDate,
            openEndedAt: referenceDate
        )
    }

    static func journal(_ journal: JournalEntry, belongsTo day: CalendarDay) -> Bool {
        self.day(for: journal) == day
    }

    static func coveredDays(
        by episode: TimelineEpisode,
        openEndedAt referenceDate: Date = .now,
        limit: Int = 14
    ) -> [CalendarDay] {
        let effectiveEnd = episode.endDate ?? referenceDate
        guard effectiveEnd > episode.startDate, limit > 0 else { return [] }

        let zone = timeZone(identifier: episode.timeZoneIdentifier)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let firstStart = calendar.startOfDay(for: episode.startDate)
        let lastInstant = effectiveEnd.addingTimeInterval(-0.001)
        var cursor = calendar.startOfDay(for: max(lastInstant, episode.startDate))
        var result: [CalendarDay] = []

        while cursor >= firstStart && result.count < limit {
            result.append(CalendarDay(containing: cursor, timeZone: zone))
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor),
                  previous < cursor else {
                break
            }
            cursor = previous
        }

        return result
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
