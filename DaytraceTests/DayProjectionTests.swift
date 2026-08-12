import SwiftData
import XCTest
@testable import Daytrace

final class DayProjectionTests: XCTestCase {
    func testDayIntervalIntersectsOvernightEpisode() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12)))
        let interval = DayInterval(containing: day, timeZone: zone)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 23)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 8)))

        XCTAssertTrue(interval.intersects(start: start, end: end))
    }

    func testFutureEpisodeDoesNotIntersect() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12)))
        let interval = DayInterval(containing: day, timeZone: zone)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 9)))

        XCTAssertFalse(interval.intersects(start: start, end: nil))
    }

    @MainActor
    func testRenameAssertionDoesNotFreezeAutomaticDeparture() throws {
        let context = try makeContext()
        let arrival = Date(timeIntervalSince1970: 1_786_500_000)
        let departure = arrival.addingTimeInterval(60 * 60 * 7)
        let visit = VisitEvidence(
            arrivalDate: arrival,
            departureDate: nil,
            observedAt: arrival,
            latitude: 34.66,
            longitude: 133.92,
            horizontalAccuracy: 30,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        context.insert(visit)
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: arrival.addingTimeInterval(60))
        let firstStay = try XCTUnwrap(try context.fetch(FetchDescriptor<TimelineEpisode>()).first { $0.kind == .stay })

        try TimelineEditingService().saveStay(
            firstStay,
            title: "学校",
            startDate: firstStay.startDate,
            endDate: firstStay.endDate,
            confirmLocation: false,
            in: context
        )

        visit.departureDate = departure
        visit.observedAt = departure
        try context.save()
        try TimelineEngine().rebuildRecentTimeline(in: context, now: departure.addingTimeInterval(60))

        let stays = try context.fetch(FetchDescriptor<TimelineEpisode>()).filter { $0.kind == .stay }
        let stay = try XCTUnwrap(stays.first { $0.sourceVisitID == visit.id })
        XCTAssertEqual(stay.title, "学校")
        XCTAssertEqual(stay.endDate, departure)
    }

    @MainActor
    func testEditingArrivalDoesNotFreezeAutomaticDeparture() throws {
        let context = try makeContext()
        let arrival = Date(timeIntervalSince1970: 1_786_500_000)
        let editedArrival = arrival.addingTimeInterval(-10 * 60)
        let departure = arrival.addingTimeInterval(60 * 60 * 5)
        let visit = VisitEvidence(
            arrivalDate: arrival,
            departureDate: nil,
            observedAt: arrival,
            latitude: 34.66,
            longitude: 133.92,
            horizontalAccuracy: 25,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        context.insert(visit)
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: arrival.addingTimeInterval(60))
        let firstStay = try XCTUnwrap(try context.fetch(FetchDescriptor<TimelineEpisode>()).first { $0.kind == .stay })

        try TimelineEditingService().saveStay(
            firstStay,
            title: firstStay.title,
            startDate: editedArrival,
            endDate: firstStay.endDate,
            confirmLocation: false,
            in: context
        )

        visit.departureDate = departure
        visit.observedAt = departure
        try context.save()
        try TimelineEngine().rebuildRecentTimeline(in: context, now: departure.addingTimeInterval(60))

        let stay = try XCTUnwrap(try context.fetch(FetchDescriptor<TimelineEpisode>()).first { $0.sourceVisitID == visit.id })
        XCTAssertEqual(stay.startDate, editedArrival)
        XCTAssertEqual(stay.endDate, departure)
    }

    @MainActor
    func testEditingDepartureDoesNotFreezeAutomaticArrivalRefinement() throws {
        let context = try makeContext()
        let arrival = Date(timeIntervalSince1970: 1_786_500_000)
        let initialDeparture = arrival.addingTimeInterval(60 * 60 * 4)
        let editedDeparture = initialDeparture.addingTimeInterval(20 * 60)
        let refinedArrival = arrival.addingTimeInterval(5 * 60)
        let visit = VisitEvidence(
            arrivalDate: arrival,
            departureDate: initialDeparture,
            observedAt: initialDeparture,
            latitude: 34.66,
            longitude: 133.92,
            horizontalAccuracy: 25,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        context.insert(visit)
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: initialDeparture.addingTimeInterval(60))
        let firstStay = try XCTUnwrap(try context.fetch(FetchDescriptor<TimelineEpisode>()).first { $0.kind == .stay })

        try TimelineEditingService().saveStay(
            firstStay,
            title: firstStay.title,
            startDate: firstStay.startDate,
            endDate: editedDeparture,
            confirmLocation: false,
            in: context
        )

        visit.arrivalDate = refinedArrival
        visit.observedAt = editedDeparture
        try context.save()
        try TimelineEngine().rebuildRecentTimeline(in: context, now: editedDeparture.addingTimeInterval(60))

        let stay = try XCTUnwrap(try context.fetch(FetchDescriptor<TimelineEpisode>()).first { $0.sourceVisitID == visit.id })
        XCTAssertEqual(stay.startDate, refinedArrival)
        XCTAssertEqual(stay.endDate, editedDeparture)
    }

    @MainActor
    func testClearingDepartureKeepsOngoingOverride() throws {
        let context = try makeContext()
        let arrival = Date(timeIntervalSince1970: 1_786_500_000)
        let departure = arrival.addingTimeInterval(60 * 60 * 2)
        let visit = VisitEvidence(
            arrivalDate: arrival,
            departureDate: departure,
            observedAt: departure,
            latitude: 34.66,
            longitude: 133.92,
            horizontalAccuracy: 25,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        context.insert(visit)
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: departure.addingTimeInterval(60))
        let firstStay = try XCTUnwrap(try context.fetch(FetchDescriptor<TimelineEpisode>()).first { $0.kind == .stay })

        try TimelineEditingService().saveStay(
            firstStay,
            title: firstStay.title,
            startDate: firstStay.startDate,
            endDate: nil,
            confirmLocation: false,
            in: context
        )
        try TimelineEngine().rebuildRecentTimeline(in: context, now: departure.addingTimeInterval(120))

        let stay = try XCTUnwrap(try context.fetch(FetchDescriptor<TimelineEpisode>()).first { $0.sourceVisitID == visit.id })
        XCTAssertNil(stay.endDate)
    }

    @MainActor
    func testUnknownArrivalDoesNotInventStay() throws {
        let context = try makeContext()
        let departure = Date(timeIntervalSince1970: 1_786_500_000)
        context.insert(VisitEvidence(
            arrivalDate: nil,
            departureDate: departure,
            observedAt: departure,
            latitude: 34.66,
            longitude: 133.92,
            horizontalAccuracy: 40,
            timeZoneIdentifier: "Asia/Tokyo"
        ))
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: departure.addingTimeInterval(60))

        let stays = try context.fetch(FetchDescriptor<TimelineEpisode>()).filter { $0.kind == .stay }
        XCTAssertTrue(stays.isEmpty)
    }

    @MainActor
    func testTransitionWithoutSamplesBecomesGap() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_786_500_000)
        let firstDeparture = start.addingTimeInterval(60 * 60)
        let secondArrival = firstDeparture.addingTimeInterval(30 * 60)

        context.insert(VisitEvidence(
            arrivalDate: start,
            departureDate: firstDeparture,
            observedAt: firstDeparture,
            latitude: 34.66,
            longitude: 133.92,
            horizontalAccuracy: 30,
            timeZoneIdentifier: "Asia/Tokyo"
        ))
        context.insert(VisitEvidence(
            arrivalDate: secondArrival,
            departureDate: secondArrival.addingTimeInterval(60 * 60),
            observedAt: secondArrival,
            latitude: 34.68,
            longitude: 133.94,
            horizontalAccuracy: 30,
            timeZoneIdentifier: "Asia/Tokyo"
        ))
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: secondArrival.addingTimeInterval(60 * 60))

        let episodes = try context.fetch(FetchDescriptor<TimelineEpisode>())
        XCTAssertEqual(episodes.filter { $0.kind == .gap }.count, 1)
        XCTAssertEqual(episodes.filter { $0.kind == .move }.count, 0)
    }

    @MainActor
    func testTransitionWithLocationSampleBecomesMove() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_786_500_000)
        let firstDeparture = start.addingTimeInterval(60 * 60)
        let secondArrival = firstDeparture.addingTimeInterval(30 * 60)

        context.insert(VisitEvidence(
            arrivalDate: start,
            departureDate: firstDeparture,
            observedAt: firstDeparture,
            latitude: 34.66,
            longitude: 133.92,
            horizontalAccuracy: 30,
            timeZoneIdentifier: "Asia/Tokyo"
        ))
        context.insert(VisitEvidence(
            arrivalDate: secondArrival,
            departureDate: secondArrival.addingTimeInterval(60 * 60),
            observedAt: secondArrival,
            latitude: 34.68,
            longitude: 133.94,
            horizontalAccuracy: 30,
            timeZoneIdentifier: "Asia/Tokyo"
        ))
        context.insert(LocationEvidence(
            timestamp: firstDeparture.addingTimeInterval(10 * 60),
            latitude: 34.67,
            longitude: 133.93,
            horizontalAccuracy: 20,
            speed: 4,
            course: 90,
            source: .significantChange,
            timeZoneIdentifier: "Asia/Tokyo"
        ))
        try context.save()

        try TimelineEngine().rebuildRecentTimeline(in: context, now: secondArrival.addingTimeInterval(60 * 60))

        let episodes = try context.fetch(FetchDescriptor<TimelineEpisode>())
        XCTAssertEqual(episodes.filter { $0.kind == .move }.count, 1)
        XCTAssertEqual(episodes.filter { $0.kind == .gap }.count, 0)
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
