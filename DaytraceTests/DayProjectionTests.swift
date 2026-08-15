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
    func testSuppressingMiddleStayRebuildsTransitionAcrossIt() throws {
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
        insertVisit(
            arrival: thirdArrival,
            departure: thirdDeparture,
            observedAt: thirdDeparture,
            latitude: 34.68,
            longitude: 133.94,
            in: context
        )
        try context.save()

        let engine = TimelineEngine()
        try engine.rebuildRecentTimeline(in: context, now: thirdDeparture)
        let middleStay = try stay(for: middleVisit.id, in: context)
        try TimelineEditingService().setSuppressed(
            episodeID: middleStay.id,
            suppressed: true,
            in: context
        )
        try engine.rebuildRecentTimeline(in: context, now: thirdDeparture)

        let episodes = try context.fetch(FetchDescriptor<TimelineEpisode>())
        let gaps = episodes.filter { $0.kind == .gap }
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps.first?.startDate, firstDeparture)
        XCTAssertEqual(gaps.first?.endDate, thirdArrival)
        XCTAssertNotNil(try stay(for: firstVisit.id, in: context))
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
            at: firstDeparture.addingTimeInterval(10 * 60),
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
