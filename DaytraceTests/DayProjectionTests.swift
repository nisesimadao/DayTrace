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
            sourceVersion: 5,
            timeZoneIdentifier: zone
        )
        context.insert(episode)
        return episode
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
