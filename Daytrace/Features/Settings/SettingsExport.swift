import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum DayTraceExportFormat {
    case json
    case markdown
    case gpx

    var contentType: UTType {
        switch self {
        case .json: .json
        case .markdown: .dayTraceMarkdown
        case .gpx: .dayTraceGPX
        }
    }

    var fileExtension: String {
        switch self {
        case .json: "json"
        case .markdown: "md"
        case .gpx: "gpx"
        }
    }
}

extension UTType {
    static var dayTraceMarkdown: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    static var dayTraceGPX: UTType {
        UTType(filenameExtension: "gpx") ?? .xml
    }
}

struct DayTraceExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json, .dayTraceMarkdown, .dayTraceGPX, .plainText, .xml]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
enum DayTraceExportBuilder {
    struct Snapshot: Codable {
        let schemaVersion: Int
        let exportedAt: Date
        let rawLocationEvidenceIncluded: Bool
        let episodes: [Episode]
        let journals: [Journal]
        let momentNotes: [Moment]
        let places: [Place]
        let assertions: [Assertion]
    }

    struct Episode: Codable {
        let id: UUID
        let kind: String
        let startDate: Date
        let endDate: Date?
        let title: String
        let subtitle: String?
        let latitude: Double?
        let longitude: Double?
        let confidence: String
        let placeID: UUID?
        let sourceVisitID: UUID?
        let sourceVersion: Int
        let timeZoneIdentifier: String
    }

    struct Journal: Codable {
        let id: UUID
        let dayAnchor: Date
        let body: String
        let createdAt: Date
        let updatedAt: Date
        let timeZoneIdentifier: String
    }

    struct Moment: Codable {
        let id: UUID
        let timestamp: Date
        let body: String
        let timeZoneIdentifier: String
    }

    struct Place: Codable {
        let id: UUID
        let name: String
        let latitude: Double
        let longitude: Double
        let radius: Double
        let source: String
        let isPrivate: Bool
    }

    struct Assertion: Codable {
        let id: UUID
        let episodeID: UUID?
        let type: String
        let createdAt: Date
        let replacementStart: Date?
        let replacementEnd: Date?
        let replacementTitle: String?
        let replacementLatitude: Double?
        let replacementLongitude: Double?
        let isActive: Bool
    }

    static func json(
        episodes: [TimelineEpisode],
        journals: [JournalEntry],
        momentNotes: [MomentNote],
        places: [PlaceRecord],
        assertions: [UserAssertion],
        now: Date = .now
    ) throws -> Data {
        let snapshot = Snapshot(
            schemaVersion: 1,
            exportedAt: now,
            rawLocationEvidenceIncluded: false,
            episodes: episodes.map {
                Episode(
                    id: $0.id,
                    kind: $0.kind.rawValue,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    title: $0.title,
                    subtitle: $0.subtitle,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    confidence: $0.confidence.rawValue,
                    placeID: $0.placeID,
                    sourceVisitID: $0.sourceVisitID,
                    sourceVersion: $0.sourceVersion,
                    timeZoneIdentifier: $0.timeZoneIdentifier
                )
            },
            journals: journals.map {
                Journal(
                    id: $0.id,
                    dayAnchor: $0.dayAnchor,
                    body: $0.body,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    timeZoneIdentifier: $0.timeZoneIdentifier
                )
            },
            momentNotes: momentNotes.map {
                Moment(
                    id: $0.id,
                    timestamp: $0.timestamp,
                    body: $0.body,
                    timeZoneIdentifier: $0.timeZoneIdentifier
                )
            },
            places: places.map {
                Place(
                    id: $0.id,
                    name: $0.name,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    radius: $0.radius,
                    source: $0.source.rawValue,
                    isPrivate: $0.isPrivate
                )
            },
            assertions: assertions.map {
                Assertion(
                    id: $0.id,
                    episodeID: $0.episodeID,
                    type: $0.type.rawValue,
                    createdAt: $0.createdAt,
                    replacementStart: $0.replacementStart,
                    replacementEnd: $0.replacementEnd,
                    replacementTitle: $0.replacementTitle,
                    replacementLatitude: $0.replacementLatitude,
                    replacementLongitude: $0.replacementLongitude,
                    isActive: $0.isActive
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func markdown(
        episodes: [TimelineEpisode],
        journals: [JournalEntry],
        momentNotes: [MomentNote],
        now: Date = .now
    ) -> String {
        var days = Set<CalendarDay>()
        for episode in episodes {
            days.formUnion(TimelineDayProjection.coveredDays(by: episode, openEndedAt: now, limit: 10_000))
        }
        for journal in journals {
            days.insert(TimelineDayProjection.day(for: journal))
        }
        for note in momentNotes {
            let zone = TimelineDayProjection.timeZone(identifier: note.timeZoneIdentifier)
            days.insert(CalendarDay(containing: note.timestamp, timeZone: zone))
        }

        var lines = [
            "# DayTrace",
            "",
            "書き出し日時: \(iso8601(now))",
            ""
        ]

        for day in days.sorted() {
            lines.append("## \(dayString(day))")
            lines.append("")

            let dayEpisodes = episodes
                .filter { TimelineDayProjection.episode($0, intersects: day, openEndedAt: now) }
                .sorted { $0.startDate < $1.startDate }

            for episode in dayEpisodes {
                let start = TimelineFormatting.clock(
                    episode.startDate,
                    timeZoneIdentifier: episode.timeZoneIdentifier
                )
                let end = episode.endDate.map {
                    TimelineFormatting.clock($0, timeZoneIdentifier: episode.timeZoneIdentifier)
                } ?? "継続中"
                lines.append("- \(start)–\(end)  \(episode.title)")
            }

            let dayNotes = momentNotes
                .filter { note in
                    let zone = TimelineDayProjection.timeZone(identifier: note.timeZoneIdentifier)
                    return CalendarDay(containing: note.timestamp, timeZone: zone) == day
                }
                .sorted { $0.timestamp < $1.timestamp }

            if !dayNotes.isEmpty {
                lines.append("")
                lines.append("### メモ")
                lines.append("")
                for note in dayNotes {
                    let time = TimelineFormatting.clock(
                        note.timestamp,
                        timeZoneIdentifier: note.timeZoneIdentifier
                    )
                    lines.append("- \(time)  \(note.body.replacingOccurrences(of: "\n", with: " "))")
                }
            }

            if let journal = journals.first(where: { TimelineDayProjection.journal($0, belongsTo: day) }),
               !journal.body.isEmpty {
                lines.append("")
                lines.append("### 日記")
                lines.append("")
                lines.append(journal.body)
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func gpx(locations: [LocationEvidence], now: Date = .now) -> String {
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        let segments = splitGPXSegments(sorted)

        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"DayTrace\" xmlns=\"http://www.topografix.com/GPX/1/1\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">",
            "  <metadata>",
            "    <time>\(iso8601(now))</time>",
            "  </metadata>",
            "  <trk>",
            "    <name>DayTrace</name>"
        ]

        for segment in segments {
            lines.append("    <trkseg>")
            for location in segment {
                lines.append(
                    "      <trkpt lat=\"\(decimal(location.latitude))\" lon=\"\(decimal(location.longitude))\"><time>\(iso8601(location.timestamp))</time></trkpt>"
                )
            }
            lines.append("    </trkseg>")
        }

        lines.append("  </trk>")
        lines.append("</gpx>")
        return lines.joined(separator: "\n")
    }

    static func filenameDate(_ date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func splitGPXSegments(_ locations: [LocationEvidence]) -> [[LocationEvidence]] {
        guard let first = locations.first else { return [] }

        var result: [[LocationEvidence]] = []
        var current = [first]

        for location in locations.dropFirst() {
            if let previous = current.last,
               location.timestamp.timeIntervalSince(previous.timestamp) > 10 * 60 {
                result.append(current)
                current = []
            }
            current.append(location)
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func dayString(_ day: CalendarDay) -> String {
        String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
