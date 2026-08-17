import CoreLocation
import Foundation

enum DayRoutePointKind: Equatable, Sendable {
    case stay
    case movementSample
    case currentLocation
}

struct DayRoutePoint: Identifiable, Sendable {
    let id: String
    let kind: DayRoutePointKind
    let timestamp: Date
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct DayRouteStayInput: Equatable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date?
    let latitude: Double
    let longitude: Double

    init(id: UUID, startDate: Date, endDate: Date?, latitude: Double, longitude: Double) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.latitude = latitude
        self.longitude = longitude
    }

    init?(episode: TimelineEpisode) {
        guard episode.kind == .stay,
              let latitude = episode.latitude,
              let longitude = episode.longitude else {
            return nil
        }
        id = episode.id
        startDate = episode.startDate
        endDate = episode.endDate
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct DayRouteLocationInput: Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let source: EvidenceSource

    init(
        id: UUID,
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        source: EvidenceSource
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.source = source
    }

    init(evidence: LocationEvidence) {
        id = evidence.id
        timestamp = evidence.timestamp
        latitude = evidence.latitude
        longitude = evidence.longitude
        horizontalAccuracy = evidence.horizontalAccuracy
        source = evidence.source
    }
}

struct DayRouteCurrentLocationInput: Equatable, Sendable {
    let startDate: Date
    let lastEvidenceAt: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timeZoneIdentifier: String

    init(
        startDate: Date,
        lastEvidenceAt: Date,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        timeZoneIdentifier: String
    ) {
        self.startDate = startDate
        self.lastEvidenceAt = lastEvidenceAt
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    init(currentLocation: CurrentLocationContext) {
        startDate = currentLocation.startDate
        lastEvidenceAt = currentLocation.lastEvidenceAt
        latitude = currentLocation.latitude
        longitude = currentLocation.longitude
        horizontalAccuracy = currentLocation.horizontalAccuracy
        timeZoneIdentifier = currentLocation.timeZoneIdentifier
    }
}

@MainActor
enum DayRouteProjection {
    struct Options: Equatable, Sendable {
        var maximumSamplesPerSegment: Int
        var minimumSampleInterval: TimeInterval
        var minimumSampleDistance: CLLocationDistance
        var includesCurrentLocationInRoute: Bool

        static let preview = Options(
            maximumSamplesPerSegment: 28,
            minimumSampleInterval: 25,
            minimumSampleDistance: 260,
            includesCurrentLocationInRoute: true
        )

        static let detail = Options(
            maximumSamplesPerSegment: 120,
            minimumSampleInterval: 10,
            minimumSampleDistance: 90,
            includesCurrentLocationInRoute: true
        )
    }

    private static let maximumRouteSampleAccuracy: CLLocationAccuracy = 1_000

    static func points(
        episodes: [TimelineEpisode],
        locationEvidence: [LocationEvidence],
        currentLocation: CurrentLocationContext? = nil,
        options: Options = .detail
    ) -> [DayRoutePoint] {
        points(
            stays: episodes.compactMap { DayRouteStayInput(episode: $0) },
            locationEvidence: locationEvidence.map { DayRouteLocationInput(evidence: $0) },
            currentLocation: currentLocation.map { DayRouteCurrentLocationInput(currentLocation: $0) },
            options: options
        )
    }

    static func points(
        stays: [DayRouteStayInput],
        locationEvidence: [DayRouteLocationInput],
        currentLocation: DayRouteCurrentLocationInput? = nil,
        options: Options = .detail
    ) -> [DayRoutePoint] {
        let sortedStays = stays.sorted { $0.startDate < $1.startDate }

        guard let firstStay = sortedStays.first else {
            guard let currentLocation else { return [] }
            return [point(for: currentLocation)]
        }

        let usableSamples = locationEvidence
            .filter {
                $0.horizontalAccuracy >= 0
                    && $0.horizontalAccuracy <= maximumRouteSampleAccuracy
                    && ($0.source == .standardLocation || $0.source == .significantChange)
            }
            .sorted { $0.timestamp < $1.timestamp }

        var routePoints: [DayRoutePoint] = [point(for: firstStay)]

        for pair in zip(sortedStays, sortedStays.dropFirst()) {
            if let departure = pair.0.endDate {
                routePoints.append(contentsOf: samples(
                    from: usableSamples,
                    start: departure,
                    end: pair.1.startDate,
                    startCoordinate: coordinate(for: pair.0),
                    options: options
                ))
            }
            routePoints.append(point(for: pair.1))
        }

        if let currentLocation, options.includesCurrentLocationInRoute {
            let lastStay = sortedStays[sortedStays.count - 1]
            let routeStart = lastStay.endDate ?? lastStay.startDate
            routePoints.append(contentsOf: samples(
                from: usableSamples,
                start: routeStart,
                end: currentLocation.lastEvidenceAt,
                startCoordinate: coordinate(for: lastStay),
                options: options
            ))
            routePoints.append(point(for: currentLocation))
        }

        return removeAdjacentDuplicates(routePoints)
    }

    static func movementSampleCount(
        episodes: [TimelineEpisode],
        locationEvidence: [LocationEvidence],
        currentLocation: CurrentLocationContext? = nil,
        options: Options = .detail
    ) -> Int {
        points(
            episodes: episodes,
            locationEvidence: locationEvidence,
            currentLocation: currentLocation,
            options: options
        )
        .count { $0.kind == .movementSample }
    }

    private static func samples(
        from evidence: [DayRouteLocationInput],
        start: Date,
        end: Date,
        startCoordinate: CLLocationCoordinate2D,
        options: Options
    ) -> [DayRoutePoint] {
        guard end > start else { return [] }

        let lowerBound = firstIndex(after: start, in: evidence)
        let upperBound = firstIndex(atOrAfter: end, in: evidence)
        guard lowerBound < upperBound else { return [] }
        let segmentSamples = Array(evidence[lowerBound..<upperBound])
        let thinnedSamples = thin(
            segmentSamples,
            startCoordinate: startCoordinate,
            minimumInterval: options.minimumSampleInterval,
            minimumDistance: options.minimumSampleDistance
        )
        let decimatedSamples = decimate(thinnedSamples, maximumCount: options.maximumSamplesPerSegment)
        return decimatedSamples.map { sample in
            DayRoutePoint(
                id: "sample-\(sample.id.uuidString)",
                kind: .movementSample,
                timestamp: sample.timestamp,
                latitude: sample.latitude,
                longitude: sample.longitude
            )
        }
    }

    private static func thin(
        _ samples: [DayRouteLocationInput],
        startCoordinate: CLLocationCoordinate2D,
        minimumInterval: TimeInterval,
        minimumDistance: CLLocationDistance
    ) -> [DayRouteLocationInput] {
        var thinned: [DayRouteLocationInput] = []
        var lastAcceptedLocation = CLLocation(
            latitude: startCoordinate.latitude,
            longitude: startCoordinate.longitude
        )
        var lastAcceptedTimestamp: Date?

        for sample in samples {
            let elapsed = lastAcceptedTimestamp.map {
                sample.timestamp.timeIntervalSince($0)
            } ?? .greatestFiniteMagnitude
            let sampleLocation = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
            let distance = sampleLocation.distance(from: lastAcceptedLocation)
            guard elapsed >= minimumInterval && distance >= minimumDistance else {
                continue
            }
            thinned.append(sample)
            lastAcceptedLocation = sampleLocation
            lastAcceptedTimestamp = sample.timestamp
        }

        if let last = samples.last, thinned.last?.id != last.id {
            let distance = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: lastAcceptedLocation)
            if distance >= minimumDistance {
                thinned.append(last)
            }
        }

        return thinned
    }

    private static func decimate(
        _ samples: [DayRouteLocationInput],
        maximumCount: Int
    ) -> [DayRouteLocationInput] {
        guard samples.count > maximumCount, maximumCount > 1 else { return samples }
        let stride = Double(samples.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            samples[Int((Double(index) * stride).rounded())]
        }
    }

    private static func point(for stay: DayRouteStayInput) -> DayRoutePoint {
        DayRoutePoint(
            id: "stay-\(stay.id.uuidString)",
            kind: .stay,
            timestamp: stay.startDate,
            latitude: stay.latitude,
            longitude: stay.longitude
        )
    }

    private static func coordinate(for stay: DayRouteStayInput) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: stay.latitude,
            longitude: stay.longitude
        )
    }

    private static func point(for currentLocation: DayRouteCurrentLocationInput) -> DayRoutePoint {
        DayRoutePoint(
            id: "current-\(currentLocation.lastEvidenceAt.timeIntervalSinceReferenceDate)",
            kind: .currentLocation,
            timestamp: currentLocation.lastEvidenceAt,
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude
        )
    }

    private static func firstIndex(
        after timestamp: Date,
        in evidence: [DayRouteLocationInput]
    ) -> Int {
        var lower = 0
        var upper = evidence.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if evidence[middle].timestamp <= timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func firstIndex(
        atOrAfter timestamp: Date,
        in evidence: [DayRouteLocationInput]
    ) -> Int {
        var lower = 0
        var upper = evidence.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if evidence[middle].timestamp < timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func removeAdjacentDuplicates(_ points: [DayRoutePoint]) -> [DayRoutePoint] {
        var deduplicated: [DayRoutePoint] = []

        for point in points {
            guard let previous = deduplicated.last else {
                deduplicated.append(point)
                continue
            }

            let previousLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
            if previousLocation.distance(from: pointLocation) >= 5 {
                deduplicated.append(point)
            }
        }

        return deduplicated
    }
}
