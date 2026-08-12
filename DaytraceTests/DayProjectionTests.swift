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
}
