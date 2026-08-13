import Foundation

struct DaytraceWidgetCivilDay: Codable, Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }
}

struct DaytraceWidgetSnapshot: Codable, Equatable, Sendable {
    let day: DaytraceWidgetCivilDay
    let generatedAt: Date
    let visitCount: Int
    let movementMinutes: Int
    let placeNames: [String]
    let hasJournal: Bool
    let currentPlaceName: String?

    static func empty(now: Date = .now, timeZone: TimeZone = .current) -> DaytraceWidgetSnapshot {
        DaytraceWidgetSnapshot(
            day: DaytraceWidgetCivilDay(date: now, timeZone: timeZone),
            generatedAt: now,
            visitCount: 0,
            movementMinutes: 0,
            placeNames: [],
            hasJournal: false,
            currentPlaceName: nil
        )
    }
}

enum DaytraceWidgetShared {
    static let appGroupIdentifier = "group.dev.nisesimadao.Daytrace"
    static let snapshotKey = "daytrace.widget.today.snapshot.v1"
    static let widgetKind = "DaytraceTodayWidget"
    static let todayURL = URL(string: "daytrace://today")!
}

enum DaytraceWidgetSnapshotStore {
    static func load() -> DaytraceWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: DaytraceWidgetShared.appGroupIdentifier),
              let data = defaults.data(forKey: DaytraceWidgetShared.snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(DaytraceWidgetSnapshot.self, from: data)
    }

    @discardableResult
    static func save(_ snapshot: DaytraceWidgetSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: DaytraceWidgetShared.appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot) else {
            return false
        }
        defaults.set(data, forKey: DaytraceWidgetShared.snapshotKey)
        return true
    }
}
