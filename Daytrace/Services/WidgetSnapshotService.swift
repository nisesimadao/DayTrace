import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetSnapshotService {
    static func refresh(in context: ModelContext, now: Date = .now) {
        guard let episodes = try? context.fetch(FetchDescriptor<TimelineEpisode>()),
              let assertions = try? context.fetch(FetchDescriptor<UserAssertion>()),
              let journals = try? context.fetch(FetchDescriptor<JournalEntry>()),
              let places = try? context.fetch(FetchDescriptor<PlaceRecord>()) else {
            return
        }

        let today = CalendarDay(containing: now, timeZone: .current)
        let suppressed = TimelineVisibility.suppressedEpisodeIDs(from: assertions)
        let visibleToday = episodes
            .filter {
                !suppressed.contains($0.id)
                    && TimelineDayProjection.episode($0, intersects: today, openEndedAt: now)
            }
            .sorted { $0.startDate < $1.startDate }

        let stays = visibleToday.filter { $0.kind == .stay }
        let placesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let names = stays.map { displayName(for: $0, placesByID: placesByID) }
        let currentPlace = stays.last(where: { episode in
            episode.startDate <= now && (episode.endDate == nil || episode.endDate! > now)
        }).map { displayName(for: $0, placesByID: placesByID) }

        let movementMinutes = visibleToday
            .filter { $0.kind == .move }
            .reduce(into: 0) { total, episode in
                total += overlapMinutes(for: episode, day: today, now: now)
            }

        let hasJournal = journals.contains { journal in
            TimelineDayProjection.journal(journal, belongsTo: today)
                && !journal.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let snapshot = DaytraceWidgetSnapshot(
            day: DaytraceWidgetCivilDay(date: now, timeZone: .current),
            generatedAt: now,
            visitCount: stays.count,
            movementMinutes: movementMinutes,
            placeNames: names,
            hasJournal: hasJournal,
            currentPlaceName: currentPlace
        )

        if DaytraceWidgetSnapshotStore.save(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: DaytraceWidgetShared.widgetKind)
        }
    }

    private static func displayName(
        for episode: TimelineEpisode,
        placesByID: [UUID: PlaceRecord]
    ) -> String {
        if let placeID = episode.placeID,
           let place = placesByID[placeID],
           place.isPrivate {
            return "非公開の場所"
        }

        let trimmed = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "未設定の場所" || episode.confidence == .low {
            return "場所を確認"
        }
        return trimmed
    }

    private static func overlapMinutes(
        for episode: TimelineEpisode,
        day: CalendarDay,
        now: Date
    ) -> Int {
        let zone = TimelineDayProjection.timeZone(identifier: episode.timeZoneIdentifier)
        guard let dayDate = day.date(in: zone) else { return 0 }
        let interval = DayInterval(containing: dayDate, timeZone: zone)
        let start = max(episode.startDate, interval.start)
        let end = min(episode.endDate ?? now, min(interval.end, now))
        guard end > start else { return 0 }
        return max(Int(end.timeIntervalSince(start) / 60), 0)
    }
}
