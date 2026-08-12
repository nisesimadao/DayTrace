import CoreLocation
import Foundation
import SwiftData

@MainActor
struct TimelineEngine {
    static let sourceVersion = 2

    func rebuildRecentTimeline(in context: ModelContext, now: Date = .now) throws {
        let horizon = now.addingTimeInterval(-60 * 60 * 48)

        let visitDescriptor = FetchDescriptor<VisitEvidence>(
            predicate: #Predicate { $0.arrivalDate >= horizon },
            sortBy: [SortDescriptor(\VisitEvidence.arrivalDate)]
        )
        let visits = try context.fetch(visitDescriptor)

        let locationDescriptor = FetchDescriptor<LocationEvidence>(
            predicate: #Predicate { $0.timestamp >= horizon },
            sortBy: [SortDescriptor(\LocationEvidence.timestamp)]
        )
        let locations = try context.fetch(locationDescriptor)

        let episodeDescriptor = FetchDescriptor<TimelineEpisode>(
            predicate: #Predicate { $0.startDate >= horizon }
        )
        let existingEpisodes = try context.fetch(episodeDescriptor)
        let assertions = try context.fetch(FetchDescriptor<UserAssertion>())
        let protectedEpisodeIDs = Set(assertions.compactMap { $0.isActive ? $0.episodeID : nil })

        for episode in existingEpisodes where !protectedEpisodeIDs.contains(episode.id) {
            context.delete(episode)
        }

        let protectedEpisodes = existingEpisodes.filter { protectedEpisodeIDs.contains($0.id) }
        var previousVisit: VisitEvidence?

        for visit in visits {
            if let previousVisit,
               let previousDeparture = previousVisit.departureDate,
               visit.arrivalDate > previousDeparture {
                insertTransition(
                    from: previousVisit,
                    departure: previousDeparture,
                    to: visit,
                    locations: locations,
                    protectedEpisodes: protectedEpisodes,
                    context: context
                )
            }

            let overlapsProtected = protectedEpisodes.contains {
                intervalsOverlap(
                    startA: $0.startDate,
                    endA: $0.endDate,
                    startB: visit.arrivalDate,
                    endB: visit.departureDate
                )
            }

            if !overlapsProtected {
                let resolvedPlace = nearestPlace(to: visit, in: context)
                context.insert(TimelineEpisode(
                    kind: .stay,
                    startDate: visit.arrivalDate,
                    endDate: visit.departureDate,
                    title: resolvedPlace?.name ?? "未設定の場所",
                    subtitle: resolvedPlace == nil ? "場所を確認" : nil,
                    latitude: visit.latitude,
                    longitude: visit.longitude,
                    confidence: resolvedPlace != nil ? .high : (visit.horizontalAccuracy <= 100 ? .medium : .low),
                    placeID: resolvedPlace?.id,
                    sourceVersion: Self.sourceVersion,
                    timeZoneIdentifier: visit.timeZoneIdentifier
                ))
            }

            previousVisit = visit
        }

        applyAssertions(assertions.sorted { $0.createdAt < $1.createdAt }, to: protectedEpisodes)
        try context.save()
    }

    private func insertTransition(
        from previous: VisitEvidence,
        departure: Date,
        to next: VisitEvidence,
        locations: [LocationEvidence],
        protectedEpisodes: [TimelineEpisode],
        context: ModelContext
    ) {
        guard next.arrivalDate.timeIntervalSince(departure) >= 60 else { return }

        let overlapsProtected = protectedEpisodes.contains {
            intervalsOverlap(startA: $0.startDate, endA: $0.endDate, startB: departure, endB: next.arrivalDate)
        }
        guard !overlapsProtected else { return }

        let transitionSamples = locations.filter { $0.timestamp >= departure && $0.timestamp <= next.arrivalDate }
        let kind: EpisodeKind = transitionSamples.isEmpty ? .gap : .move
        let title = kind == .move ? "移動" : "記録のない区間"
        let subtitle = kind == .gap ? "この間の位置情報を確認できませんでした" : nil

        context.insert(TimelineEpisode(
            kind: kind,
            startDate: departure,
            endDate: next.arrivalDate,
            title: title,
            subtitle: subtitle,
            confidence: kind == .move ? .medium : .low,
            sourceVersion: Self.sourceVersion,
            timeZoneIdentifier: next.timeZoneIdentifier
        ))
    }

    private func nearestPlace(to visit: VisitEvidence, in context: ModelContext) -> PlaceRecord? {
        guard let places = try? context.fetch(FetchDescriptor<PlaceRecord>()), !places.isEmpty else { return nil }
        let visitLocation = CLLocation(latitude: visit.latitude, longitude: visit.longitude)

        return places
            .compactMap { place -> (PlaceRecord, CLLocationDistance)? in
                let distance = visitLocation.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
                let allowedDistance = max(place.radius, visit.horizontalAccuracy)
                guard distance <= allowedDistance else { return nil }
                return (place, distance)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func applyAssertions(_ assertions: [UserAssertion], to protectedEpisodes: [TimelineEpisode]) {
        let byID = Dictionary(uniqueKeysWithValues: protectedEpisodes.map { ($0.id, $0) })
        for assertion in assertions where assertion.isActive {
            guard let episodeID = assertion.episodeID, let episode = byID[episodeID] else { continue }
            switch assertion.type {
            case .rename:
                if let title = assertion.replacementTitle { episode.title = title }
            case .retime:
                if let start = assertion.replacementStart { episode.startDate = start }
                if let end = assertion.replacementEnd { episode.endDate = end }
            case .reposition:
                if let latitude = assertion.replacementLatitude { episode.latitude = latitude }
                if let longitude = assertion.replacementLongitude { episode.longitude = longitude }
            case .suppress:
                episode.subtitle = "非表示"
            case .confirm:
                episode.confidence = .high
            case .mergeStay, .splitStay:
                break
            }
        }
    }

    private func intervalsOverlap(startA: Date, endA: Date?, startB: Date, endB: Date?) -> Bool {
        startA < (endB ?? .distantFuture) && (endA ?? .distantFuture) > startB
    }
}
