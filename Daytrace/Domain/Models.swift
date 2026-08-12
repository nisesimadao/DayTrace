import Foundation
import SwiftData

@Model
final class LocationEvidence {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var speed: Double
    var course: Double
    var sourceRaw: String
    var timeZoneIdentifier: String

    init(
        id: UUID = UUID(),
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        speed: Double,
        course: Double,
        source: EvidenceSource,
        timeZoneIdentifier: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.course = course
        self.sourceRaw = source.rawValue
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var source: EvidenceSource {
        get { EvidenceSource(rawValue: sourceRaw) ?? .standardLocation }
        set { sourceRaw = newValue.rawValue }
    }
}

@Model
final class VisitEvidence {
    @Attribute(.unique) var id: UUID
    var arrivalDate: Date?
    var departureDate: Date?
    var observedAt: Date = Date.distantPast
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var timeZoneIdentifier: String

    init(
        id: UUID = UUID(),
        arrivalDate: Date?,
        departureDate: Date?,
        observedAt: Date = .now,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        timeZoneIdentifier: String
    ) {
        self.id = id
        self.arrivalDate = arrivalDate
        self.departureDate = departureDate
        self.observedAt = observedAt
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

@Model
final class PlaceRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var sourceRaw: String
    var isPrivate: Bool

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 100,
        source: PlaceSource = .userConfirmed,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.sourceRaw = source.rawValue
        self.isPrivate = isPrivate
    }

    var source: PlaceSource {
        get { PlaceSource(rawValue: sourceRaw) ?? .coordinateOnly }
        set { sourceRaw = newValue.rawValue }
    }
}

@Model
final class TimelineEpisode {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var startDate: Date
    var endDate: Date?
    var title: String
    var subtitle: String?
    var latitude: Double?
    var longitude: Double?
    var confidenceRaw: String
    var placeID: UUID?
    var sourceVisitID: UUID?
    var sourceVersion: Int
    var timeZoneIdentifier: String

    init(
        id: UUID = UUID(),
        kind: EpisodeKind,
        startDate: Date,
        endDate: Date?,
        title: String,
        subtitle: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        confidence: EpisodeConfidence = .medium,
        placeID: UUID? = nil,
        sourceVisitID: UUID? = nil,
        sourceVersion: Int = 1,
        timeZoneIdentifier: String
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.confidenceRaw = confidence.rawValue
        self.placeID = placeID
        self.sourceVisitID = sourceVisitID
        self.sourceVersion = sourceVersion
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var kind: EpisodeKind {
        get { EpisodeKind(rawValue: kindRaw) ?? .gap }
        set { kindRaw = newValue.rawValue }
    }

    var confidence: EpisodeConfidence {
        get { EpisodeConfidence(rawValue: confidenceRaw) ?? .low }
        set { confidenceRaw = newValue.rawValue }
    }
}

@Model
final class UserAssertion {
    @Attribute(.unique) var id: UUID
    var episodeID: UUID?
    var assertionTypeRaw: String
    var createdAt: Date
    var replacementStart: Date?
    var replacementEnd: Date?
    var replacementTitle: String?
    var replacementLatitude: Double?
    var replacementLongitude: Double?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        episodeID: UUID?,
        type: UserAssertionType,
        createdAt: Date = .now,
        replacementStart: Date? = nil,
        replacementEnd: Date? = nil,
        replacementTitle: String? = nil,
        replacementLatitude: Double? = nil,
        replacementLongitude: Double? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.episodeID = episodeID
        self.assertionTypeRaw = type.rawValue
        self.createdAt = createdAt
        self.replacementStart = replacementStart
        self.replacementEnd = replacementEnd
        self.replacementTitle = replacementTitle
        self.replacementLatitude = replacementLatitude
        self.replacementLongitude = replacementLongitude
        self.isActive = isActive
    }

    var type: UserAssertionType {
        get { UserAssertionType(rawValue: assertionTypeRaw) ?? .rename }
        set { assertionTypeRaw = newValue.rawValue }
    }
}

@Model
final class JournalEntry {
    @Attribute(.unique) var id: UUID
    var dayAnchor: Date
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var timeZoneIdentifier: String

    init(
        id: UUID = UUID(),
        dayAnchor: Date,
        body: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        timeZoneIdentifier: String
    ) {
        self.id = id
        self.dayAnchor = dayAnchor
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

@Model
final class MomentNote {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var body: String
    var timeZoneIdentifier: String

    init(id: UUID = UUID(), timestamp: Date, body: String, timeZoneIdentifier: String) {
        self.id = id
        self.timestamp = timestamp
        self.body = body
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

enum EvidenceSource: String, Codable, Hashable, Sendable {
    case standardLocation
    case significantChange
    case visit
    case userAdded
    case imported
}

enum PlaceSource: String, Codable, Hashable, Sendable {
    case userConfirmed
    case learned
    case mapSuggestion
    case coordinateOnly
}

enum EpisodeKind: String, Codable, Hashable, Sendable {
    case stay
    case move
    case gap
}

enum EpisodeConfidence: String, Codable, Hashable, Sendable {
    case high
    case medium
    case low
}

enum UserAssertionType: String, Codable, Hashable, Sendable {
    case rename
    case retime
    case retimeStart
    case retimeEnd
    case reposition
    case suppress
    case mergeStay
    case splitStay
    case confirm
}

enum TimelineVisibility {
    static func suppressedEpisodeIDs(from assertions: [UserAssertion]) -> Set<UUID> {
        Set(assertions.compactMap { assertion in
            guard assertion.isActive,
                  assertion.type == .suppress,
                  let episodeID = assertion.episodeID else {
                return nil
            }
            return episodeID
        })
    }
}

enum TimelineEditingError: LocalizedError, Equatable {
    case invalidStayRange
    case overlapsStay(String)

    var errorDescription: String? {
        switch self {
        case .invalidStayRange:
            "出発時刻は到着時刻より後にしてください。"
        case .overlapsStay(let title):
            "「\(title)」と時間が重なっています。"
        }
    }
}

@MainActor
enum StayIntervalValidator {
    static func validationError(
        episodeID: UUID,
        startDate: Date,
        endDate: Date?,
        episodes: [TimelineEpisode],
        suppressedEpisodeIDs: Set<UUID>
    ) -> TimelineEditingError? {
        if let endDate, endDate <= startDate {
            return .invalidStayRange
        }

        let proposedEnd = endDate ?? .distantFuture
        let conflict = episodes
            .filter {
                $0.kind == .stay
                    && $0.id != episodeID
                    && !suppressedEpisodeIDs.contains($0.id)
            }
            .sorted { $0.startDate < $1.startDate }
            .first { other in
                let otherEnd = other.endDate ?? .distantFuture
                return startDate < otherEnd && proposedEnd > other.startDate
            }

        if let conflict {
            return .overlapsStay(conflict.title)
        }
        return nil
    }
}

@MainActor
struct TimelineEditingService {
    func saveStay(
        _ episode: TimelineEpisode,
        title: String,
        startDate: Date,
        endDate: Date?,
        confirmLocation: Bool,
        in context: ModelContext
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = trimmedTitle.isEmpty ? episode.title : trimmedTitle
        let startChanged = startDate != episode.startDate
        let endChanged = endDate != episode.endDate

        if startChanged || endChanged {
            let episodes = try context.fetch(FetchDescriptor<TimelineEpisode>())
            let assertions = try context.fetch(FetchDescriptor<UserAssertion>())
            let suppressedEpisodeIDs = TimelineVisibility.suppressedEpisodeIDs(from: assertions)

            if let validationError = StayIntervalValidator.validationError(
                episodeID: episode.id,
                startDate: startDate,
                endDate: endDate,
                episodes: episodes,
                suppressedEpisodeIDs: suppressedEpisodeIDs
            ) {
                throw validationError
            }
        }

        if safeTitle != episode.title {
            deactivateAssertions(for: episode.id, type: .rename, in: context)
            context.insert(UserAssertion(
                episodeID: episode.id,
                type: .rename,
                replacementTitle: safeTitle
            ))
            episode.title = safeTitle
            detachMismatchedPlace(from: episode, title: safeTitle, in: context)
        }

        if startChanged || endChanged {
            migrateLegacyRetimeIfNeeded(
                for: episode.id,
                startChanged: startChanged,
                endChanged: endChanged,
                in: context
            )
        }

        if startChanged {
            deactivateAssertions(for: episode.id, type: .retimeStart, in: context)
            context.insert(UserAssertion(
                episodeID: episode.id,
                type: .retimeStart,
                replacementStart: startDate
            ))
            episode.startDate = startDate
        }

        if endChanged {
            deactivateAssertions(for: episode.id, type: .retimeEnd, in: context)
            context.insert(UserAssertion(
                episodeID: episode.id,
                type: .retimeEnd,
                replacementEnd: endDate
            ))
            episode.endDate = endDate
        }

        let canConfirmLocation = confirmLocation
            && !safeTitle.isEmpty
            && safeTitle != "未設定の場所"

        if canConfirmLocation, episode.confidence != .high {
            deactivateAssertions(for: episode.id, type: .confirm, in: context)
            context.insert(UserAssertion(episodeID: episode.id, type: .confirm))
            episode.confidence = .high
            episode.subtitle = nil
            learnConfirmedPlace(for: episode, name: safeTitle, in: context)
        }

        try context.save()
    }

    func setSuppressed(
        episodeID: UUID,
        suppressed: Bool,
        in context: ModelContext
    ) throws {
        deactivateAssertions(for: episodeID, type: .suppress, in: context)

        if suppressed {
            context.insert(UserAssertion(episodeID: episodeID, type: .suppress))
        } else {
            clearLegacySuppressedSubtitle(for: episodeID, in: context)
        }

        try context.save()
    }

    func restoreAllSuppressed(in context: ModelContext) throws {
        guard let assertions = try? context.fetch(FetchDescriptor<UserAssertion>()) else { return }
        let suppressedIDs = Set(assertions.compactMap { assertion -> UUID? in
            guard assertion.isActive, assertion.type == .suppress else { return nil }
            assertion.isActive = false
            return assertion.episodeID
        })

        guard !suppressedIDs.isEmpty else { return }
        let episodes = (try? context.fetch(FetchDescriptor<TimelineEpisode>())) ?? []
        for episode in episodes where suppressedIDs.contains(episode.id) && episode.subtitle == "非表示" {
            episode.subtitle = nil
        }
        try context.save()
    }

    private func migrateLegacyRetimeIfNeeded(
        for episodeID: UUID,
        startChanged: Bool,
        endChanged: Bool,
        in context: ModelContext
    ) {
        guard let assertions = try? context.fetch(FetchDescriptor<UserAssertion>()) else { return }
        let active = assertions.filter { $0.episodeID == episodeID && $0.isActive }
        guard let legacy = active
            .filter({ $0.type == .retime })
            .max(by: { $0.createdAt < $1.createdAt }) else {
            return
        }

        let hasStartOverride = active.contains { $0.type == .retimeStart }
        let hasEndOverride = active.contains { $0.type == .retimeEnd }

        for assertion in active where assertion.type == .retime {
            assertion.isActive = false
        }

        if !startChanged, !hasStartOverride, let start = legacy.replacementStart {
            context.insert(UserAssertion(
                episodeID: episodeID,
                type: .retimeStart,
                replacementStart: start
            ))
        }

        if !endChanged, !hasEndOverride {
            context.insert(UserAssertion(
                episodeID: episodeID,
                type: .retimeEnd,
                replacementEnd: legacy.replacementEnd
            ))
        }
    }

    private func deactivateAssertions(
        for episodeID: UUID,
        type: UserAssertionType,
        in context: ModelContext
    ) {
        guard let assertions = try? context.fetch(FetchDescriptor<UserAssertion>()) else { return }
        for assertion in assertions where assertion.episodeID == episodeID && assertion.type == type && assertion.isActive {
            assertion.isActive = false
        }
    }

    private func clearLegacySuppressedSubtitle(for episodeID: UUID, in context: ModelContext) {
        guard let episodes = try? context.fetch(FetchDescriptor<TimelineEpisode>()) else { return }
        if let episode = episodes.first(where: { $0.id == episodeID && $0.subtitle == "非表示" }) {
            episode.subtitle = nil
        }
    }

    private func detachMismatchedPlace(
        from episode: TimelineEpisode,
        title: String,
        in context: ModelContext
    ) {
        guard let placeID = episode.placeID else { return }
        let places = (try? context.fetch(FetchDescriptor<PlaceRecord>())) ?? []
        guard let place = places.first(where: { $0.id == placeID }), place.name != title else { return }
        episode.placeID = nil
        episode.confidence = .medium
        episode.subtitle = "場所を確認"
    }

    private func learnConfirmedPlace(for episode: TimelineEpisode, name: String, in context: ModelContext) {
        guard let latitude = episode.latitude, let longitude = episode.longitude else { return }
        let places = (try? context.fetch(FetchDescriptor<PlaceRecord>())) ?? []

        if let placeID = episode.placeID,
           let place = places.first(where: { $0.id == placeID }),
           place.name == name {
            place.source = .userConfirmed
            return
        }

        let place = PlaceRecord(
            name: name,
            latitude: latitude,
            longitude: longitude,
            radius: 100,
            source: .userConfirmed
        )
        context.insert(place)
        episode.placeID = place.id
    }
}
