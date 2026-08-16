#if DEBUG
import Foundation
import SwiftData

@MainActor
struct DebugMarketingFixtureService {
    struct ImportResult: Equatable {
        let episodes: Int
        let places: Int
        let rawLocations: Int
        let visits: Int
        let journals: Int
        let momentNotes: Int
        let assertions: Int
    }

    enum FixtureError: LocalizedError {
        case missingFixture([String])

        var errorDescription: String? {
            switch self {
            case .missingFixture:
                "撮影素材Fixtureが見つかりません。"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .missingFixture(let paths):
                "次のいずれかに daytrace-marketing-fixture.json を置いてください:\n\(paths.joined(separator: "\n"))"
            }
        }
    }

    private let filename = "daytrace-marketing-fixture.json"

    func fixtureURL() -> URL? {
        candidateURLs().first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func expectedFixturePaths() -> [String] {
        candidateURLs().map(\.path)
    }

    func importFixture(in context: ModelContext) throws -> ImportResult {
        guard let url = fixtureURL() else {
            throw FixtureError.missingFixture(expectedFixturePaths())
        }

        return try importFixture(from: url, in: context)
    }

    func importFixture(from url: URL, in context: ModelContext) throws -> ImportResult {
        let fixture = try Self.decoder.decode(MarketingFixture.self, from: Data(contentsOf: url))
        try replaceAllData(in: context, with: fixture)

        return ImportResult(
            episodes: fixture.episodes.count,
            places: fixture.places.count,
            rawLocations: fixture.rawLocationEvidence.count,
            visits: fixture.visitEvidence.count,
            journals: fixture.journals.count,
            momentNotes: fixture.momentNotes.count,
            assertions: fixture.assertions.count
        )
    }

    private func replaceAllData(in context: ModelContext, with fixture: MarketingFixture) throws {
        try deleteAllData(in: context)

        for place in fixture.places {
            context.insert(PlaceRecord(
                id: place.id,
                name: place.name,
                latitude: place.latitude,
                longitude: place.longitude,
                radius: place.radius,
                source: PlaceSource(rawValue: place.source) ?? .coordinateOnly,
                isPrivate: place.isPrivate
            ))
        }

        for location in fixture.rawLocationEvidence {
            context.insert(LocationEvidence(
                id: location.id,
                timestamp: location.timestamp,
                latitude: location.latitude,
                longitude: location.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                speed: location.speed,
                course: location.course,
                source: EvidenceSource(rawValue: location.source) ?? .imported,
                timeZoneIdentifier: location.timeZoneIdentifier
            ))
        }

        for visit in fixture.visitEvidence {
            context.insert(VisitEvidence(
                id: visit.id,
                arrivalDate: visit.arrivalDate,
                departureDate: visit.departureDate,
                observedAt: visit.observedAt,
                latitude: visit.latitude,
                longitude: visit.longitude,
                horizontalAccuracy: visit.horizontalAccuracy,
                timeZoneIdentifier: visit.timeZoneIdentifier,
                source: EvidenceSource(rawValue: visit.source) ?? .visit
            ))
        }

        for episode in fixture.episodes {
            context.insert(TimelineEpisode(
                id: episode.id,
                kind: EpisodeKind(rawValue: episode.kind) ?? .gap,
                startDate: episode.startDate,
                endDate: episode.endDate,
                title: episode.title,
                subtitle: episode.subtitle,
                latitude: episode.latitude,
                longitude: episode.longitude,
                confidence: EpisodeConfidence(rawValue: episode.confidence) ?? .medium,
                placeID: episode.placeID,
                sourceVisitID: episode.sourceVisitID,
                sourceVersion: episode.sourceVersion,
                timeZoneIdentifier: episode.timeZoneIdentifier
            ))
        }

        for journal in fixture.journals {
            context.insert(JournalEntry(
                id: journal.id,
                dayAnchor: journal.dayAnchor,
                body: journal.body,
                createdAt: journal.createdAt,
                updatedAt: journal.updatedAt,
                timeZoneIdentifier: journal.timeZoneIdentifier
            ))
        }

        for moment in fixture.momentNotes {
            context.insert(MomentNote(
                id: moment.id,
                timestamp: moment.timestamp,
                body: moment.body,
                timeZoneIdentifier: moment.timeZoneIdentifier
            ))
        }

        for assertion in fixture.assertions {
            context.insert(UserAssertion(
                id: assertion.id,
                episodeID: assertion.episodeID,
                type: UserAssertionType(rawValue: assertion.type) ?? .confirm,
                createdAt: assertion.createdAt,
                replacementStart: assertion.replacementStart,
                replacementEnd: assertion.replacementEnd,
                replacementTitle: assertion.replacementTitle,
                replacementLatitude: assertion.replacementLatitude,
                replacementLongitude: assertion.replacementLongitude,
                isActive: assertion.isActive
            ))
        }

        try context.save()
    }

    private func deleteAllData(in context: ModelContext) throws {
        try context.fetch(FetchDescriptor<LocationEvidence>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<VisitEvidence>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<PlaceRecord>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<TimelineEpisode>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<UserAssertion>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<JournalEntry>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<MomentNote>()).forEach { context.delete($0) }
    }

    private func candidateURLs() -> [URL] {
        var urls: [URL] = []

        if let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: DaytraceWidgetShared.appGroupIdentifier
        ) {
            urls.append(
                appGroupURL
                    .appendingPathComponent("MarketingFixtures", isDirectory: true)
                    .appendingPathComponent(filename)
            )
            urls.append(appGroupURL.appendingPathComponent(filename))
        }

        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(
                documentsURL
                    .appendingPathComponent("MarketingFixtures", isDirectory: true)
                    .appendingPathComponent(filename)
            )
            urls.append(documentsURL.appendingPathComponent(filename))
        }

        if let bundledURL = Bundle.main.url(forResource: "daytrace-marketing-fixture", withExtension: "json") {
            urls.append(bundledURL)
        }

        return urls
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Self.fractionalISO8601Formatter.date(from: string) {
                return date
            }
            if let date = Self.iso8601Formatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(string)"
            )
        }
        return decoder
    }()

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Formatter = ISO8601DateFormatter()
}

private struct MarketingFixture: Decodable {
    let episodes: [MarketingEpisode]
    let places: [MarketingPlace]
    let rawLocationEvidence: [MarketingLocationEvidence]
    let visitEvidence: [MarketingVisitEvidence]
    let journals: [MarketingJournal]
    let momentNotes: [MarketingMomentNote]
    let assertions: [MarketingAssertion]
}

private struct MarketingEpisode: Decodable {
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

private struct MarketingPlace: Decodable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let source: String
    let isPrivate: Bool
}

private struct MarketingLocationEvidence: Decodable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let speed: Double
    let course: Double
    let source: String
    let timeZoneIdentifier: String
}

private struct MarketingVisitEvidence: Decodable {
    let id: UUID
    let arrivalDate: Date?
    let departureDate: Date?
    let observedAt: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let source: String
    let timeZoneIdentifier: String
}

private struct MarketingJournal: Decodable {
    let id: UUID
    let dayAnchor: Date
    let body: String
    let createdAt: Date
    let updatedAt: Date
    let timeZoneIdentifier: String
}

private struct MarketingMomentNote: Decodable {
    let id: UUID
    let timestamp: Date
    let body: String
    let timeZoneIdentifier: String
}

private struct MarketingAssertion: Decodable {
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
#endif
