import SwiftData
import XCTest
@testable import Daytrace

final class RegressionTests: XCTestCase {
    private let tokyo = "Asia/Tokyo"
    private let baseTime = Date(timeIntervalSince1970: 1_786_500_000)

    func testCalendarDayUsesRecordedTimezoneAndDSTDayHasRealDuration() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let tokyoZone = try XCTUnwrap(TimeZone(identifier: tokyo))

        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-03-09T06:30:00Z")
        )
        XCTAssertEqual(CalendarDay(containing: instant, timeZone: losAngeles), CalendarDayComponents(2026, 3, 8))
        XCTAssertEqual(CalendarDay(containing: instant, timeZone: tokyoZone), CalendarDayComponents(2026, 3, 9))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        let dstDate = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: losAngeles,
            year: 2026,
            month: 3,
            day: 8,
            hour: 12
        )))
        let interval = DayInterval(containing: dstDate, timeZone: losAngeles)
        XCTAssertEqual(interval.end.timeIntervalSince(interval.start), 23 * 60 * 60, accuracy: 1)
    }

    @MainActor
    func testDelayedVisitRetentionUsesVisitEvidenceTime() throws {
        let context = try makeContext()
        let now = baseTime
        let oldDeparture = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let recentObservation = now.addingTimeInterval(-60 * 60)

        context.insert(VisitEvidence(
            arrivalDate: oldDeparture.addingTimeInterval(-60 * 60),
            departureDate: oldDeparture,
            observedAt: recentObservation,
            latitude: 34.66,
            longitude: 133.92,
            horizontalAccuracy: 30,
            timeZoneIdentifier: tokyo
        ))
        try context.save()

        try RawEvidenceRetentionService().prune(
            in: context,
            retentionDays: 30,
            now: now
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<VisitEvidence>()).isEmpty)
    }

    @MainActor
    func testVisitRetentionPrefersRecentDepartureOverOldArrival() throws {
        let context = try makeContext()
        let now = baseTime

        context.insert(VisitEvidence(
            arrivalDate: now.addingTimeInterval(-40 * 24 * 60 * 60),
            departureDate: now.addingTimeInterval(-2 * 24 * 60 * 60),
            observedAt: now.addingTimeInterval(-60 * 60),
            latitude: 34.66,
            longitude: 133.92,
            horizontalAccuracy: 30,
            timeZoneIdentifier: tokyo
        ))
        try context.save()

        try RawEvidenceRetentionService().prune(
            in: context,
            retentionDays: 30,
            now: now
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<VisitEvidence>()).count, 1)
    }

    @MainActor
    func testNearbySameNameConfirmationReusesPlace() throws {
        let context = try makeContext()
        let existing = PlaceRecord(
            name: "学校",
            latitude: 34.6600,
            longitude: 133.9200,
            radius: 100,
            source: .userConfirmed
        )
        let stay = TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: baseTime.addingTimeInterval(60 * 60),
            title: "学校",
            latitude: 34.6605,
            longitude: 133.9205,
            confidence: .medium,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        context.insert(existing)
        context.insert(stay)
        try context.save()

        try TimelineEditingService().saveStay(
            stay,
            title: "学校",
            startDate: stay.startDate,
            endDate: stay.endDate,
            confirmLocation: true,
            in: context
        )

        let places = try context.fetch(FetchDescriptor<PlaceRecord>())
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(stay.placeID, existing.id)
        XCTAssertEqual(existing.source, .userConfirmed)
    }

    @MainActor
    func testDistantSameNameConfirmationCreatesSeparatePlace() throws {
        let context = try makeContext()
        let existing = PlaceRecord(
            name: "セブンイレブン",
            latitude: 34.6600,
            longitude: 133.9200,
            radius: 100,
            source: .userConfirmed
        )
        let stay = TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: baseTime.addingTimeInterval(30 * 60),
            title: "セブンイレブン",
            latitude: 34.7000,
            longitude: 133.9600,
            confidence: .medium,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        context.insert(existing)
        context.insert(stay)
        try context.save()

        try TimelineEditingService().saveStay(
            stay,
            title: "セブンイレブン",
            startDate: stay.startDate,
            endDate: stay.endDate,
            confirmLocation: true,
            in: context
        )

        let places = try context.fetch(FetchDescriptor<PlaceRecord>())
        XCTAssertEqual(places.count, 2)
        XCTAssertNotEqual(stay.placeID, existing.id)
    }

    @MainActor
    func testJournalSaveReconcilesDuplicateCalendarDay() throws {
        let context = try makeContext()
        let zone = try XCTUnwrap(TimeZone(identifier: tokyo))
        let day = DayInterval(containing: baseTime, timeZone: zone)

        let first = JournalEntry(
            dayAnchor: day.start,
            body: "first",
            createdAt: baseTime,
            updatedAt: baseTime,
            timeZoneIdentifier: tokyo
        )
        let second = JournalEntry(
            dayAnchor: day.start.addingTimeInterval(60 * 60),
            body: "second",
            createdAt: baseTime.addingTimeInterval(10),
            updatedAt: baseTime.addingTimeInterval(10),
            timeZoneIdentifier: tokyo
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let result = try JournalEditingService().save(
            day: day,
            body: "updated",
            existingJournal: second,
            in: context,
            now: baseTime.addingTimeInterval(20)
        )

        let journals = try context.fetch(FetchDescriptor<JournalEntry>())
        XCTAssertEqual(journals.count, 1)
        XCTAssertEqual(result?.id, second.id)
        XCTAssertEqual(journals.first?.body, "updated")
    }

    @MainActor
    func testMomentNoteOnlyHistoricalJournalUsesNoteTimezone() throws {
        let context = try makeContext()
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let tokyoZone = try XCTUnwrap(TimeZone(identifier: tokyo))
        let targetDay = CalendarDayComponents(2026, 8, 12)
        let noteTimestamp = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T01:00:00Z")
        )

        XCTAssertEqual(
            CalendarDay(containing: noteTimestamp, timeZone: losAngeles),
            targetDay
        )
        XCTAssertNotEqual(
            CalendarDay(containing: noteTimestamp, timeZone: tokyoZone),
            targetDay
        )

        context.insert(MomentNote(
            timestamp: noteTimestamp,
            body: "旅先のメモ",
            timeZoneIdentifier: losAngeles.identifier
        ))
        try context.save()

        let fallbackDate = try XCTUnwrap(targetDay.date(in: tokyoZone))
        let fallbackDay = DayInterval(containing: fallbackDate, timeZone: tokyoZone)
        let journal = try XCTUnwrap(JournalEditingService().save(
            day: fallbackDay,
            body: "帰宅後に書いた日記",
            existingJournal: nil,
            in: context,
            now: noteTimestamp.addingTimeInterval(24 * 60 * 60)
        ))

        XCTAssertEqual(journal.timeZoneIdentifier, losAngeles.identifier)
        XCTAssertEqual(TimelineDayProjection.day(for: journal), targetDay)
        XCTAssertEqual(
            journal.dayAnchor,
            try XCTUnwrap(targetDay.date(in: losAngeles)),
            accuracy: 0.001
        )
    }

    @MainActor
    func testLocationHistoryResetPreservesJournalAndMomentNote() throws {
        let context = try makeContext()
        let resetTime = baseTime.addingTimeInterval(2 * 60 * 60)
        UserDefaults.standard.removeObject(forKey: "locationHistoryResetCutoff")
        defer {
            UserDefaults.standard.removeObject(forKey: "locationHistoryResetCutoff")
        }

        let place = PlaceRecord(
            name: "学校",
            latitude: 34.66,
            longitude: 133.92,
            source: .userConfirmed
        )
        let episode = TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: baseTime.addingTimeInterval(60 * 60),
            title: "学校",
            latitude: 34.66,
            longitude: 133.92,
            confidence: .high,
            placeID: place.id,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )

        context.insert(LocationEvidence(
            timestamp: baseTime,
            latitude: 34.66,
            longitude: 133.92,
            horizontalAccuracy: 20,
            speed: 0,
            course: 0,
            source: .standardLocation,
            timeZoneIdentifier: tokyo
        ))
        context.insert(VisitEvidence(
            arrivalDate: baseTime,
            departureDate: baseTime.addingTimeInterval(60 * 60),
            observedAt: baseTime.addingTimeInterval(60 * 60),
            latitude: 34.66,
            longitude: 133.92,
            horizontalAccuracy: 30,
            timeZoneIdentifier: tokyo
        ))
        context.insert(place)
        context.insert(episode)
        context.insert(UserAssertion(episodeID: episode.id, type: .confirm))
        context.insert(JournalEntry(
            dayAnchor: baseTime,
            body: "残す日記",
            timeZoneIdentifier: tokyo
        ))
        context.insert(MomentNote(
            timestamp: baseTime,
            body: "残すメモ",
            timeZoneIdentifier: tokyo
        ))
        try context.save()

        let recorder = LocationRecorder.shared
        recorder.attach(context: context)
        try recorder.deleteLocationHistoryKeepingJournal(now: resetTime)

        XCTAssertTrue(try context.fetch(FetchDescriptor<LocationEvidence>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<VisitEvidence>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlaceRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TimelineEpisode>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<UserAssertion>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JournalEntry>()).map(\.body), ["残す日記"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<MomentNote>()).map(\.body), ["残すメモ"])

        let storedCutoff = Date(
            timeIntervalSinceReferenceDate: UserDefaults.standard.double(forKey: "locationHistoryResetCutoff")
        )
        XCTAssertEqual(storedCutoff.timeIntervalSinceReferenceDate, resetTime.timeIntervalSinceReferenceDate, accuracy: 0.001)
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

    private func CalendarDayComponents(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return CalendarDay(containing: date, timeZone: calendar.timeZone)
    }
}
