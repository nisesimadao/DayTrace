import SwiftData
import XCTest
@testable import Daytrace

final class DayProjectionTests: XCTestCase {
    private let baseTime = Date(timeIntervalSince1970: 1_786_500_000)
    private let zone = "Asia/Tokyo"

    func testDayIntervalIntersectsOvernightEpisode() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12)))
        let interval = DayInterval(containing: day, timeZone: timeZone)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 23)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 8)))

        XCTAssertTrue(interval.intersects(start: start, end: end))
    }

    func testFutureEpisodeDoesNotIntersect() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12)))
        let interval = DayInterval(containing: day, timeZone: timeZone)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 9)))

        XCTAssertFalse(interval.intersects(start: start, end: nil))
    }

    func testQueryEnvelopeContainsRecordedTimezoneDayIntervals() throws {
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let targetDays = try [
            DateComponents(year: 2026, month: 3, day: 8, hour: 12),
            DateComponents(year: 2026, month: 8, day: 12, hour: 12),
            DateComponents(year: 2026, month: 11, day: 1, hour: 12)
        ].map { components in
            CalendarDay(
                containing: try XCTUnwrap(calendar.date(from: components)),
                timeZone: utc
            )
        }

        for day in targetDays {
            let envelope = TimelineDayProjection.queryEnvelope(for: day)
            for identifier in TimeZone.knownTimeZoneIdentifiers {
                guard let timeZone = TimeZone(identifier: identifier),
                      let date = day.date(in: timeZone) else {
                    continue
                }
                let interval = DayInterval(containing: date, timeZone: timeZone)
                XCTAssertLessThanOrEqual(
                    envelope.start,
                    interval.start,
                    "Envelope starts too late for \(identifier) on \(day)"
                )
                XCTAssertGreaterThanOrEqual(
                    envelope.end,
                    interval.end,
                    "Envelope ends too early for \(identifier) on \(day)"
                )
            }
        }
    }

    func testHistoricalDisplayIntervalClipsMultiDayEpisodeToRecordedCivilDay() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let targetDate = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 8,
            day: 15,
            hour: 12
        )))
        let targetDay = CalendarDay(containing: targetDate, timeZone: timeZone)
        let episode = TimelineEpisode(
            kind: .stay,
            startDate: try XCTUnwrap(calendar.date(from: DateComponents(
                timeZone: timeZone, year: 2026, month: 8, day: 10, hour: 0, minute: 6
            ))),
            endDate: try XCTUnwrap(calendar.date(from: DateComponents(
                timeZone: timeZone, year: 2026, month: 8, day: 15, hour: 7, minute: 25
            ))),
            title: "長期滞在",
            confidence: .high,
            timeZoneIdentifier: timeZone.identifier
        )

        let display = try XCTUnwrap(TimelineDayProjection.displayInterval(for: episode, on: targetDay))
        let expectedStart = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone, year: 2026, month: 8, day: 15, hour: 0
        )))

        XCTAssertEqual(display.start, expectedStart)
        XCTAssertEqual(display.end, episode.endDate)
        XCTAssertEqual(display.duration, 7 * 60 * 60 + 25 * 60, accuracy: 0.1)
    }

    func testHistoricalDisplayIntervalUsesEpisodeRecordedTimezone() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        let targetDate = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: losAngeles, year: 2026, month: 8, day: 12, hour: 12
        )))
        let targetDay = CalendarDay(containing: targetDate, timeZone: losAngeles)
        let episode = TimelineEpisode(
            kind: .move,
            startDate: try XCTUnwrap(calendar.date(from: DateComponents(
                timeZone: losAngeles, year: 2026, month: 8, day: 11, hour: 23
            ))),
            endDate: try XCTUnwrap(calendar.date(from: DateComponents(
                timeZone: losAngeles, year: 2026, month: 8, day: 12, hour: 2
            ))),
            title: "移動",
            confidence: .medium,
            timeZoneIdentifier: losAngeles.identifier
        )

        let display = try XCTUnwrap(TimelineDayProjection.displayInterval(for: episode, on: targetDay))
        let expectedStart = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: losAngeles, year: 2026, month: 8, day: 12, hour: 0
        )))

        XCTAssertEqual(display.start, expectedStart)
        XCTAssertEqual(display.end, episode.endDate)
        XCTAssertEqual(display.duration, 2 * 60 * 60, accuracy: 0.1)
    }

    func testOngoingEpisodeDoesNotMarkFutureDay() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 18)))
        let episodeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 9)))
        let today = DayInterval(containing: now, timeZone: timeZone)
        let tomorrowDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let tomorrow = DayInterval(containing: tomorrowDate, timeZone: timeZone)

        XCTAssertTrue(today.intersects(start: episodeStart, end: nil, openEndedAt: now))
        XCTAssertFalse(tomorrow.intersects(start: episodeStart, end: nil, openEndedAt: now))
    }

    @MainActor
    func testHistoricalDayLocationQueryFetchesOnlyTargetTokyoDay() throws {
        let context = try makeContext()
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 8,
            day: 12,
            hour: 12
        )))
        let interval = DayInterval(containing: noon, timeZone: timeZone)

        let previous = locationEvidence(at: interval.start.addingTimeInterval(-1))
        let atStart = locationEvidence(at: interval.start)
        let midday = locationEvidence(at: interval.start.addingTimeInterval(12 * 60 * 60))
        let beforeEnd = locationEvidence(at: interval.end.addingTimeInterval(-0.001))
        let atEnd = locationEvidence(at: interval.end)
        for evidence in [previous, atStart, midday, beforeEnd, atEnd] {
            context.insert(evidence)
        }
        try context.save()

        let fetched = try HistoricalDayDataQuery.locationEvidence(in: interval, context: context)

        XCTAssertEqual(fetched.map(\.id), [atStart.id, midday.id, beforeEnd.id])
        XCTAssertFalse(fetched.contains { $0.id == previous.id })
        XCTAssertFalse(fetched.contains { $0.id == atEnd.id })
    }

    @MainActor
    func testHistoricalDayLocationQueryRespectsDSTDayLengths() throws {
        let context = try makeContext()
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let springNoon = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 3,
            day: 8,
            hour: 12
        )))
        let fallNoon = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 11,
            day: 1,
            hour: 12
        )))
        let spring = DayInterval(containing: springNoon, timeZone: timeZone)
        let fall = DayInterval(containing: fallNoon, timeZone: timeZone)
        XCTAssertEqual(spring.end.timeIntervalSince(spring.start), 23 * 60 * 60, accuracy: 0.1)
        XCTAssertEqual(fall.end.timeIntervalSince(fall.start), 25 * 60 * 60, accuracy: 0.1)

        let springInside = locationEvidence(at: spring.end.addingTimeInterval(-1))
        let springOutside = locationEvidence(at: spring.end)
        let fallInside = locationEvidence(at: fall.end.addingTimeInterval(-1))
        let fallOutside = locationEvidence(at: fall.end)
        for evidence in [springInside, springOutside, fallInside, fallOutside] {
            context.insert(evidence)
        }
        try context.save()

        XCTAssertEqual(
            try HistoricalDayDataQuery.locationEvidence(in: spring, context: context).map(\.id),
            [springInside.id]
        )
        XCTAssertEqual(
            try HistoricalDayDataQuery.locationEvidence(in: fall, context: context).map(\.id),
            [fallInside.id]
        )
    }

    @MainActor
    func testHistoricalDayLocationQueryUsesEachEvidenceRecordedTimezone() throws {
        let context = try makeContext()
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = tokyo
        var losAngelesCalendar = Calendar(identifier: .gregorian)
        losAngelesCalendar.timeZone = losAngeles

        let targetDate = try XCTUnwrap(tokyoCalendar.date(from: DateComponents(
            timeZone: tokyo,
            year: 2026,
            month: 8,
            day: 12,
            hour: 12
        )))
        let targetDay = CalendarDay(containing: targetDate, timeZone: tokyo)
        let tokyoInsideDate = try XCTUnwrap(tokyoCalendar.date(from: DateComponents(
            timeZone: tokyo,
            year: 2026,
            month: 8,
            day: 12,
            hour: 0,
            minute: 30
        )))
        let losAngelesInsideDate = try XCTUnwrap(losAngelesCalendar.date(from: DateComponents(
            timeZone: losAngeles,
            year: 2026,
            month: 8,
            day: 12,
            hour: 23,
            minute: 30
        )))
        let tokyoOutsideDate = try XCTUnwrap(tokyoCalendar.date(from: DateComponents(
            timeZone: tokyo,
            year: 2026,
            month: 8,
            day: 13,
            hour: 0
        )))
        let losAngelesOutsideDate = try XCTUnwrap(losAngelesCalendar.date(from: DateComponents(
            timeZone: losAngeles,
            year: 2026,
            month: 8,
            day: 11,
            hour: 23,
            minute: 59
        )))

        let tokyoInside = LocationEvidence(
            timestamp: tokyoInsideDate,
            latitude: 35.68,
            longitude: 139.76,
            horizontalAccuracy: 20,
            speed: 0,
            course: 0,
            source: .standardLocation,
            timeZoneIdentifier: tokyo.identifier
        )
        let losAngelesInside = LocationEvidence(
            timestamp: losAngelesInsideDate,
            latitude: 34.05,
            longitude: -118.24,
            horizontalAccuracy: 20,
            speed: 0,
            course: 0,
            source: .standardLocation,
            timeZoneIdentifier: losAngeles.identifier
        )
        let tokyoOutside = LocationEvidence(
            timestamp: tokyoOutsideDate,
            latitude: 35.68,
            longitude: 139.76,
            horizontalAccuracy: 20,
            speed: 0,
            course: 0,
            source: .standardLocation,
            timeZoneIdentifier: tokyo.identifier
        )
        let losAngelesOutside = LocationEvidence(
            timestamp: losAngelesOutsideDate,
            latitude: 34.05,
            longitude: -118.24,
            horizontalAccuracy: 20,
            speed: 0,
            course: 0,
            source: .standardLocation,
            timeZoneIdentifier: losAngeles.identifier
        )
        for evidence in [tokyoInside, losAngelesInside, tokyoOutside, losAngelesOutside] {
            context.insert(evidence)
        }
        try context.save()

        let fetched = try HistoricalDayDataQuery.locationEvidence(on: targetDay, context: context)

        XCTAssertEqual(Set(fetched.map(\.id)), Set([tokyoInside.id, losAngelesInside.id]))
    }

    @MainActor
    func testHistoricalDayLocationQueryRemainsScopedWithLargeMultiDayFixture() throws {
        let context = try makeContext()
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let targetNoon = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 8,
            day: 12,
            hour: 12
        )))
        let targetInterval = DayInterval(containing: targetNoon, timeZone: timeZone)
        let targetDayIndex = 15
        let days = 31
        let samplesPerDay = 200
        var expectedTargetIDs = Set<UUID>()

        for dayIndex in 0..<days {
            let dayStart = try XCTUnwrap(calendar.date(
                byAdding: .day,
                value: dayIndex - targetDayIndex,
                to: targetInterval.start
            ))
            for sampleIndex in 0..<samplesPerDay {
                let timestamp = dayStart.addingTimeInterval(Double(sampleIndex) * 4 * 60)
                let evidence = locationEvidence(at: timestamp)
                context.insert(evidence)
                if dayIndex == targetDayIndex {
                    expectedTargetIDs.insert(evidence.id)
                }
            }
        }
        try context.save()

        let fetched = try HistoricalDayDataQuery.locationEvidence(in: targetInterval, context: context)

        XCTAssertEqual(fetched.count, samplesPerDay)
        XCTAssertEqual(Set(fetched.map(\.id)), expectedTargetIDs)
    }

    @MainActor
    func testHistoryDayIndexTreatsEpisodeEndAsExclusive() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 8,
            day: 12,
            hour: 23
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 8,
            day: 13,
            hour: 0
        )))
        let episode = TimelineEpisode(
            kind: .stay,
            startDate: start,
            endDate: end,
            title: "夜の滞在",
            confidence: .high,
            sourceVersion: TimelineEngine.sourceVersion,
            timeZoneIdentifier: timeZone.identifier
        )
        let august12 = CalendarDay(containing: start, timeZone: timeZone)
        let august13 = CalendarDay(
            containing: end.addingTimeInterval(12 * 60 * 60),
            timeZone: timeZone
        )

        let indexed = HistoryDayIndex.episodeDays(
            episodes: [episode],
            among: [august12, august13],
            openEndedAt: end
        )

        XCTAssertEqual(indexed, Set([august12]))
    }

    @MainActor
    func testHistoryDayIndexRespectsDSTAndRecordedTimezone() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 3,
            day: 7,
            hour: 23,
            minute: 30
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 3,
            day: 9,
            hour: 0
        )))
        let episode = TimelineEpisode(
            kind: .stay,
            startDate: start,
            endDate: end,
            title: "DSTをまたぐ滞在",
            confidence: .high,
            sourceVersion: TimelineEngine.sourceVersion,
            timeZoneIdentifier: timeZone.identifier
        )
        let march7 = CalendarDay(containing: start, timeZone: timeZone)
        let march8 = CalendarDay(
            containing: try XCTUnwrap(calendar.date(from: DateComponents(
                timeZone: timeZone,
                year: 2026,
                month: 3,
                day: 8,
                hour: 12
            ))),
            timeZone: timeZone
        )
        let march9 = CalendarDay(
            containing: try XCTUnwrap(calendar.date(from: DateComponents(
                timeZone: timeZone,
                year: 2026,
                month: 3,
                day: 9,
                hour: 12
            ))),
            timeZone: timeZone
        )

        let indexed = HistoryDayIndex.episodeDays(
            episodes: [episode],
            among: [march7, march8, march9],
            openEndedAt: end
        )

        XCTAssertEqual(indexed, Set([march7, march8]))
        XCTAssertEqual(end.timeIntervalSince(start), 23.5 * 60 * 60, accuracy: 1)
    }

    func testCalendarMonthGridUsesMondayFirstStableSixWeekGrid() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 20)))

        let days = CalendarMonthGrid.days(for: month, timeZone: timeZone)

        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.prefix(5).compactMap(\.self).count, 0)
        XCTAssertEqual(days.compactMap(\.self).count, 31)
        XCTAssertEqual(
            days.compactMap { $0 }.first.map { CalendarDay(containing: $0, timeZone: timeZone) },
            CalendarDay(containing: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12))), timeZone: timeZone)
        )
    }

    func testCalendarMonthShiftKeepsFirstDayAnchorAcrossShortMonths() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let januaryEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 23)))

        let february = CalendarMonthGrid.shiftedMonth(from: januaryEnd, by: 1, timeZone: timeZone)
        let march = CalendarMonthGrid.shiftedMonth(from: february, by: 1, timeZone: timeZone)

        XCTAssertEqual(CalendarDay(containing: february, timeZone: timeZone), CalendarDay(containing: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 12))), timeZone: timeZone))
        XCTAssertEqual(CalendarDay(containing: march, timeZone: timeZone), CalendarDay(containing: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12))), timeZone: timeZone))
    }

    @MainActor
    func testRenameAssertionDoesNotFreezeAutomaticDeparture() throws {
        let context = try makeContext()
        let departure = baseTime.addingTimeInterval(60 * 60 * 7)
        let visit = insertVisit(arrival: baseTime, departure: nil, observedAt: baseTime, in: context)
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60))
        let first = try firstStay(in: context)
        try TimelineEditingService().saveStay(
            first,
            title: "学校",
            startDate: first.startDate,
            endDate: first.endDate,
            confirmLocation: false,
            in: context
        )

        visit.departureDate = departure
        visit.observedAt = departure
        try context.save()
        try TimelineEngine().rebuildRecentTimeline(in: context, now: departure.addingTimeInterval(60))

        let rebuilt = try stay(for: visit.id, in: context)
        XCTAssertEqual(rebuilt.title, "学校")
        XCTAssertEqual(rebuilt.endDate, departure)
    }

    @MainActor
    func testEditingArrivalDoesNotFreezeAutomaticDeparture() throws {
        let context = try makeContext()
        let editedArrival = baseTime.addingTimeInterval(-10 * 60)
        let departure = baseTime.addingTimeInterval(60 * 60 * 5)
        let visit = insertVisit(arrival: baseTime, departure: nil, observedAt: baseTime, in: context)
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60))
        let first = try firstStay(in: context)
        try TimelineEditingService().saveStay(
            first,
            title: first.title,
            startDate: editedArrival,
            endDate: first.endDate,
            confirmLocation: false,
            in: context
        )

        visit.departureDate = departure
        visit.observedAt = departure
        try context.save()
        try TimelineEngine().rebuildRecentTimeline(in: context, now: departure.addingTimeInterval(60))

        let rebuilt = try stay(for: visit.id, in: context)
        XCTAssertEqual(rebuilt.startDate, editedArrival)
        XCTAssertEqual(rebuilt.endDate, departure)
    }

    @MainActor
    func testEditingDepartureDoesNotFreezeAutomaticArrivalRefinement() throws {
        let context = try makeContext()
        let initialDeparture = baseTime.addingTimeInterval(60 * 60 * 4)
        let editedDeparture = initialDeparture.addingTimeInterval(20 * 60)
        let refinedArrival = baseTime.addingTimeInterval(5 * 60)
        let visit = insertVisit(
            arrival: baseTime,
            departure: initialDeparture,
            observedAt: initialDeparture,
            in: context
        )
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: initialDeparture.addingTimeInterval(60))
        let first = try firstStay(in: context)
        try TimelineEditingService().saveStay(
            first,
            title: first.title,
            startDate: first.startDate,
            endDate: editedDeparture,
            confirmLocation: false,
            in: context
        )

        visit.arrivalDate = refinedArrival
        visit.observedAt = editedDeparture
        try context.save()
        try TimelineEngine().rebuildRecentTimeline(in: context, now: editedDeparture.addingTimeInterval(60))

        let rebuilt = try stay(for: visit.id, in: context)
        XCTAssertEqual(rebuilt.startDate, refinedArrival)
        XCTAssertEqual(rebuilt.endDate, editedDeparture)
    }

    @MainActor
    func testClearingDepartureKeepsOngoingOverride() throws {
        let context = try makeContext()
        let departure = baseTime.addingTimeInterval(60 * 60 * 2)
        let visit = insertVisit(
            arrival: baseTime,
            departure: departure,
            observedAt: departure,
            in: context
        )
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: departure.addingTimeInterval(60))
        let first = try firstStay(in: context)
        try TimelineEditingService().saveStay(
            first,
            title: first.title,
            startDate: first.startDate,
            endDate: nil,
            confirmLocation: false,
            in: context
        )
        try TimelineEngine().rebuildRecentTimeline(in: context, now: departure.addingTimeInterval(120))

        XCTAssertNil(try stay(for: visit.id, in: context).endDate)
    }

    @MainActor
    func testUnknownArrivalDoesNotInventStay() throws {
        let context = try makeContext()
        insertVisit(
            arrival: nil,
            departure: baseTime,
            observedAt: baseTime,
            accuracy: 40,
            in: context
        )
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60))

        XCTAssertTrue(try stays(in: context).isEmpty)
    }

    @MainActor
    func testAutomaticPlaceSuggestionSurvivesTimelineRebuild() throws {
        let context = try makeContext()
        let visit = insertVisit(arrival: baseTime, departure: nil, observedAt: baseTime, in: context)
        let episode = TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: nil,
            title: "未設定の場所",
            latitude: visit.latitude,
            longitude: visit.longitude,
            confidence: .medium,
            sourceVisitID: visit.id,
            sourceVersion: TimelineEngine.sourceVersion,
            timeZoneIdentifier: zone
        )
        context.insert(episode)
        context.insert(UserAssertion(
            episodeID: episode.id,
            type: .automaticPlaceSuggestion,
            replacementTitle: "近くのカフェ"
        ))
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60))

        let rebuilt = try stay(for: visit.id, in: context)
        XCTAssertEqual(rebuilt.title, "近くのカフェ")
        XCTAssertEqual(rebuilt.subtitle, "近くのスポット候補・確認してください")
        XCTAssertNil(rebuilt.placeID)
    }

    @MainActor
    func testLearnedPlaceOverridesAutomaticPlaceSuggestion() throws {
        let context = try makeContext()
        let place = PlaceRecord(
            name: "家",
            latitude: 34.66,
            longitude: 133.92,
            radius: 100,
            source: .userConfirmed
        )
        context.insert(place)
        let visit = insertVisit(arrival: baseTime, departure: nil, observedAt: baseTime, in: context)
        let episode = TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: nil,
            title: "未設定の場所",
            latitude: visit.latitude,
            longitude: visit.longitude,
            confidence: .medium,
            sourceVisitID: visit.id,
            sourceVersion: TimelineEngine.sourceVersion,
            timeZoneIdentifier: zone
        )
        context.insert(episode)
        context.insert(UserAssertion(
            episodeID: episode.id,
            type: .automaticPlaceSuggestion,
            replacementTitle: "近くのカフェ"
        ))
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60))

        let rebuilt = try stay(for: visit.id, in: context)
        XCTAssertEqual(rebuilt.title, "家")
        XCTAssertEqual(rebuilt.placeID, place.id)
    }

    @MainActor
    func testDepartureOnlyVisitUsesEarlierRawLocationAsStayStart() throws {
        let context = try makeContext()
        let home = PlaceRecord(
            name: "家",
            latitude: 34.66,
            longitude: 133.92,
            radius: 100,
            source: .userConfirmed
        )
        context.insert(home)
        context.insert(locationEvidence(
            at: baseTime,
            latitude: 34.66,
            longitude: 133.92,
            speed: -1
        ))
        let departure = baseTime.addingTimeInterval(90 * 60)
        let visit = insertVisit(
            arrival: nil,
            departure: departure,
            observedAt: departure.addingTimeInterval(60),
            latitude: 34.660_01,
            longitude: 133.920_01,
            accuracy: 20,
            in: context
        )
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: departure.addingTimeInterval(60 * 60))

        let stay = try stay(for: visit.id, in: context)
        XCTAssertEqual(stay.title, "家")
        XCTAssertEqual(stay.placeID, home.id)
        XCTAssertEqual(stay.startDate, baseTime)
        XCTAssertEqual(stay.endDate, departure)
    }

    @MainActor
    func testLowAccuracyVisitDoesNotAutoResolvePlace() throws {
        let context = try makeContext()
        context.insert(PlaceRecord(
            name: "学校",
            latitude: 34.66,
            longitude: 133.92,
            radius: 100,
            source: .userConfirmed
        ))
        insertVisit(
            arrival: baseTime,
            departure: baseTime.addingTimeInterval(60 * 60),
            observedAt: baseTime,
            latitude: 34.67,
            longitude: 133.93,
            accuracy: 5_000,
            in: context
        )
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60 * 60))

        let stay = try firstStay(in: context)
        XCTAssertNil(stay.placeID)
        XCTAssertEqual(stay.title, "未設定の場所")
        XCTAssertEqual(stay.confidence, .low)
    }

    @MainActor
    func testRebuildPreservesExistingPlaceWhenLaterAccuracyIsTooLowToResolve() throws {
        let context = try makeContext()
        let home = PlaceRecord(
            name: "家",
            latitude: 34.66,
            longitude: 133.92,
            radius: 100,
            source: .userConfirmed
        )
        context.insert(home)
        let visit = insertVisit(
            arrival: baseTime,
            departure: baseTime.addingTimeInterval(60 * 60),
            observedAt: baseTime,
            accuracy: 30,
            in: context
        )
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60 * 60))
        let stay = try stay(for: visit.id, in: context)
        XCTAssertEqual(stay.title, "家")
        XCTAssertEqual(stay.placeID, home.id)

        visit.horizontalAccuracy = 800
        try context.save()
        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(2 * 60 * 60))

        XCTAssertEqual(stay.title, "家")
        XCTAssertEqual(stay.placeID, home.id)
        XCTAssertNotEqual(stay.title, "未設定の場所")
    }

    @MainActor
    func testRebuildKeepsEarlierKnownArrivalWhenVisitArrivalMovesLater() throws {
        let context = try makeContext()
        let visit = insertVisit(
            arrival: baseTime,
            departure: baseTime.addingTimeInterval(2 * 60 * 60),
            observedAt: baseTime,
            in: context
        )
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60 * 60))
        let stay = try stay(for: visit.id, in: context)
        XCTAssertEqual(stay.startDate, baseTime)

        visit.arrivalDate = baseTime.addingTimeInterval(60 * 60)
        visit.observedAt = baseTime.addingTimeInterval(60 * 60)
        try context.save()
        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(3 * 60 * 60))

        XCTAssertEqual(stay.startDate, baseTime)
        XCTAssertEqual(stay.endDate, baseTime.addingTimeInterval(2 * 60 * 60))
    }

    @MainActor
    func testUnnamedPlaceCannotBeConfirmed() throws {
        let context = try makeContext()
        let stay = TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: baseTime.addingTimeInterval(60 * 60),
            title: "未設定の場所",
            subtitle: "場所を確認",
            latitude: 34.66,
            longitude: 133.92,
            confidence: .low,
            sourceVersion: 5,
            timeZoneIdentifier: zone
        )
        context.insert(stay)
        try context.save()

        try TimelineEditingService().saveStay(
            stay,
            title: "",
            startDate: stay.startDate,
            endDate: stay.endDate,
            confirmLocation: true,
            in: context
        )

        XCTAssertEqual(stay.confidence, .low)
        XCTAssertEqual(stay.subtitle, "場所を確認")
        XCTAssertNil(stay.placeID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlaceRecord>()).isEmpty)
        XCTAssertFalse(try context.fetch(FetchDescriptor<UserAssertion>()).contains { $0.type == .confirm && $0.isActive })
    }

    @MainActor
    func testRenamingResolvedStayDoesNotRenameExistingPlace() throws {
        let context = try makeContext()
        let originalPlace = PlaceRecord(
            name: "学校",
            latitude: 34.66,
            longitude: 133.92,
            radius: 100,
            source: .userConfirmed
        )
        context.insert(originalPlace)
        insertVisit(
            arrival: baseTime,
            departure: baseTime.addingTimeInterval(60 * 60),
            observedAt: baseTime,
            in: context
        )
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60 * 60))
        let stay = try firstStay(in: context)
        XCTAssertEqual(stay.placeID, originalPlace.id)

        try TimelineEditingService().saveStay(
            stay,
            title: "塾",
            startDate: stay.startDate,
            endDate: stay.endDate,
            confirmLocation: false,
            in: context
        )

        XCTAssertEqual(originalPlace.name, "学校")
        XCTAssertEqual(stay.title, "塾")
        XCTAssertNil(stay.placeID)
        XCTAssertEqual(stay.confidence, .medium)
        XCTAssertEqual(stay.subtitle, "場所を確認")
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlaceRecord>()).count, 1)
    }

    @MainActor
    func testConfirmingCorrectedStayLearnsNewPlaceWithoutMutatingOldPlace() throws {
        let context = try makeContext()
        let originalPlace = PlaceRecord(
            name: "学校",
            latitude: 34.66,
            longitude: 133.92,
            radius: 100,
            source: .userConfirmed
        )
        context.insert(originalPlace)
        insertVisit(
            arrival: baseTime,
            departure: baseTime.addingTimeInterval(60 * 60),
            observedAt: baseTime,
            in: context
        )
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60 * 60))
        let stay = try firstStay(in: context)

        try TimelineEditingService().saveStay(
            stay,
            title: "塾",
            startDate: stay.startDate,
            endDate: stay.endDate,
            confirmLocation: true,
            in: context
        )

        let places = try context.fetch(FetchDescriptor<PlaceRecord>())
        let learned = try XCTUnwrap(places.first { $0.id != originalPlace.id })
        XCTAssertEqual(originalPlace.name, "学校")
        XCTAssertEqual(learned.name, "塾")
        XCTAssertEqual(learned.source, .userConfirmed)
        XCTAssertEqual(stay.placeID, learned.id)
        XCTAssertEqual(stay.confidence, .high)
        XCTAssertNil(stay.subtitle)
        XCTAssertEqual(places.count, 2)
    }

    @MainActor
    func testOverlappingRetimeIsRejectedWithoutMutation() throws {
        let context = try makeContext()
        let first = insertCanonicalStay(title: "学校", in: context)
        let second = insertCanonicalStay(
            title: "塾",
            start: baseTime.addingTimeInterval(2 * 60 * 60),
            in: context
        )
        try context.save()
        let originalEnd = first.endDate

        XCTAssertThrowsError(
            try TimelineEditingService().saveStay(
                first,
                title: first.title,
                startDate: first.startDate,
                endDate: second.startDate.addingTimeInterval(30 * 60),
                confirmLocation: false,
                in: context
            )
        ) { error in
            guard let editingError = error as? TimelineEditingError else {
                return XCTFail("Expected TimelineEditingError")
            }
            XCTAssertEqual(editingError, .overlapsStay("塾"))
        }

        XCTAssertEqual(first.endDate, originalEnd)
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<UserAssertion>()).contains {
                $0.episodeID == first.id
                    && $0.isActive
                    && ($0.type == .retime || $0.type == .retimeStart || $0.type == .retimeEnd)
            }
        )
    }

    @MainActor
    func testExactBoundaryRetimeIsAllowed() throws {
        let context = try makeContext()
        let first = insertCanonicalStay(title: "学校", in: context)
        let second = insertCanonicalStay(
            title: "塾",
            start: baseTime.addingTimeInterval(2 * 60 * 60),
            in: context
        )
        try context.save()

        try TimelineEditingService().saveStay(
            first,
            title: first.title,
            startDate: first.startDate,
            endDate: second.startDate,
            confirmLocation: false,
            in: context
        )

        XCTAssertEqual(first.endDate, second.startDate)
    }

    @MainActor
    func testOngoingRetimeIsRejectedWhenFutureStayExists() throws {
        let context = try makeContext()
        let first = insertCanonicalStay(title: "学校", in: context)
        insertCanonicalStay(
            title: "塾",
            start: baseTime.addingTimeInterval(2 * 60 * 60),
            in: context
        )
        try context.save()

        XCTAssertThrowsError(
            try TimelineEditingService().saveStay(
                first,
                title: first.title,
                startDate: first.startDate,
                endDate: nil,
                confirmLocation: false,
                in: context
            )
        ) { error in
            guard let editingError = error as? TimelineEditingError else {
                return XCTFail("Expected TimelineEditingError")
            }
            XCTAssertEqual(editingError, .overlapsStay("塾"))
        }
        XCTAssertNotNil(first.endDate)
    }

    @MainActor
    func testSuppressedStayDoesNotBlockRetime() throws {
        let context = try makeContext()
        let first = insertCanonicalStay(title: "学校", in: context)
        let hidden = insertCanonicalStay(
            title: "誤記録",
            start: baseTime.addingTimeInterval(2 * 60 * 60),
            in: context
        )
        try context.save()

        let editor = TimelineEditingService()
        try editor.setSuppressed(episodeID: hidden.id, suppressed: true, in: context)
        let newEnd = hidden.startDate.addingTimeInterval(30 * 60)
        try editor.saveStay(
            first,
            title: first.title,
            startDate: first.startDate,
            endDate: newEnd,
            confirmLocation: false,
            in: context
        )

        XCTAssertEqual(first.endDate, newEnd)
    }

    @MainActor
    func testRetentionPrunesOnlyRawEvidence() throws {
        let context = try makeContext()
        let oldDate = baseTime.addingTimeInterval(-40 * 86_400)
        let freshDate = baseTime.addingTimeInterval(-5 * 86_400)

        context.insert(locationEvidence(at: oldDate))
        context.insert(locationEvidence(at: freshDate, latitude: 34.67, longitude: 133.93))
        insertVisit(arrival: oldDate, departure: oldDate.addingTimeInterval(60 * 60), observedAt: oldDate, in: context)
        insertVisit(
            arrival: freshDate,
            departure: freshDate.addingTimeInterval(60 * 60),
            observedAt: freshDate,
            latitude: 34.67,
            longitude: 133.93,
            in: context
        )
        let canonicalEpisode = TimelineEpisode(
            kind: .stay,
            startDate: oldDate,
            endDate: oldDate.addingTimeInterval(60 * 60),
            title: "古い思い出",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: zone
        )
        context.insert(canonicalEpisode)
        try context.save()

        try RawEvidenceRetentionService().prune(in: context, retentionDays: 30, now: baseTime)

        let locations = try context.fetch(FetchDescriptor<LocationEvidence>())
        let visits = try context.fetch(FetchDescriptor<VisitEvidence>())
        let episodes = try context.fetch(FetchDescriptor<TimelineEpisode>())
        XCTAssertEqual(locations.map(\.timestamp), [freshDate])
        XCTAssertEqual(visits.map(\.observedAt), [freshDate])
        XCTAssertTrue(episodes.contains { $0.id == canonicalEpisode.id })
    }

    @MainActor
    func testForeverRetentionDoesNotDeleteRawEvidence() throws {
        let context = try makeContext()
        context.insert(locationEvidence(at: baseTime.addingTimeInterval(-400 * 86_400)))
        try context.save()

        try RawEvidenceRetentionService().prune(in: context, retentionDays: 0, now: baseTime)

        XCTAssertEqual(try context.fetch(FetchDescriptor<LocationEvidence>()).count, 1)
    }

    @MainActor
    func testLegacyVisitBackfillUsesKnownDepartureBeforeRetention() throws {
        let context = try makeContext()
        let arrival = baseTime.addingTimeInterval(-2 * 86_400)
        let departure = arrival.addingTimeInterval(60 * 60)
        let visit = insertVisit(
            arrival: arrival,
            departure: departure,
            observedAt: Date.distantPast,
            in: context
        )
        try context.save()

        let retention = RawEvidenceRetentionService()
        try retention.backfillLegacyVisits(in: context)
        XCTAssertEqual(visit.observedAt, departure)

        try retention.prune(in: context, retentionDays: 30, now: baseTime)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VisitEvidence>()).count, 1)
    }

    @MainActor
    func testSuppressAndRestoreKeepsEpisode() throws {
        let context = try makeContext()
        let episode = insertCanonicalStay(title: "学校", in: context)
        try context.save()

        let editor = TimelineEditingService()
        try editor.setSuppressed(episodeID: episode.id, suppressed: true, in: context)

        var assertions = try context.fetch(FetchDescriptor<UserAssertion>())
        XCTAssertTrue(TimelineVisibility.suppressedEpisodeIDs(from: assertions).contains(episode.id))
        XCTAssertTrue(try context.fetch(FetchDescriptor<TimelineEpisode>()).contains { $0.id == episode.id })

        try editor.setSuppressed(episodeID: episode.id, suppressed: false, in: context)
        assertions = try context.fetch(FetchDescriptor<UserAssertion>())
        XCTAssertFalse(TimelineVisibility.suppressedEpisodeIDs(from: assertions).contains(episode.id))
        XCTAssertTrue(try context.fetch(FetchDescriptor<TimelineEpisode>()).contains { $0.id == episode.id })
    }

    @MainActor
    func testRestoreAllSuppressedRestoresEveryEpisode() throws {
        let context = try makeContext()
        let first = insertCanonicalStay(title: "学校", in: context)
        let second = insertCanonicalStay(
            title: "家",
            start: baseTime.addingTimeInterval(60 * 60 * 3),
            in: context
        )
        try context.save()

        let editor = TimelineEditingService()
        try editor.setSuppressed(episodeID: first.id, suppressed: true, in: context)
        try editor.setSuppressed(episodeID: second.id, suppressed: true, in: context)
        XCTAssertEqual(
            TimelineVisibility.suppressedEpisodeIDs(from: try context.fetch(FetchDescriptor<UserAssertion>())).count,
            2
        )

        try editor.restoreAllSuppressed(in: context)

        XCTAssertTrue(
            TimelineVisibility.suppressedEpisodeIDs(from: try context.fetch(FetchDescriptor<UserAssertion>())).isEmpty
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<TimelineEpisode>()).count, 2)
    }

    @MainActor
    func testRecentRebuildDoesNotCreateTransitionFromStayPendingDeletion() throws {
        let context = try makeContext()
        let staleStay = TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: baseTime.addingTimeInterval(60 * 60),
            title: "消える滞在",
            confidence: .low,
            sourceVisitID: UUID(),
            sourceVersion: TimelineEngine.sourceVersion,
            timeZoneIdentifier: zone
        )
        context.insert(staleStay)
        let currentVisit = insertVisit(
            arrival: baseTime.addingTimeInterval(2 * 60 * 60),
            departure: baseTime.addingTimeInterval(3 * 60 * 60),
            observedAt: baseTime.addingTimeInterval(3 * 60 * 60),
            in: context
        )
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(
            in: context,
            now: baseTime.addingTimeInterval(4 * 60 * 60),
            trackingSensitivity: .lowPower
        )

        let episodes = try context.fetch(FetchDescriptor<TimelineEpisode>())
        XCTAssertFalse(episodes.contains { $0.id == staleStay.id })
        XCTAssertEqual(episodes.filter { $0.kind == .stay }.map(\.sourceVisitID), [currentVisit.id])
        XCTAssertTrue(episodes.allSatisfy { $0.kind == .stay })
    }

    @MainActor
    func testMetadataOnlyStayEditPreservesExistingTransitionRows() throws {
        let context = try makeContext()
        let departure = baseTime.addingTimeInterval(60 * 60)
        let nextArrival = baseTime.addingTimeInterval(2 * 60 * 60)
        let first = TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: departure,
            title: "変更前",
            confidence: .medium,
            sourceVersion: TimelineEngine.sourceVersion,
            timeZoneIdentifier: zone
        )
        let transition = TimelineEpisode(
            kind: .move,
            startDate: departure,
            endDate: nextArrival,
            title: "移動",
            confidence: .medium,
            sourceVersion: TimelineEngine.sourceVersion,
            timeZoneIdentifier: zone
        )
        let second = TimelineEpisode(
            kind: .stay,
            startDate: nextArrival,
            endDate: nextArrival.addingTimeInterval(60 * 60),
            title: "次の滞在",
            confidence: .medium,
            sourceVersion: TimelineEngine.sourceVersion,
            timeZoneIdentifier: zone
        )
        context.insert(first)
        context.insert(transition)
        context.insert(second)
        try context.save()

        try TimelineEditingService().saveStay(
            first,
            title: "変更後",
            startDate: first.startDate,
            endDate: first.endDate,
            confirmLocation: false,
            in: context
        )

        let transitions = try context.fetch(FetchDescriptor<TimelineEpisode>())
            .filter { $0.kind != .stay }
        XCTAssertEqual(transitions.map(\.id), [transition.id])
        XCTAssertEqual(transitions.first?.startDate, departure)
        XCTAssertEqual(transitions.first?.endDate, nextArrival)
        XCTAssertEqual(first.title, "変更後")
    }

    @MainActor
    func testSuppressingMiddleStayKeepsTransitionsAndUndoRestoresVisibility() throws {
        let context = try makeContext()
        let firstDeparture = baseTime.addingTimeInterval(60 * 60)
        let middleArrival = baseTime.addingTimeInterval(2 * 60 * 60)
        let middleDeparture = baseTime.addingTimeInterval(3 * 60 * 60)
        let thirdArrival = baseTime.addingTimeInterval(4 * 60 * 60)
        let thirdDeparture = baseTime.addingTimeInterval(5 * 60 * 60)

        let firstVisit = insertVisit(
            arrival: baseTime,
            departure: firstDeparture,
            observedAt: firstDeparture,
            in: context
        )
        let middleVisit = insertVisit(
            arrival: middleArrival,
            departure: middleDeparture,
            observedAt: middleDeparture,
            latitude: 34.67,
            longitude: 133.93,
            in: context
        )
        let thirdVisit = insertVisit(
            arrival: thirdArrival,
            departure: thirdDeparture,
            observedAt: thirdDeparture,
            latitude: 34.68,
            longitude: 133.94,
            in: context
        )
        let firstMovement = locationEvidence(
            at: firstDeparture.addingTimeInterval(30 * 60),
            latitude: 34.665,
            longitude: 133.925,
            speed: 8,
            course: 45,
            source: .significantChange
        )
        let secondMovement = locationEvidence(
            at: middleDeparture.addingTimeInterval(30 * 60),
            latitude: 34.675,
            longitude: 133.935,
            speed: 8,
            course: 45,
            source: .significantChange
        )
        context.insert(firstMovement)
        context.insert(secondMovement)
        try context.save()

        let engine = TimelineEngine()
        try engine.rebuildRecentTimeline(
            in: context,
            now: thirdDeparture,
            trackingSensitivity: .lowPower
        )

        let firstStay = try stay(for: firstVisit.id, in: context)
        let middleStay = try stay(for: middleVisit.id, in: context)
        let thirdStay = try stay(for: thirdVisit.id, in: context)
        let transitionsBeforeSuppress = try context.fetch(FetchDescriptor<TimelineEpisode>())
            .filter { $0.kind != .stay }
            .sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(transitionsBeforeSuppress.map(\.kind), [.move, .move])
        XCTAssertEqual(transitionsBeforeSuppress.map(\.startDate), [firstDeparture, middleDeparture])
        XCTAssertEqual(transitionsBeforeSuppress.compactMap(\.endDate), [middleArrival, thirdArrival])
        let transitionIDsBeforeSuppress = transitionsBeforeSuppress.map(\.id)
        let rawEvidenceIDsBeforeSuppress = Set(
            try context.fetch(FetchDescriptor<LocationEvidence>()).map(\.id)
        )

        let editor = TimelineEditingService()
        try editor.setSuppressed(episodeID: middleStay.id, suppressed: true, in: context)

        let assertionsAfterSuppress = try context.fetch(FetchDescriptor<UserAssertion>())
        let suppressedIDs = TimelineVisibility.suppressedEpisodeIDs(from: assertionsAfterSuppress)
        XCTAssertEqual(suppressedIDs, Set([middleStay.id]))
        XCTAssertTrue(assertionsAfterSuppress.contains {
            $0.episodeID == middleStay.id && $0.type == .suppress && $0.isActive
        })

        let episodesImmediatelyAfterSuppress = try context.fetch(FetchDescriptor<TimelineEpisode>())
        let visibleImmediatelyAfterSuppress = episodesImmediatelyAfterSuppress.filter { !suppressedIDs.contains($0.id) }
        XCTAssertFalse(visibleImmediatelyAfterSuppress.contains { $0.id == middleStay.id })
        XCTAssertTrue(visibleImmediatelyAfterSuppress.contains { $0.id == firstStay.id })
        XCTAssertTrue(visibleImmediatelyAfterSuppress.contains { $0.id == thirdStay.id })

        let transitionsImmediatelyAfterSuppress = episodesImmediatelyAfterSuppress
            .filter { $0.kind != .stay }
            .sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(transitionsImmediatelyAfterSuppress.map(\.id), transitionIDsBeforeSuppress)
        XCTAssertEqual(transitionsImmediatelyAfterSuppress.map(\.startDate), [firstDeparture, middleDeparture])
        XCTAssertEqual(transitionsImmediatelyAfterSuppress.compactMap(\.endDate), [middleArrival, thirdArrival])
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<LocationEvidence>()).map(\.id)),
            rawEvidenceIDsBeforeSuppress
        )

        // A later automatic rebuild may regenerate transition rows, but the
        // hidden stay must continue to define both canonical boundaries.
        try engine.rebuildRecentTimeline(
            in: context,
            now: thirdDeparture,
            trackingSensitivity: .lowPower
        )
        let transitionsAfterRebuild = try context.fetch(FetchDescriptor<TimelineEpisode>())
            .filter { $0.kind != .stay }
            .sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(transitionsAfterRebuild.map(\.kind), [.move, .move])
        XCTAssertEqual(transitionsAfterRebuild.map(\.startDate), [firstDeparture, middleDeparture])
        XCTAssertEqual(transitionsAfterRebuild.compactMap(\.endDate), [middleArrival, thirdArrival])

        try editor.setSuppressed(episodeID: middleStay.id, suppressed: false, in: context)
        let assertionsAfterUndo = try context.fetch(FetchDescriptor<UserAssertion>())
        XCTAssertFalse(TimelineVisibility.suppressedEpisodeIDs(from: assertionsAfterUndo).contains(middleStay.id))
        XCTAssertTrue(try context.fetch(FetchDescriptor<TimelineEpisode>()).contains { $0.id == middleStay.id })

        let transitionsAfterUndo = try context.fetch(FetchDescriptor<TimelineEpisode>())
            .filter { $0.kind != .stay }
            .sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(transitionsAfterUndo.map(\.kind), [.move, .move])
        XCTAssertEqual(transitionsAfterUndo.map(\.startDate), [firstDeparture, middleDeparture])
        XCTAssertEqual(transitionsAfterUndo.compactMap(\.endDate), [middleArrival, thirdArrival])
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<LocationEvidence>()).map(\.id)),
            rawEvidenceIDsBeforeSuppress
        )
    }

    @MainActor
    func testEmptyJournalSaveDeletesExistingEntry() throws {
        let context = try makeContext()
        let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        let day = DayInterval(containing: baseTime, timeZone: timeZone)
        let journal = JournalEntry(
            dayAnchor: day.start,
            body: "残っていた日記",
            timeZoneIdentifier: zone
        )
        context.insert(journal)
        try context.save()

        let result = try JournalEditingService().save(
            day: day,
            body: "   \n ",
            existingJournal: journal,
            in: context,
            now: baseTime
        )

        XCTAssertNil(result)
        XCTAssertTrue(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
    }

    @MainActor
    func testJournalSaveTrimsAndCreatesEntry() throws {
        let context = try makeContext()
        let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        let day = DayInterval(containing: baseTime, timeZone: timeZone)

        let result = try JournalEditingService().save(
            day: day,
            body: "  今日はよかった  \n",
            existingJournal: nil,
            in: context,
            now: baseTime
        )

        let journal = try XCTUnwrap(result)
        XCTAssertEqual(journal.body, "今日はよかった")
        XCTAssertEqual(journal.dayAnchor, day.start)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JournalEntry>()).count, 1)
    }

    @MainActor
    func testTransitionWithoutSamplesBecomesGap() throws {
        let context = try makeContext()
        let firstDeparture = baseTime.addingTimeInterval(60 * 60)
        let secondArrival = firstDeparture.addingTimeInterval(30 * 60)
        insertTransitionVisits(firstDeparture: firstDeparture, secondArrival: secondArrival, in: context)
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: secondArrival.addingTimeInterval(60 * 60))

        let episodes = try context.fetch(FetchDescriptor<TimelineEpisode>())
        XCTAssertEqual(episodes.filter { $0.kind == .gap }.count, 1)
        XCTAssertEqual(episodes.filter { $0.kind == .move }.count, 0)
    }

    @MainActor
    func testTransitionWithLocationSampleBecomesMove() throws {
        let context = try makeContext()
        let firstDeparture = baseTime.addingTimeInterval(60 * 60)
        let secondArrival = firstDeparture.addingTimeInterval(30 * 60)
        insertTransitionVisits(firstDeparture: firstDeparture, secondArrival: secondArrival, in: context)
        context.insert(locationEvidence(
            at: firstDeparture,
            latitude: 34.67,
            longitude: 133.93,
            speed: 4,
            course: 90,
            source: .significantChange
        ))
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: secondArrival.addingTimeInterval(60 * 60))

        let episodes = try context.fetch(FetchDescriptor<TimelineEpisode>())
        XCTAssertEqual(episodes.filter { $0.kind == .move }.count, 1)
        XCTAssertEqual(episodes.filter { $0.kind == .gap }.count, 0)
    }

    @MainActor
    func testTransitionUsesStayBoundariesWhenFirstLocationSampleIsLate() throws {
        let context = try makeContext()
        let firstDeparture = baseTime.addingTimeInterval(60 * 60)
        let firstMovingSample = firstDeparture.addingTimeInterval(2 * 60 * 60)
        let secondArrival = firstDeparture.addingTimeInterval(2 * 60 * 60 + 38 * 60)
        insertTransitionVisits(firstDeparture: firstDeparture, secondArrival: secondArrival, in: context)
        context.insert(locationEvidence(
            at: firstMovingSample,
            latitude: 34.67,
            longitude: 133.93,
            speed: 12,
            course: 90,
            source: .standardLocation
        ))
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: secondArrival.addingTimeInterval(60 * 60))

        let transitions = try context.fetch(FetchDescriptor<TimelineEpisode>())
            .filter { $0.kind != .stay }
            .sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(transitions.map(\.kind), [.move])
        XCTAssertEqual(transitions[0].startDate, firstDeparture)
        XCTAssertEqual(transitions[0].endDate, secondArrival)
        XCTAssertEqual(
            TimelineFormatting.duration(from: transitions[0].startDate, to: transitions[0].endDate),
            "約2時間38分"
        )
    }

    @MainActor
    func testDayRouteProjectionKeepsMovingSamplesAsRouteVertices() throws {
        let firstStay = timelineStay(
            start: baseTime,
            end: baseTime.addingTimeInterval(60 * 60),
            latitude: 34.660,
            longitude: 133.920
        )
        let secondStay = timelineStay(
            start: baseTime.addingTimeInterval(90 * 60),
            end: baseTime.addingTimeInterval(120 * 60),
            latitude: 34.700,
            longitude: 133.960
        )
        let movingSample = locationEvidence(
            at: baseTime.addingTimeInterval(75 * 60),
            latitude: 34.680,
            longitude: 133.940,
            speed: 12,
            source: .standardLocation
        )

        let points = DayRouteProjection.points(
            episodes: [secondStay, firstStay],
            locationEvidence: [movingSample]
        )

        XCTAssertEqual(points.map(\.kind), [.stay, .movementSample, .stay])
        XCTAssertEqual(points.map(\.latitude), [34.660, 34.680, 34.700])
        XCTAssertEqual(points.map(\.longitude), [133.920, 133.940, 133.960])
    }

    @MainActor
    func testDayRouteProjectionSnapshotInputsMatchModelProjection() throws {
        let firstStay = timelineStay(
            start: baseTime,
            end: baseTime.addingTimeInterval(60 * 60),
            latitude: 34.660,
            longitude: 133.920
        )
        let secondStay = timelineStay(
            start: baseTime.addingTimeInterval(90 * 60),
            end: baseTime.addingTimeInterval(120 * 60),
            latitude: 34.700,
            longitude: 133.960
        )
        let movingSample = locationEvidence(
            at: baseTime.addingTimeInterval(75 * 60),
            latitude: 34.680,
            longitude: 133.940,
            speed: 12,
            source: .standardLocation
        )

        let modelPoints = DayRouteProjection.points(
            episodes: [secondStay, firstStay],
            locationEvidence: [movingSample],
            options: .preview
        )
        let snapshotPoints = DayRouteProjection.points(
            stays: [secondStay, firstStay].compactMap { DayRouteStayInput(episode: $0) },
            locationEvidence: [DayRouteLocationInput(evidence: movingSample)],
            options: .preview
        )

        XCTAssertEqual(snapshotPoints.map(\.id), modelPoints.map(\.id))
        XCTAssertEqual(snapshotPoints.map(\.kind), modelPoints.map(\.kind))
        XCTAssertEqual(snapshotPoints.map(\.timestamp), modelPoints.map(\.timestamp))
        XCTAssertEqual(snapshotPoints.map(\.latitude), modelPoints.map(\.latitude))
        XCTAssertEqual(snapshotPoints.map(\.longitude), modelPoints.map(\.longitude))
    }

    @MainActor
    func testDayRouteProjectionExcludesSamplesAtTransitionBoundaries() throws {
        let departure = baseTime.addingTimeInterval(60 * 60)
        let arrival = baseTime.addingTimeInterval(90 * 60)
        let firstStay = timelineStay(
            start: baseTime,
            end: departure,
            latitude: 34.660,
            longitude: 133.920
        )
        let secondStay = timelineStay(
            start: arrival,
            end: arrival.addingTimeInterval(30 * 60),
            latitude: 34.720,
            longitude: 133.980
        )
        let atDeparture = locationEvidence(
            at: departure,
            latitude: 34.670,
            longitude: 133.930,
            speed: 8,
            source: .standardLocation
        )
        let inside = locationEvidence(
            at: departure.addingTimeInterval(15 * 60),
            latitude: 34.690,
            longitude: 133.950,
            speed: 8,
            source: .standardLocation
        )
        let atArrival = locationEvidence(
            at: arrival,
            latitude: 34.710,
            longitude: 133.970,
            speed: 8,
            source: .standardLocation
        )

        let points = DayRouteProjection.points(
            episodes: [firstStay, secondStay],
            locationEvidence: [atArrival, inside, atDeparture],
            options: .preview
        )

        XCTAssertEqual(points.map(\.kind), [.stay, .movementSample, .stay])
        XCTAssertEqual(points[1].id, "sample-\(inside.id.uuidString)")
    }

    @MainActor
    func testDayRouteProjectionLargeSnapshotBoundsSamplesPerSegment() {
        let segmentCount = 12
        let segmentDuration: TimeInterval = 2 * 60 * 60
        let stayDuration: TimeInterval = 15 * 60
        let stays = (0...segmentCount).map { index in
            let start = baseTime.addingTimeInterval(Double(index) * segmentDuration)
            return DayRouteStayInput(
                id: UUID(),
                startDate: start,
                endDate: start.addingTimeInterval(stayDuration),
                latitude: 34.60 + Double(index) * 0.02,
                longitude: 133.80 + Double(index) * 0.02
            )
        }
        var samples: [DayRouteLocationInput] = []
        samples.reserveCapacity(segmentCount * 1_000)
        for segment in 0..<segmentCount {
            let start = stays[segment].endDate!
            let end = stays[segment + 1].startDate
            for sampleIndex in 1...1_000 {
                let fraction = Double(sampleIndex) / 1_001
                let timestamp = start.addingTimeInterval(end.timeIntervalSince(start) * fraction)
                samples.append(DayRouteLocationInput(
                    id: UUID(),
                    timestamp: timestamp,
                    latitude: stays[segment].latitude
                        + (stays[segment + 1].latitude - stays[segment].latitude) * fraction,
                    longitude: stays[segment].longitude
                        + (stays[segment + 1].longitude - stays[segment].longitude) * fraction,
                    horizontalAccuracy: 20,
                    source: .standardLocation
                ))
            }
        }

        let points = DayRouteProjection.points(
            stays: stays,
            locationEvidence: Array(samples.reversed()),
            options: .preview
        )
        let movementCount = points.count { $0.kind == .movementSample }

        XCTAssertLessThanOrEqual(
            movementCount,
            segmentCount * DayRouteProjection.Options.preview.maximumSamplesPerSegment
        )
        XCTAssertEqual(points.count { $0.kind == .stay }, stays.count)
    }

    @MainActor
    func testDayRouteProjectionDoesNotTreatStaySamplesAsRouteVertices() throws {
        let firstStay = timelineStay(
            start: baseTime,
            end: baseTime.addingTimeInterval(60 * 60),
            latitude: 34.660,
            longitude: 133.920
        )
        let secondStay = timelineStay(
            start: baseTime.addingTimeInterval(90 * 60),
            end: baseTime.addingTimeInterval(120 * 60),
            latitude: 34.700,
            longitude: 133.960
        )
        let staySample = locationEvidence(
            at: baseTime.addingTimeInterval(30 * 60),
            latitude: 34.661,
            longitude: 133.921
        )

        let points = DayRouteProjection.points(
            episodes: [firstStay, secondStay],
            locationEvidence: [staySample]
        )

        XCTAssertEqual(points.map(\.kind), [.stay, .stay])
    }

    @MainActor
    func testDayRouteProjectionFiltersLowQualityMovingSamples() throws {
        let firstStay = timelineStay(
            start: baseTime,
            end: baseTime.addingTimeInterval(60 * 60),
            latitude: 34.660,
            longitude: 133.920
        )
        let secondStay = timelineStay(
            start: baseTime.addingTimeInterval(90 * 60),
            end: baseTime.addingTimeInterval(120 * 60),
            latitude: 34.700,
            longitude: 133.960
        )
        let inaccurateSample = LocationEvidence(
            timestamp: baseTime.addingTimeInterval(75 * 60),
            latitude: 34.680,
            longitude: 133.940,
            horizontalAccuracy: 1_500,
            speed: 12,
            course: 90,
            source: .standardLocation,
            timeZoneIdentifier: zone
        )

        let points = DayRouteProjection.points(
            episodes: [firstStay, secondStay],
            locationEvidence: [inaccurateSample]
        )

        XCTAssertEqual(points.map(\.kind), [.stay, .stay])
    }

    @MainActor
    func testDayRouteProjectionThinsClusteredMovingSamples() throws {
        let firstStay = timelineStay(
            start: baseTime,
            end: baseTime.addingTimeInterval(60 * 60),
            latitude: 34.660,
            longitude: 133.920
        )
        let secondStay = timelineStay(
            start: baseTime.addingTimeInterval(120 * 60),
            end: baseTime.addingTimeInterval(150 * 60),
            latitude: 34.700,
            longitude: 133.960
        )
        let clusteredSample = locationEvidence(
            at: baseTime.addingTimeInterval(75 * 60),
            latitude: 34.661,
            longitude: 133.921,
            speed: 8,
            source: .standardLocation
        )
        let distantSample = locationEvidence(
            at: baseTime.addingTimeInterval(90 * 60),
            latitude: 34.680,
            longitude: 133.940,
            speed: 12,
            source: .standardLocation
        )

        let points = DayRouteProjection.points(
            episodes: [firstStay, secondStay],
            locationEvidence: [clusteredSample, distantSample],
            options: .preview
        )

        XCTAssertEqual(points.map(\.kind), [.stay, .movementSample, .stay])
        XCTAssertEqual(points.map(\.latitude), [34.660, 34.680, 34.700])
    }

    @MainActor
    func testPreviewRouteKeepsCurrentLocationConnection() throws {
        let firstStay = timelineStay(
            start: baseTime,
            end: baseTime.addingTimeInterval(60 * 60),
            latitude: 34.660,
            longitude: 133.920
        )
        let currentLocation = CurrentLocationContext(
            startDate: baseTime.addingTimeInterval(90 * 60),
            lastEvidenceAt: baseTime.addingTimeInterval(91 * 60),
            latitude: 34.700,
            longitude: 133.960,
            horizontalAccuracy: 20,
            timeZoneIdentifier: zone
        )

        let points = DayRouteProjection.points(
            episodes: [firstStay],
            locationEvidence: [],
            currentLocation: currentLocation,
            options: .preview
        )

        XCTAssertEqual(points.map(\.kind), [.stay, .currentLocation])
    }

    @MainActor
    func testDetailRouteCanAppendCurrentLocation() throws {
        let firstStay = timelineStay(
            start: baseTime,
            end: baseTime.addingTimeInterval(60 * 60),
            latitude: 34.660,
            longitude: 133.920
        )
        let currentLocation = CurrentLocationContext(
            startDate: baseTime.addingTimeInterval(90 * 60),
            lastEvidenceAt: baseTime.addingTimeInterval(91 * 60),
            latitude: 34.700,
            longitude: 133.960,
            horizontalAccuracy: 20,
            timeZoneIdentifier: zone
        )

        let points = DayRouteProjection.points(
            episodes: [firstStay],
            locationEvidence: [],
            currentLocation: currentLocation,
            options: .detail
        )

        XCTAssertEqual(points.map(\.kind), [.stay, .currentLocation])
    }

    @MainActor
    func testBalancedTrackingInfersTwentyMinuteStopFromLocationCluster() throws {
        let context = try makeContext()
        context.insert(locationEvidence(at: baseTime, latitude: 34.660_00, longitude: 133.920_00, speed: 0.4))
        context.insert(locationEvidence(
            at: baseTime.addingTimeInterval(10 * 60),
            latitude: 34.660_12,
            longitude: 133.920_10,
            speed: 0.2
        ))
        context.insert(locationEvidence(
            at: baseTime.addingTimeInterval(20 * 60),
            latitude: 34.660_05,
            longitude: 133.920_08,
            speed: 0.1
        ))
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(
            in: context,
            now: baseTime.addingTimeInterval(60 * 60),
            trackingSensitivity: .balanced
        )

        let inferredVisit = try XCTUnwrap(try context.fetch(FetchDescriptor<VisitEvidence>())
            .first { $0.source == .inferredStop })
        let stay = try stay(for: inferredVisit.id, in: context)
        XCTAssertEqual(stay.title, "推定した停車")
        XCTAssertEqual(stay.confidence, .low)
        XCTAssertEqual(stay.startDate, baseTime)
        XCTAssertEqual(stay.endDate, baseTime.addingTimeInterval(20 * 60))
    }

    @MainActor
    func testInferredStopDoesNotDuplicateRealVisit() throws {
        let context = try makeContext()
        insertVisit(
            arrival: baseTime,
            departure: baseTime.addingTimeInterval(30 * 60),
            observedAt: baseTime.addingTimeInterval(30 * 60),
            in: context
        )
        context.insert(locationEvidence(at: baseTime, latitude: 34.660_00, longitude: 133.920_00, speed: 0))
        context.insert(locationEvidence(
            at: baseTime.addingTimeInterval(10 * 60),
            latitude: 34.660_08,
            longitude: 133.920_04,
            speed: 0
        ))
        context.insert(locationEvidence(
            at: baseTime.addingTimeInterval(20 * 60),
            latitude: 34.660_12,
            longitude: 133.920_05,
            speed: 0
        ))
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(
            in: context,
            now: baseTime.addingTimeInterval(60 * 60),
            trackingSensitivity: .balanced
        )

        let visits = try context.fetch(FetchDescriptor<VisitEvidence>())
        let stays = try context.fetch(FetchDescriptor<TimelineEpisode>()).filter { $0.kind == .stay }
        XCTAssertEqual(visits.filter { $0.source == .inferredStop }.count, 0)
        XCTAssertEqual(stays.count, 1)
        XCTAssertEqual(stays.first?.title, "未設定の場所")
    }

    @MainActor
    func testFreshNearbyEvidenceProjectsCurrentLocationSinceClusterStart() throws {
        let now = baseTime.addingTimeInterval(10 * 60)
        let evidence = [
            locationEvidence(at: baseTime, latitude: 34.660_00, longitude: 133.920_00),
            locationEvidence(
                at: baseTime.addingTimeInterval(8 * 60),
                latitude: 34.660_15,
                longitude: 133.920_10,
                source: .significantChange
            ),
        ]

        let current = try XCTUnwrap(CurrentLocationProjection.project(
            evidence: evidence,
            now: now,
            dayStart: baseTime.addingTimeInterval(-60 * 60)
        ))

        XCTAssertEqual(current.startDate, baseTime)
        XCTAssertEqual(current.lastEvidenceAt, baseTime.addingTimeInterval(8 * 60))
        XCTAssertEqual(current.latitude, 34.660_15)
    }

    @MainActor
    func testCurrentLocationProjectionDoesNotShowStaleEvidence() {
        let evidence = [locationEvidence(at: baseTime)]

        XCTAssertNil(CurrentLocationProjection.project(
            evidence: evidence,
            now: baseTime.addingTimeInterval(21 * 60),
            dayStart: baseTime.addingTimeInterval(-60 * 60)
        ))
    }

    @MainActor
    func testCurrentLocationProjectionStopsAtPreviousPlace() throws {
        let recent = baseTime.addingTimeInterval(10 * 60)
        let evidence = [
            locationEvidence(at: baseTime, latitude: 34.66, longitude: 133.92),
            locationEvidence(at: recent, latitude: 34.68, longitude: 133.94),
        ]

        let current = try XCTUnwrap(CurrentLocationProjection.project(
            evidence: evidence,
            now: recent.addingTimeInterval(60),
            dayStart: baseTime.addingTimeInterval(-60 * 60)
        ))

        XCTAssertEqual(current.startDate, recent)
    }

    @MainActor
    func testRepositionAssertionSurvivesTimelineRebuild() throws {
        let context = try makeContext()
        let visit = insertVisit(
            arrival: baseTime,
            departure: baseTime.addingTimeInterval(60 * 60),
            observedAt: baseTime,
            in: context
        )
        try context.save()
        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60 * 60))
        let stay = try stay(for: visit.id, in: context)

        let correctedLatitude = 34.670_5
        let correctedLongitude = 133.930_5
        try TimelineEditingService().saveStay(
            stay,
            title: stay.title,
            startDate: stay.startDate,
            endDate: stay.endDate,
            latitude: correctedLatitude,
            longitude: correctedLongitude,
            confirmLocation: false,
            in: context
        )

        var assertions = try context.fetch(FetchDescriptor<UserAssertion>())
        let reposition = try XCTUnwrap(assertions.first { $0.type == .reposition && $0.isActive })
        XCTAssertEqual(reposition.replacementLatitude, correctedLatitude)
        XCTAssertEqual(reposition.replacementLongitude, correctedLongitude)

        visit.latitude = 34.65
        visit.longitude = 133.91
        try context.save()
        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60 * 60))

        XCTAssertEqual(stay.latitude, correctedLatitude)
        XCTAssertEqual(stay.longitude, correctedLongitude)
        assertions = try context.fetch(FetchDescriptor<UserAssertion>())
        XCTAssertEqual(assertions.filter { $0.type == .reposition && $0.isActive }.count, 1)
    }

    @MainActor
    func testMergePlaceSelectionLinksStayToExistingPlace() throws {
        let context = try makeContext()
        let canonicalPlace = PlaceRecord(
            name: "家",
            latitude: 34.670,
            longitude: 133.930,
            radius: 120,
            source: .userConfirmed
        )
        context.insert(canonicalPlace)
        let visit = insertVisit(
            arrival: baseTime,
            departure: baseTime.addingTimeInterval(60 * 60),
            observedAt: baseTime,
            latitude: 34.671,
            longitude: 133.931,
            in: context
        )
        try context.save()
        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime.addingTimeInterval(60 * 60))
        let stay = try stay(for: visit.id, in: context)

        try TimelineEditingService().saveStay(
            stay,
            title: stay.title,
            startDate: stay.startDate,
            endDate: stay.endDate,
            latitude: stay.latitude,
            longitude: stay.longitude,
            confirmLocation: false,
            mergePlaceID: canonicalPlace.id,
            in: context
        )

        XCTAssertEqual(stay.title, "家")
        XCTAssertEqual(stay.placeID, canonicalPlace.id)
        XCTAssertEqual(stay.latitude, canonicalPlace.latitude)
        XCTAssertEqual(stay.longitude, canonicalPlace.longitude)

        let assertions = try context.fetch(FetchDescriptor<UserAssertion>())
        XCTAssertTrue(assertions.contains { $0.type == .rename && $0.isActive && $0.replacementTitle == "家" })
        XCTAssertTrue(assertions.contains { $0.type == .confirm && $0.isActive })
        XCTAssertTrue(assertions.contains { $0.type == .reposition && $0.isActive })
    }

    @MainActor
    private func insertTransitionVisits(
        firstDeparture: Date,
        secondArrival: Date,
        in context: ModelContext
    ) {
        insertVisit(
            arrival: baseTime,
            departure: firstDeparture,
            observedAt: firstDeparture,
            in: context
        )
        insertVisit(
            arrival: secondArrival,
            departure: secondArrival.addingTimeInterval(60 * 60),
            observedAt: secondArrival,
            latitude: 34.68,
            longitude: 133.94,
            in: context
        )
    }

    @MainActor
    @discardableResult
    private func insertVisit(
        arrival: Date?,
        departure: Date?,
        observedAt: Date,
        latitude: Double = 34.66,
        longitude: Double = 133.92,
        accuracy: Double = 30,
        in context: ModelContext
    ) -> VisitEvidence {
        let visit = VisitEvidence(
            arrivalDate: arrival,
            departureDate: departure,
            observedAt: observedAt,
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: accuracy,
            timeZoneIdentifier: zone
        )
        context.insert(visit)
        return visit
    }

    private func locationEvidence(
        at timestamp: Date,
        latitude: Double = 34.66,
        longitude: Double = 133.92,
        speed: Double = 0,
        course: Double = 0,
        source: EvidenceSource = .standardLocation
    ) -> LocationEvidence {
        LocationEvidence(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: 20,
            speed: speed,
            course: course,
            source: source,
            timeZoneIdentifier: zone
        )
    }

    @MainActor
    @discardableResult
    private func insertCanonicalStay(
        title: String,
        start: Date? = nil,
        in context: ModelContext
    ) -> TimelineEpisode {
        let episode = TimelineEpisode(
            kind: .stay,
            startDate: start ?? baseTime,
            endDate: (start ?? baseTime).addingTimeInterval(60 * 60),
            title: title,
            confidence: .high,
            sourceVersion: 6,
            timeZoneIdentifier: zone
        )
        context.insert(episode)
        return episode
    }

    private func timelineStay(
        start: Date,
        end: Date?,
        latitude: Double,
        longitude: Double
    ) -> TimelineEpisode {
        TimelineEpisode(
            kind: .stay,
            startDate: start,
            endDate: end,
            title: "滞在",
            latitude: latitude,
            longitude: longitude,
            confidence: .high,
            sourceVersion: 6,
            timeZoneIdentifier: zone
        )
    }

    @MainActor
    private func stays(in context: ModelContext) throws -> [TimelineEpisode] {
        try context.fetch(FetchDescriptor<TimelineEpisode>()).filter { $0.kind == .stay }
    }

    @MainActor
    private func firstStay(in context: ModelContext) throws -> TimelineEpisode {
        try XCTUnwrap(try stays(in: context).first)
    }

    @MainActor
    private func stay(for visitID: UUID, in context: ModelContext) throws -> TimelineEpisode {
        try XCTUnwrap(try stays(in: context).first { $0.sourceVisitID == visitID })
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            LocationEvidence.self,
            VisitEvidence.self,
            PlaceRecord.self,
            TimelineEpisode.self,
            UserAssertion.self,
            JournalEntry.self,
            MomentNote.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
