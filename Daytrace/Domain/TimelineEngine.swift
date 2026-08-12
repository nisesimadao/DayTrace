import CoreLocation
import Foundation
import SwiftData

@MainActor
struct TimelineEngine {
    static let sourceVersion = 5
    private static let maximumPlaceResolutionAccuracy: CLLocationAccuracy = 250

    func rebuildRecentTimeline(in context: ModelContext, now: Date = .now) throws {
        let horizon = now.addingTimeInterval(-60 * 60 * 48)

        let allVisits = try context.fetch(FetchDescriptor<VisitEvidence>())
        let visits = allVisits
            .filter { visit in
                guard let arrival = visit.arrivalDate else { return false }
                return arrival >= horizon || (visit.departureDate ?? .distantFuture) >= horizon
            }
            .sorted { visitStart($0) < visitStart($1) }

        let locationDescriptor = FetchDescriptor<LocationEvidence>(
            predicate: #Predicate { $0.timestamp >= horizon },
            sortBy: [SortDescriptor(\LocationEvidence.timestamp)]
        )
        let locations = try context.fetch(locationDescriptor)

        let existingEpisodes = try context.fetch(FetchDescriptor<TimelineEpisode>())
        let assertions = try context.fetch(FetchDescriptor<UserAssertion>()).filter { $0.isActive }
        var assertionsByEpisode: [UUID: [UserAssertion]] = [:]
        for assertion in assertions {
            guard let episodeID = assertion.episodeID else { continue }
            assertionsByEpisode[episodeID, default: []].append(assertion)
        }

        let activeAssertionEpisodeIDs = Set(assertionsByEpisode.keys)
        let suppressedEpisodeIDs = TimelineVisibility.suppressedEpisodeIDs(from: assertions)
        let currentVisitIDs = Set(visits.map(\.id))

        for episode in existingEpisodes where episode.startDate >= horizon && episode.kind != .stay {
            if !activeAssertionEpisodeIDs.contains(episode.id) {
                context.delete(episode)
            }
        }

        for episode in existingEpisodes where episode.startDate >= horizon && episode.kind == .stay {
            guard !activeAssertionEpisodeIDs.contains(episode.id) else { continue }
            if let sourceVisitID = episode.sourceVisitID {
                if !currentVisitIDs.contains(sourceVisitID) {
                    context.delete(episode)
                }
            } else {
                context.delete(episode)
            }
        }

        var stayByVisitID: [UUID: TimelineEpisode] = [:]
        for episode in existingEpisodes where episode.kind == .stay {
            if let sourceVisitID = episode.sourceVisitID {
                stayByVisitID[sourceVisitID] = episode
            }
        }

        for visit in visits {
            guard let arrival = visit.arrivalDate else { continue }
            let resolvedPlace = nearestPlace(to: visit, in: context)
            let inferredTitle = resolvedPlace?.name ?? "未設定の場所"
            let inferredSubtitle = resolvedPlace == nil ? "場所を確認" : nil
            let confidence = inferredConfidence(for: visit, resolvedPlace: resolvedPlace)

            if let episode = stayByVisitID[visit.id] {
                reconcile(
                    episode,
                    with: visit,
                    arrival: arrival,
                    inferredTitle: inferredTitle,
                    inferredSubtitle: inferredSubtitle,
                    inferredConfidence: confidence,
                    resolvedPlace: resolvedPlace,
                    assertions: assertionsByEpisode[episode.id] ?? []
                )
            } else {
                let episode = TimelineEpisode(
                    kind: .stay,
                    startDate: arrival,
                    endDate: visit.departureDate,
                    title: inferredTitle,
                    subtitle: inferredSubtitle,
                    latitude: visit.latitude,
                    longitude: visit.longitude,
                    confidence: confidence,
                    placeID: resolvedPlace?.id,
                    sourceVisitID: visit.id,
                    sourceVersion: Self.sourceVersion,
                    timeZoneIdentifier: visit.timeZoneIdentifier
                )
                context.insert(episode)
                stayByVisitID[visit.id] = episode
            }
        }

        let canonicalStays = stayByVisitID.values
            .filter {
                !suppressedEpisodeIDs.contains($0.id)
                    && ($0.startDate >= horizon || ($0.endDate ?? .distantFuture) >= horizon)
            }
            .sorted { $0.startDate < $1.startDate }

        for pair in zip(canonicalStays, canonicalStays.dropFirst()) {
            guard let departure = pair.0.endDate else { continue }
            let nextArrival = pair.1.startDate
            guard nextArrival.timeIntervalSince(departure) >= 60 else { continue }
            insertTransition(
                departure: departure,
                nextArrival: nextArrival,
                timeZoneIdentifier: pair.1.timeZoneIdentifier,
                locations: locations,
                context: context
            )
        }

        try context.save()
    }

    private func reconcile(
        _ episode: TimelineEpisode,
        with visit: VisitEvidence,
        arrival: Date,
        inferredTitle: String,
        inferredSubtitle: String?,
        inferredConfidence: EpisodeConfidence,
        resolvedPlace: PlaceRecord?,
        assertions: [UserAssertion]
    ) {
        let assertionTypes = Set(assertions.map(\.type))
        let hasLegacyRetime = assertionTypes.contains(.retime)
        let overridesStart = hasLegacyRetime || assertionTypes.contains(.retimeStart)
        let overridesEnd = hasLegacyRetime || assertionTypes.contains(.retimeEnd)

        episode.kind = .stay
        episode.sourceVisitID = visit.id
        episode.sourceVersion = Self.sourceVersion
        episode.timeZoneIdentifier = visit.timeZoneIdentifier

        if !overridesStart {
            episode.startDate = arrival
        }
        if !overridesEnd {
            episode.endDate = visit.departureDate
        }

        if !assertionTypes.contains(.rename) {
            episode.title = inferredTitle
            episode.subtitle = inferredSubtitle
            episode.placeID = resolvedPlace?.id
        }

        if !assertionTypes.contains(.reposition) {
            episode.latitude = visit.latitude
            episode.longitude = visit.longitude
        }

        episode.confidence = assertionTypes.contains(.confirm) ? .high : inferredConfidence

        for assertion in assertions.sorted(by: { $0.createdAt < $1.createdAt }) {
            switch assertion.type {
            case .rename:
                if let title = assertion.replacementTitle { episode.title = title }
            case .retime:
                if let start = assertion.replacementStart { episode.startDate = start }
                episode.endDate = assertion.replacementEnd
            case .retimeStart:
                if let start = assertion.replacementStart { episode.startDate = start }
            case .retimeEnd:
                episode.endDate = assertion.replacementEnd
            case .reposition:
                if let latitude = assertion.replacementLatitude { episode.latitude = latitude }
                if let longitude = assertion.replacementLongitude { episode.longitude = longitude }
            case .confirm:
                episode.confidence = .high
            case .suppress, .mergeStay, .splitStay:
                break
            }
        }
    }

    private func insertTransition(
        departure: Date,
        nextArrival: Date,
        timeZoneIdentifier: String,
        locations: [LocationEvidence],
        context: ModelContext
    ) {
        let transitionSamples = locations.filter { $0.timestamp >= departure && $0.timestamp <= nextArrival }
        let kind: EpisodeKind = transitionSamples.isEmpty ? .gap : .move

        context.insert(TimelineEpisode(
            kind: kind,
            startDate: departure,
            endDate: nextArrival,
            title: kind == .move ? "移動" : "記録のない区間",
            subtitle: kind == .gap ? "この間の位置情報を確認できませんでした" : nil,
            confidence: kind == .move ? .medium : .low,
            sourceVersion: Self.sourceVersion,
            timeZoneIdentifier: timeZoneIdentifier
        ))
    }

    private func nearestPlace(to visit: VisitEvidence, in context: ModelContext) -> PlaceRecord? {
        guard visit.horizontalAccuracy >= 0,
              visit.horizontalAccuracy <= Self.maximumPlaceResolutionAccuracy else {
            return nil
        }
        guard let places = try? context.fetch(FetchDescriptor<PlaceRecord>()), !places.isEmpty else { return nil }
        let visitLocation = CLLocation(latitude: visit.latitude, longitude: visit.longitude)

        return places
            .compactMap { place -> (PlaceRecord, CLLocationDistance)? in
                let distance = visitLocation.distance(
                    from: CLLocation(latitude: place.latitude, longitude: place.longitude)
                )
                let allowedDistance = max(place.radius, visit.horizontalAccuracy)
                guard distance <= allowedDistance else { return nil }
                return (place, distance)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func inferredConfidence(
        for visit: VisitEvidence,
        resolvedPlace: PlaceRecord?
    ) -> EpisodeConfidence {
        guard visit.horizontalAccuracy >= 0 else { return .low }

        if resolvedPlace != nil {
            return visit.horizontalAccuracy <= 75 ? .high : .medium
        }
        return visit.horizontalAccuracy <= 100 ? .medium : .low
    }

    private func visitStart(_ visit: VisitEvidence) -> Date {
        visit.arrivalDate ?? visit.departureDate ?? visit.observedAt
    }
}
