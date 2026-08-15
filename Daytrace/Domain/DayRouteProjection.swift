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
        let stays = episodes
            .filter { $0.kind == .stay && $0.latitude != nil && $0.longitude != nil }
            .sorted { $0.startDate < $1.startDate }

        guard let firstStay = stays.first else {
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

        var points: [DayRoutePoint] = [point(for: firstStay)]

        for pair in zip(stays, stays.dropFirst()) {
            if let departure = pair.0.endDate {
                points.append(contentsOf: samples(
                    from: usableSamples,
                    start: departure,
                    end: pair.1.startDate,
                    startCoordinate: coordinate(for: pair.0),
                    options: options
                ))
            }
            points.append(point(for: pair.1))
        }

        if let currentLocation, options.includesCurrentLocationInRoute {
            let lastStay = stays[stays.count - 1]
            let routeStart = lastStay.endDate ?? lastStay.startDate
            points.append(contentsOf: samples(
                from: usableSamples,
                start: routeStart,
                end: currentLocation.lastEvidenceAt,
                startCoordinate: coordinate(for: lastStay),
                options: options
            ))
            points.append(point(for: currentLocation))
        }

        return removeAdjacentDuplicates(points)
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
        from evidence: [LocationEvidence],
        start: Date,
        end: Date,
        startCoordinate: CLLocationCoordinate2D,
        options: Options
    ) -> [DayRoutePoint] {
        guard end > start else { return [] }

        let samples = evidence.filter { $0.timestamp > start && $0.timestamp < end }
        let thinnedSamples = thin(
            samples,
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
        _ samples: [LocationEvidence],
        startCoordinate: CLLocationCoordinate2D,
        minimumInterval: TimeInterval,
        minimumDistance: CLLocationDistance
    ) -> [LocationEvidence] {
        var thinned: [LocationEvidence] = []
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
        _ samples: [LocationEvidence],
        maximumCount: Int
    ) -> [LocationEvidence] {
        guard samples.count > maximumCount, maximumCount > 1 else { return samples }
        let stride = Double(samples.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            samples[Int((Double(index) * stride).rounded())]
        }
    }

    private static func point(for episode: TimelineEpisode) -> DayRoutePoint {
        DayRoutePoint(
            id: "stay-\(episode.id.uuidString)",
            kind: .stay,
            timestamp: episode.startDate,
            latitude: episode.latitude ?? 0,
            longitude: episode.longitude ?? 0
        )
    }

    private static func coordinate(for episode: TimelineEpisode) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: episode.latitude ?? 0,
            longitude: episode.longitude ?? 0
        )
    }

    private static func point(for currentLocation: CurrentLocationContext) -> DayRoutePoint {
        DayRoutePoint(
            id: "current-\(currentLocation.lastEvidenceAt.timeIntervalSinceReferenceDate)",
            kind: .currentLocation,
            timestamp: currentLocation.lastEvidenceAt,
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude
        )
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
