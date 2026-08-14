import CoreLocation
import Foundation

struct CurrentLocationContext: Equatable {
    let startDate: Date
    let lastEvidenceAt: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timeZoneIdentifier: String
}

@MainActor
enum CurrentLocationProjection {
    private static let freshnessInterval: TimeInterval = 20 * 60
    private static let maximumSampleGap: TimeInterval = 90 * 60
    private static let minimumClusterRadius: CLLocationDistance = 150
    private static let maximumClusterRadius: CLLocationDistance = 500
    private static let maximumUsableAccuracy: CLLocationAccuracy = 1_000

    static func project(
        evidence: [LocationEvidence],
        now: Date = .now,
        dayStart: Date
    ) -> CurrentLocationContext? {
        let usableEvidence = evidence
            .filter {
                $0.timestamp >= dayStart
                    && $0.timestamp <= now.addingTimeInterval(5 * 60)
                    && $0.horizontalAccuracy >= 0
                    && $0.horizontalAccuracy <= maximumUsableAccuracy
            }
            .sorted { $0.timestamp > $1.timestamp }

        guard let latest = usableEvidence.first,
              now.timeIntervalSince(latest.timestamp) <= freshnessInterval else {
            return nil
        }

        let latestLocation = CLLocation(latitude: latest.latitude, longitude: latest.longitude)
        var clusterStart = latest.timestamp
        var newerTimestamp = latest.timestamp

        for sample in usableEvidence.dropFirst() {
            let gap = newerTimestamp.timeIntervalSince(sample.timestamp)
            guard gap >= 0, gap <= maximumSampleGap else { break }

            let sampleLocation = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
            let radius = min(
                max(minimumClusterRadius, latest.horizontalAccuracy + sample.horizontalAccuracy),
                maximumClusterRadius
            )
            guard latestLocation.distance(from: sampleLocation) <= radius else { break }

            clusterStart = sample.timestamp
            newerTimestamp = sample.timestamp
        }

        return CurrentLocationContext(
            startDate: clusterStart,
            lastEvidenceAt: latest.timestamp,
            latitude: latest.latitude,
            longitude: latest.longitude,
            horizontalAccuracy: latest.horizontalAccuracy,
            timeZoneIdentifier: latest.timeZoneIdentifier
        )
    }

    static func placeName(
        for currentLocation: CurrentLocationContext,
        places: [PlaceRecord]
    ) -> String? {
        let location = CLLocation(
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude
        )

        return places
            .compactMap { place -> (name: String, distance: CLLocationDistance)? in
                let distance = location.distance(
                    from: CLLocation(latitude: place.latitude, longitude: place.longitude)
                )
                let allowedDistance = max(place.radius, currentLocation.horizontalAccuracy)
                guard distance <= allowedDistance else { return nil }
                return (place.isPrivate ? "非公開の場所" : place.name, distance)
            }
            .min { $0.distance < $1.distance }?
            .name
    }

    static func matches(
        _ episode: TimelineEpisode,
        currentLocation: CurrentLocationContext
    ) -> Bool {
        guard episode.kind == .stay,
              episode.endDate == nil,
              let latitude = episode.latitude,
              let longitude = episode.longitude else {
            return false
        }

        let distance = CLLocation(
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude
        ).distance(from: CLLocation(latitude: latitude, longitude: longitude))
        let allowedDistance = min(
            max(minimumClusterRadius, currentLocation.horizontalAccuracy),
            maximumClusterRadius
        )
        return distance <= allowedDistance
    }
}
