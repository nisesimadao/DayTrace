import Foundation
import SwiftData
import XCTest
@testable import Daytrace

final class RegressionTests: XCTestCase {
    private let tokyo = "Asia/Tokyo"
    private let baseTime = Date(timeIntervalSince1970: 1_786_500_000)

#if DEBUG
    @MainActor
    func testDebugDemoDataIsIdempotentAndRemovalPreservesUserData() throws {
        let context = try makeContext()
        let userJournal = JournalEntry(
            dayAnchor: baseTime,
            body: "ユーザーの日記",
            timeZoneIdentifier: tokyo
        )
        let userPlace = PlaceRecord(
            name: "ユーザーの場所",
            latitude: 34.66,
            longitude: 133.92
        )
        let userAssertion = UserAssertion(episodeID: UUID(), type: .rename)
        context.insert(userJournal)
        context.insert(userPlace)
        context.insert(userAssertion)
        try context.save()

        let service = DebugDemoDataService()
        try service.install(in: context, now: baseTime)
        try service.install(in: context, now: baseTime)

        XCTAssertEqual(try context.fetch(FetchDescriptor<JournalEntry>()).count, 6)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlaceRecord>()).count, 4)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TimelineEpisode>()).count, 8)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MomentNote>()).count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserAssertion>()).count, 9)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocationEvidence>()).count, 2)

        try TimelineEngine().rebuildRecentTimeline(in: context, now: baseTime)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TimelineEpisode>()).count, 8)

        try service.remove(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<JournalEntry>()).map(\.id), [userJournal.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlaceRecord>()).map(\.id), [userPlace.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<TimelineEpisode>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MomentNote>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserAssertion>()).map(\.id), [userAssertion.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<LocationEvidence>()).isEmpty)
    }
#endif

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

    func testResetCutoffRejectsOldLocationSamples() {
        let cutoff = baseTime

        XCTAssertTrue(LocationHistoryCutoffPolicy.acceptsLocation(
            timestamp: cutoff.addingTimeInterval(1),
            cutoff: cutoff
        ))
        XCTAssertTrue(LocationHistoryCutoffPolicy.acceptsLocation(
            timestamp: cutoff,
            cutoff: cutoff
        ))
        XCTAssertFalse(LocationHistoryCutoffPolicy.acceptsLocation(
            timestamp: cutoff.addingTimeInterval(-1),
            cutoff: cutoff
        ))
        XCTAssertTrue(LocationHistoryCutoffPolicy.acceptsLocation(
            timestamp: cutoff.addingTimeInterval(-10_000),
            cutoff: nil
        ))
    }

    func testResetCutoffDropsEndedVisitAndClampsSpanningVisit() throws {
        let cutoff = baseTime

        XCTAssertNil(LocationHistoryCutoffPolicy.adjustedVisit(
            arrival: cutoff.addingTimeInterval(-7_200),
            departure: cutoff.addingTimeInterval(-1),
            cutoff: cutoff
        ))

        let spanning = try XCTUnwrap(LocationHistoryCutoffPolicy.adjustedVisit(
            arrival: cutoff.addingTimeInterval(-3_600),
            departure: cutoff.addingTimeInterval(3_600),
            cutoff: cutoff
        ))
        XCTAssertEqual(spanning.arrival, cutoff)
        XCTAssertEqual(spanning.departure, cutoff.addingTimeInterval(3_600))

        let ongoing = try XCTUnwrap(LocationHistoryCutoffPolicy.adjustedVisit(
            arrival: cutoff.addingTimeInterval(-1_800),
            departure: nil,
            cutoff: cutoff
        ))
        XCTAssertEqual(ongoing.arrival, cutoff)
        XCTAssertNil(ongoing.departure)

        let futureArrival = cutoff.addingTimeInterval(600)
        let afterReset = try XCTUnwrap(LocationHistoryCutoffPolicy.adjustedVisit(
            arrival: futureArrival,
            departure: nil,
            cutoff: cutoff
        ))
        XCTAssertEqual(afterReset.arrival, futureArrival)
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
    func testJournalSaveMatchesExistingEntryByRecordedCivilDayAcrossTimezones() throws {
        let context = try makeContext()
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let tokyoZone = try XCTUnwrap(TimeZone(identifier: tokyo))
        let targetDay = CalendarDayComponents(2026, 8, 12)
        let losAngelesDate = try XCTUnwrap(targetDay.date(in: losAngeles))
        let losAngelesInterval = DayInterval(containing: losAngelesDate, timeZone: losAngeles)
        let existing = JournalEntry(
            dayAnchor: losAngelesInterval.start,
            body: "旅先で書いた日記",
            createdAt: losAngelesInterval.start.addingTimeInterval(60),
            updatedAt: losAngelesInterval.start.addingTimeInterval(60),
            timeZoneIdentifier: losAngeles.identifier
        )
        context.insert(existing)
        try context.save()

        let tokyoDate = try XCTUnwrap(targetDay.date(in: tokyoZone))
        let fallbackDay = DayInterval(containing: tokyoDate, timeZone: tokyoZone)
        let result = try JournalEditingService().save(
            day: fallbackDay,
            body: "更新後",
            existingJournal: nil,
            in: context,
            now: losAngelesInterval.start.addingTimeInterval(120)
        )

        XCTAssertEqual(result?.id, existing.id)
        XCTAssertEqual(result?.body, "更新後")
        XCTAssertEqual(try context.fetch(FetchDescriptor<JournalEntry>()).count, 1)
        XCTAssertEqual(TimelineDayProjection.day(for: try XCTUnwrap(result)), targetDay)
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
        let representative = try XCTUnwrap(targetDay.date(in: losAngeles))
        let expectedAnchor = DayInterval(containing: representative, timeZone: losAngeles).start
        XCTAssertEqual(
            journal.dayAnchor.timeIntervalSinceReferenceDate,
            expectedAnchor.timeIntervalSinceReferenceDate,
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
    func testTargetedHistoricalRebuildUsesRetimedBoundaryAndCreatesGap() throws {
        let context = try makeContext()
        let oldDeparture = baseTime.addingTimeInterval(60 * 60)
        let newDeparture = baseTime.addingTimeInterval(90 * 60)
        let nextArrival = baseTime.addingTimeInterval(3 * 60 * 60)

        let first = TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: oldDeparture,
            title: "学校",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        let second = TimelineEpisode(
            kind: .stay,
            startDate: nextArrival,
            endDate: nextArrival.addingTimeInterval(60 * 60),
            title: "家",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        let staleGap = TimelineEpisode(
            kind: .gap,
            startDate: oldDeparture,
            endDate: nextArrival,
            title: "記録のない区間",
            confidence: .low,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        context.insert(first)
        context.insert(second)
        context.insert(staleGap)
        try context.save()

        try TimelineEditingService().saveStay(
            first,
            title: first.title,
            startDate: first.startDate,
            endDate: newDeparture,
            confirmLocation: false,
            in: context
        )
        try TimelineEngine().rebuildTransitions(
            covering: DateInterval(
                start: oldDeparture.addingTimeInterval(-1),
                end: newDeparture.addingTimeInterval(1)
            ),
            in: context
        )

        let transitions = try context.fetch(FetchDescriptor<TimelineEpisode>()).filter { $0.kind != .stay }
        XCTAssertEqual(transitions.count, 1)
        let rebuilt = try XCTUnwrap(transitions.first)
        XCTAssertNotEqual(rebuilt.id, staleGap.id)
        XCTAssertEqual(rebuilt.kind, .gap)
        XCTAssertEqual(rebuilt.startDate, newDeparture)
        XCTAssertEqual(rebuilt.endDate, nextArrival)
    }

    @MainActor
    func testTargetedHistoricalRebuildFindsBoundaryStaysOutsideRequestedInterval() throws {
        let context = try makeContext()
        let departure = baseTime.addingTimeInterval(60 * 60)
        let intervalStart = baseTime.addingTimeInterval(2 * 60 * 60)
        let intervalEnd = baseTime.addingTimeInterval(3 * 60 * 60)
        let nextArrival = baseTime.addingTimeInterval(5 * 60 * 60)

        context.insert(TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: departure,
            title: "学校",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        ))
        context.insert(TimelineEpisode(
            kind: .stay,
            startDate: nextArrival,
            endDate: nextArrival.addingTimeInterval(60 * 60),
            title: "家",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        ))
        let staleGap = TimelineEpisode(
            kind: .gap,
            startDate: departure,
            endDate: nextArrival,
            title: "古いGap",
            confidence: .low,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        context.insert(staleGap)
        try context.save()

        try TimelineEngine().rebuildTransitions(
            covering: DateInterval(start: intervalStart, end: intervalEnd),
            in: context
        )

        let transitions = try context.fetch(FetchDescriptor<TimelineEpisode>())
            .filter { $0.kind != .stay }
        XCTAssertEqual(transitions.count, 1)
        let rebuilt = try XCTUnwrap(transitions.first)
        XCTAssertNotEqual(rebuilt.id, staleGap.id)
        XCTAssertEqual(rebuilt.kind, .gap)
        XCTAssertEqual(rebuilt.startDate, departure)
        XCTAssertEqual(rebuilt.endDate, nextArrival)
    }

    @MainActor
    func testTargetedHistoricalRebuildFindsProtectedTransitionOutsideRequestedInterval() throws {
        let context = try makeContext()
        let departure = baseTime.addingTimeInterval(60 * 60)
        let protectedEnd = baseTime.addingTimeInterval(2 * 60 * 60)
        let intervalStart = baseTime.addingTimeInterval(3 * 60 * 60)
        let intervalEnd = baseTime.addingTimeInterval(4 * 60 * 60)
        let nextArrival = baseTime.addingTimeInterval(5 * 60 * 60)

        context.insert(TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: departure,
            title: "学校",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        ))
        context.insert(TimelineEpisode(
            kind: .stay,
            startDate: nextArrival,
            endDate: nextArrival.addingTimeInterval(60 * 60),
            title: "家",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        ))
        let protectedGap = TimelineEpisode(
            kind: .gap,
            startDate: departure,
            endDate: protectedEnd,
            title: "保護済み区間",
            confidence: .low,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        let staleGap = TimelineEpisode(
            kind: .gap,
            startDate: protectedEnd,
            endDate: nextArrival,
            title: "古いGap",
            confidence: .low,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        context.insert(protectedGap)
        context.insert(staleGap)
        context.insert(UserAssertion(
            episodeID: protectedGap.id,
            type: .rename,
            replacementTitle: protectedGap.title
        ))
        try context.save()

        try TimelineEngine().rebuildTransitions(
            covering: DateInterval(start: intervalStart, end: intervalEnd),
            in: context
        )

        let transitions = try context.fetch(FetchDescriptor<TimelineEpisode>())
            .filter { $0.kind != .stay }
            .sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions.first?.id, protectedGap.id)
        XCTAssertEqual(transitions.first?.title, "保護済み区間")
    }

    @MainActor
    func testTargetedHistoricalRebuildUsesRetainedSampleForMove() throws {
        let context = try makeContext()
        let departure = baseTime.addingTimeInterval(60 * 60)
        let nextArrival = baseTime.addingTimeInterval(3 * 60 * 60)

        context.insert(TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: departure,
            title: "学校",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        ))
        context.insert(TimelineEpisode(
            kind: .stay,
            startDate: nextArrival,
            endDate: nextArrival.addingTimeInterval(60 * 60),
            title: "家",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        ))
        context.insert(TimelineEpisode(
            kind: .gap,
            startDate: departure,
            endDate: nextArrival,
            title: "古いGap",
            confidence: .low,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        ))
        context.insert(LocationEvidence(
            timestamp: departure.addingTimeInterval(20 * 60),
            latitude: 34.67,
            longitude: 133.93,
            horizontalAccuracy: 20,
            speed: 4,
            course: 90,
            source: .significantChange,
            timeZoneIdentifier: tokyo
        ))
        try context.save()

        try TimelineEngine().rebuildTransitions(
            covering: DateInterval(start: departure, end: nextArrival),
            in: context
        )

        let transitions = try context.fetch(FetchDescriptor<TimelineEpisode>())
            .filter { $0.kind != .stay }
            .sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions.first?.kind, .move)
        XCTAssertEqual(transitions.first?.startDate, departure)
        XCTAssertEqual(transitions.first?.endDate, nextArrival)
    }

    @MainActor
    func testTargetedHistoricalRebuildKeepsSuppressedMiddleStayAsTransitionBoundary() throws {
        let context = try makeContext()
        let firstDeparture = baseTime.addingTimeInterval(60 * 60)
        let middleArrival = baseTime.addingTimeInterval(2 * 60 * 60)
        let middleDeparture = baseTime.addingTimeInterval(3 * 60 * 60)
        let thirdArrival = baseTime.addingTimeInterval(4 * 60 * 60)

        let first = TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: firstDeparture,
            title: "学校",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        let middle = TimelineEpisode(
            kind: .stay,
            startDate: middleArrival,
            endDate: middleDeparture,
            title: "誤記録",
            confidence: .low,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        let third = TimelineEpisode(
            kind: .stay,
            startDate: thirdArrival,
            endDate: thirdArrival.addingTimeInterval(60 * 60),
            title: "家",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        context.insert(first)
        context.insert(middle)
        context.insert(third)
        context.insert(TimelineEpisode(
            kind: .gap,
            startDate: firstDeparture,
            endDate: middleArrival,
            title: "古いGap1",
            confidence: .low,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        ))
        context.insert(TimelineEpisode(
            kind: .gap,
            startDate: middleDeparture,
            endDate: thirdArrival,
            title: "古いGap2",
            confidence: .low,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        ))
        context.insert(UserAssertion(episodeID: middle.id, type: .suppress))
        try context.save()

        try TimelineEngine().rebuildTransitions(
            covering: DateInterval(start: firstDeparture, end: thirdArrival),
            in: context
        )

        let transitions = try context.fetch(FetchDescriptor<TimelineEpisode>())
            .filter { $0.kind != .stay }
            .sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(transitions.count, 2)
        XCTAssertEqual(transitions.map(\.kind), [.gap, .gap])
        XCTAssertEqual(transitions.map(\.startDate), [firstDeparture, middleDeparture])
        XCTAssertEqual(transitions.compactMap(\.endDate), [middleArrival, thirdArrival])
    }

    @MainActor
    func testTargetedHistoricalRebuildPreservesAssertedTransition() throws {
        let context = try makeContext()
        let departure = baseTime.addingTimeInterval(60 * 60)
        let nextArrival = baseTime.addingTimeInterval(3 * 60 * 60)

        context.insert(TimelineEpisode(
            kind: .stay,
            startDate: baseTime,
            endDate: departure,
            title: "学校",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        ))
        context.insert(TimelineEpisode(
            kind: .stay,
            startDate: nextArrival,
            endDate: nextArrival.addingTimeInterval(60 * 60),
            title: "家",
            confidence: .high,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        ))
        let protectedGap = TimelineEpisode(
            kind: .gap,
            startDate: departure,
            endDate: nextArrival,
            title: "ユーザー保護区間",
            confidence: .low,
            sourceVersion: 5,
            timeZoneIdentifier: tokyo
        )
        context.insert(protectedGap)
        context.insert(UserAssertion(
            episodeID: protectedGap.id,
            type: .rename,
            replacementTitle: protectedGap.title
        ))
        try context.save()

        try TimelineEngine().rebuildTransitions(
            covering: DateInterval(start: departure, end: nextArrival),
            in: context
        )

        let transitions = try context.fetch(FetchDescriptor<TimelineEpisode>()).filter { $0.kind != .stay }
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions.first?.id, protectedGap.id)
        XCTAssertEqual(transitions.first?.title, "ユーザー保護区間")
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
