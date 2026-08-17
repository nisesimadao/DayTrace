import CoreLocation
import Foundation
import SwiftData

@MainActor
struct TimelineEngine {
    static let sourceVersion = 6
    private static let maximumPlaceResolutionAccuracy: CLLocationAccuracy = 250
    private static let inferredStopMinimumSampleCount = 3
    private static let inferredStopMaximumSampleGap: TimeInterval = 12 * 60
    private static let inferredStopMaximumAverageSpeed: CLLocationSpeed = 2.2

    func rebuildRecentTimeline(
        in context: ModelContext,
        now: Date = .now,
        trackingSensitivity: TrackingSensitivity = .current
    ) throws {
        let horizon = now.addingTimeInterval(-60 * 60 * 48)

        let locationDescriptor = FetchDescriptor<LocationEvidence>(
            predicate: #Predicate { $0.timestamp >= horizon },
            sortBy: [SortDescriptor(\LocationEvidence.timestamp)]
        )
        let locations = try context.fetch(locationDescriptor)
        try reconcileInferredStops(
            from: locations,
            horizon: horizon,
            trackingSensitivity: trackingSensitivity,
            in: context
        )

        let allVisits = try context.fetch(FetchDescriptor<VisitEvidence>())
        let inferredArrivalsByVisitID = inferredDepartureOnlyArrivals(
            for: allVisits,
            locations: locations,
            horizon: horizon
        )
        let visits = allVisits
            .filter { visit in
                guard let arrival = visit.arrivalDate ?? inferredArrivalsByVisitID[visit.id] else { return false }
                return arrival >= horizon || (visit.departureDate ?? .distantFuture) >= horizon
            }
            .sorted {
                visitStart($0, inferredArrivalsByVisitID: inferredArrivalsByVisitID)
                    < visitStart($1, inferredArrivalsByVisitID: inferredArrivalsByVisitID)
            }

        let existingEpisodes = try context.fetch(FetchDescriptor<TimelineEpisode>())
        let assertions = try context.fetch(FetchDescriptor<UserAssertion>()).filter { $0.isActive }
        var assertionsByEpisode: [UUID: [UserAssertion]] = [:]
        for assertion in assertions {
            guard let episodeID = assertion.episodeID else { continue }
            assertionsByEpisode[episodeID, default: []].append(assertion)
        }

        let activeAssertionEpisodeIDs = Set(assertionsByEpisode.keys)
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
            guard let arrival = visit.arrivalDate ?? inferredArrivalsByVisitID[visit.id] else { continue }

            if let episode = stayByVisitID[visit.id] {
                let visitPlace = nearestPlace(to: visit, in: context)
                let startLocation = representativeStartLocation(
                    for: episode,
                    visit: visit,
                    locations: locations
                )
                let startPlace = startLocation.flatMap { nearestPlace(to: $0, in: context) }
                let resolvedPlace = visitPlace
                    ?? startPlace
                    ?? preservedExistingPlace(for: episode, visit: visit, in: context)
                let inferredTitle = resolvedPlace?.name ?? title(for: visit)
                let inferredSubtitle = subtitle(for: visit, resolvedPlace: resolvedPlace)
                let confidence = inferredConfidence(for: visit, resolvedPlace: resolvedPlace)

                reconcile(
                    episode,
                    with: visit,
                    arrival: arrival,
                    inferredTitle: inferredTitle,
                    inferredSubtitle: inferredSubtitle,
                    inferredConfidence: confidence,
                    resolvedPlace: resolvedPlace,
                    coordinateOverride: coordinateOverride(
                        for: episode,
                        visit: visit,
                        resolvedPlace: resolvedPlace,
                        startLocation: startLocation,
                        didResolveFromStartLocation: visitPlace == nil && startPlace != nil
                    ),
                    assertions: assertionsByEpisode[episode.id] ?? []
                )
            } else {
                let resolvedPlace = nearestPlace(to: visit, in: context)
                let inferredTitle = resolvedPlace?.name ?? title(for: visit)
                let inferredSubtitle = subtitle(for: visit, resolvedPlace: resolvedPlace)
                let confidence = inferredConfidence(for: visit, resolvedPlace: resolvedPlace)

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
            .filter { $0.startDate >= horizon || ($0.endDate ?? .distantFuture) >= horizon }
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

    func rebuildTransitions(covering interval: DateInterval, in context: ModelContext) throws {
        let existingEpisodes = try context.fetch(FetchDescriptor<TimelineEpisode>())
        let assertions = try context.fetch(FetchDescriptor<UserAssertion>()).filter { $0.isActive }
        let protectedEpisodeIDs = Set(assertions.compactMap(\.episodeID))

        for episode in existingEpisodes where episode.kind != .stay {
            guard !protectedEpisodeIDs.contains(episode.id) else { continue }
            let episodeEnd = episode.endDate ?? episode.startDate
            if episode.startDate <= interval.end && episodeEnd >= interval.start {
                context.delete(episode)
            }
        }

        // Suppression is a presentation concern. Hidden stays still define the
        // canonical transition boundaries so rebuilding cannot bridge across
        // them or rewrite the movement history on either side.
        let canonicalStays = existingEpisodes
            .filter { $0.kind == .stay }
            .sorted { $0.startDate < $1.startDate }

        for pair in zip(canonicalStays, canonicalStays.dropFirst()) {
            guard let departure = pair.0.endDate else { continue }
            let nextArrival = pair.1.startDate
            guard nextArrival.timeIntervalSince(departure) >= 60 else { continue }
            guard departure <= interval.end && nextArrival >= interval.start else { continue }

            let protectedTransitionExists = existingEpisodes.contains { episode in
                guard episode.kind != .stay, protectedEpisodeIDs.contains(episode.id) else { return false }
                let episodeEnd = episode.endDate ?? episode.startDate
                return episode.startDate <= nextArrival && episodeEnd >= departure
            }
            guard !protectedTransitionExists else { continue }

            let transitionStart = departure
            let transitionEnd = nextArrival
            let descriptor = FetchDescriptor<LocationEvidence>(
                predicate: #Predicate {
                    $0.timestamp >= transitionStart && $0.timestamp <= transitionEnd
                },
                sortBy: [SortDescriptor(\LocationEvidence.timestamp)]
            )
            let locations = try context.fetch(descriptor)

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
        coordinateOverride: CLLocationCoordinate2D?,
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
            // Core Location can revise a visit's arrival forward after first
            // delivery, so keep the earliest known value by default. Once the
            // user edits only the departure, however, the untouched arrival
            // remains automatic and should track the latest visit evidence.
            episode.startDate = overridesEnd ? arrival : min(episode.startDate, arrival)
        }
        if !overridesEnd {
            episode.endDate = visit.departureDate
        }

        if !assertionTypes.contains(.rename) && !assertionTypes.contains(.reposition) {
            episode.title = inferredTitle
            episode.subtitle = inferredSubtitle
            episode.placeID = resolvedPlace?.id
        }

        if !assertionTypes.contains(.reposition) {
            if let coordinateOverride {
                episode.latitude = coordinateOverride.latitude
                episode.longitude = coordinateOverride.longitude
            } else {
                episode.latitude = visit.latitude
                episode.longitude = visit.longitude
            }
        }

        if assertionTypes.contains(.confirm) {
            episode.confidence = .high
        } else if !assertionTypes.contains(.reposition) {
            episode.confidence = inferredConfidence
        }

        for assertion in assertions.sorted(by: { $0.createdAt < $1.createdAt }) {
            switch assertion.type {
            case .rename:
                if let title = assertion.replacementTitle { episode.title = title }
            case .automaticPlaceSuggestion:
                if !assertionTypes.contains(.rename),
                   resolvedPlace == nil,
                   let title = assertion.replacementTitle {
                    episode.title = title
                    if episode.subtitle == "場所を確認" {
                        episode.subtitle = "近くのスポット候補・確認してください"
                    }
                }
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
        let hasTransitionSample = locations.contains {
                $0.timestamp >= departure
                    && $0.timestamp <= nextArrival
                    && $0.horizontalAccuracy >= 0
                    && $0.horizontalAccuracy <= 1_000
                    && ($0.source == .standardLocation || $0.source == .significantChange)
        }

        guard hasTransitionSample else {
            insertTransitionEpisode(
                kind: .gap,
                startDate: departure,
                endDate: nextArrival,
                timeZoneIdentifier: timeZoneIdentifier,
                context: context
            )
            return
        }

        // A location sample proves that movement happened somewhere in the
        // stay-to-stay interval; it does not prove that movement began at the
        // sample timestamp. The visit departure and next arrival remain the
        // authoritative boundaries for the diary-facing duration.
        insertTransitionEpisode(
            kind: .move,
            startDate: departure,
            endDate: nextArrival,
            timeZoneIdentifier: timeZoneIdentifier,
            context: context
        )
    }

    private func insertTransitionEpisode(
        kind: EpisodeKind,
        startDate: Date,
        endDate: Date,
        timeZoneIdentifier: String,
        context: ModelContext
    ) {
        guard endDate.timeIntervalSince(startDate) >= 60 else { return }
        context.insert(TimelineEpisode(
            kind: kind,
            startDate: startDate,
            endDate: endDate,
            title: kind == .move ? "移動" : "記録のない区間",
            subtitle: kind == .gap ? "この間の位置情報を確認できませんでした" : nil,
            confidence: kind == .move ? .medium : .low,
            sourceVersion: Self.sourceVersion,
            timeZoneIdentifier: timeZoneIdentifier
        ))
    }

    private func reconcileInferredStops(
        from locations: [LocationEvidence],
        horizon: Date,
        trackingSensitivity: TrackingSensitivity,
        in context: ModelContext
    ) throws {
        guard let minimumDuration = trackingSensitivity.inferredStopMinimumDuration else {
            try deleteInferredVisits(since: horizon, in: context)
            return
        }

        let candidates = inferredStopCandidates(
            from: locations,
            minimumDuration: minimumDuration,
            radius: trackingSensitivity.inferredStopRadius,
            maximumAccuracy: trackingSensitivity.inferredStopMaximumAccuracy
        )

        let existingVisits = try context.fetch(FetchDescriptor<VisitEvidence>())
        let realVisits = existingVisits.filter { $0.source != .inferredStop }
        let inferredVisits = existingVisits.filter {
            $0.source == .inferredStop
                && (($0.arrivalDate ?? $0.observedAt) >= horizon
                    || ($0.departureDate ?? .distantFuture) >= horizon)
        }

        var matchedVisitIDs = Set<UUID>()
        for candidate in candidates where !overlapsRealVisit(candidate, realVisits: realVisits) {
            if let match = matchingInferredVisit(for: candidate, in: inferredVisits, excluding: matchedVisitIDs) {
                match.arrivalDate = candidate.arrival
                match.departureDate = candidate.departure
                match.observedAt = candidate.observedAt
                match.latitude = candidate.latitude
                match.longitude = candidate.longitude
                match.horizontalAccuracy = candidate.horizontalAccuracy
                match.timeZoneIdentifier = candidate.timeZoneIdentifier
                match.source = .inferredStop
                matchedVisitIDs.insert(match.id)
            } else {
                context.insert(VisitEvidence(
                    arrivalDate: candidate.arrival,
                    departureDate: candidate.departure,
                    observedAt: candidate.observedAt,
                    latitude: candidate.latitude,
                    longitude: candidate.longitude,
                    horizontalAccuracy: candidate.horizontalAccuracy,
                    timeZoneIdentifier: candidate.timeZoneIdentifier,
                    source: .inferredStop
                ))
            }
        }

        for visit in inferredVisits where !matchedVisitIDs.contains(visit.id) {
            context.delete(visit)
        }
    }

    private func deleteInferredVisits(since horizon: Date, in context: ModelContext) throws {
        let visits = try context.fetch(FetchDescriptor<VisitEvidence>())
        for visit in visits where visit.source == .inferredStop {
            let evidenceDate = visit.departureDate ?? visit.arrivalDate ?? visit.observedAt
            if evidenceDate >= horizon {
                context.delete(visit)
            }
        }
    }

    private struct InferredStopCandidate {
        var arrival: Date
        var departure: Date
        var observedAt: Date
        var latitude: Double
        var longitude: Double
        var horizontalAccuracy: Double
        var timeZoneIdentifier: String
    }

    private func inferredStopCandidates(
        from locations: [LocationEvidence],
        minimumDuration: TimeInterval,
        radius: CLLocationDistance,
        maximumAccuracy: CLLocationAccuracy
    ) -> [InferredStopCandidate] {
        let usableLocations = locations
            .filter {
                $0.horizontalAccuracy >= 0
                    && $0.horizontalAccuracy <= maximumAccuracy
                    && ($0.source == .standardLocation || $0.source == .significantChange)
            }
            .sorted { $0.timestamp < $1.timestamp }

        var candidates: [InferredStopCandidate] = []
        var cluster: [LocationEvidence] = []

        func finishCluster() {
            guard let candidate = candidate(from: cluster, minimumDuration: minimumDuration, radius: radius) else {
                return
            }
            candidates.append(candidate)
        }

        for location in usableLocations {
            guard let previous = cluster.last else {
                cluster = [location]
                continue
            }

            let gap = location.timestamp.timeIntervalSince(previous.timestamp)
            let center = centroid(of: cluster)
            let distance = CLLocation(latitude: location.latitude, longitude: location.longitude)
                .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))

            if gap <= Self.inferredStopMaximumSampleGap && distance <= radius {
                cluster.append(location)
            } else {
                finishCluster()
                cluster = [location]
            }
        }

        finishCluster()
        return candidates
    }

    private func candidate(
        from cluster: [LocationEvidence],
        minimumDuration: TimeInterval,
        radius: CLLocationDistance
    ) -> InferredStopCandidate? {
        guard cluster.count >= Self.inferredStopMinimumSampleCount,
              let first = cluster.first,
              let last = cluster.last else {
            return nil
        }

        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        guard duration >= minimumDuration else { return nil }

        let center = centroid(of: cluster)
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let maximumDistance = cluster
            .map { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: centerLocation) }
            .max() ?? 0
        guard maximumDistance <= radius else { return nil }

        let speeds = cluster.map(\.speed).filter { $0 >= 0 }
        if !speeds.isEmpty {
            let averageSpeed = speeds.reduce(0, +) / Double(speeds.count)
            guard averageSpeed <= Self.inferredStopMaximumAverageSpeed else { return nil }
        }

        return InferredStopCandidate(
            arrival: first.timestamp,
            departure: last.timestamp,
            observedAt: last.timestamp,
            latitude: center.latitude,
            longitude: center.longitude,
            horizontalAccuracy: min(cluster.map(\.horizontalAccuracy).max() ?? 100, radius),
            timeZoneIdentifier: first.timeZoneIdentifier
        )
    }

    private func centroid(of locations: [LocationEvidence]) -> (latitude: Double, longitude: Double) {
        guard !locations.isEmpty else { return (0, 0) }
        let latitude = locations.map(\.latitude).reduce(0, +) / Double(locations.count)
        let longitude = locations.map(\.longitude).reduce(0, +) / Double(locations.count)
        return (latitude, longitude)
    }

    private func overlapsRealVisit(_ candidate: InferredStopCandidate, realVisits: [VisitEvidence]) -> Bool {
        let candidateLocation = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        return realVisits.contains { visit in
            guard let arrival = visit.arrivalDate else { return false }
            let departure = visit.departureDate ?? candidate.departure
            guard arrival <= candidate.departure && departure >= candidate.arrival else { return false }

            let visitLocation = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
            let allowance = max(250, max(visit.horizontalAccuracy, candidate.horizontalAccuracy))
            return candidateLocation.distance(from: visitLocation) <= allowance
        }
    }

    private func matchingInferredVisit(
        for candidate: InferredStopCandidate,
        in visits: [VisitEvidence],
        excluding matchedVisitIDs: Set<UUID>
    ) -> VisitEvidence? {
        let candidateLocation = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        return visits
            .filter { !matchedVisitIDs.contains($0.id) }
            .compactMap { visit -> (VisitEvidence, Double)? in
                guard let arrival = visit.arrivalDate else { return nil }
                let arrivalDelta = abs(arrival.timeIntervalSince(candidate.arrival))
                guard arrivalDelta <= 5 * 60 else { return nil }

                let visitLocation = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
                let distance = candidateLocation.distance(from: visitLocation)
                guard distance <= max(250, candidate.horizontalAccuracy) else { return nil }
                return (visit, arrivalDelta + distance / 100)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func nearestPlace(to visit: VisitEvidence, in context: ModelContext) -> PlaceRecord? {
        guard visit.horizontalAccuracy >= 0,
              visit.horizontalAccuracy <= Self.maximumPlaceResolutionAccuracy else {
            return nil
        }
        return nearestPlace(
            latitude: visit.latitude,
            longitude: visit.longitude,
            horizontalAccuracy: visit.horizontalAccuracy,
            in: context
        )
    }

    private func nearestPlace(to location: LocationEvidence, in context: ModelContext) -> PlaceRecord? {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maximumPlaceResolutionAccuracy else {
            return nil
        }
        return nearestPlace(
            latitude: location.latitude,
            longitude: location.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            in: context
        )
    }

    private func nearestPlace(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: CLLocationAccuracy,
        in context: ModelContext
    ) -> PlaceRecord? {
        guard let places = try? context.fetch(FetchDescriptor<PlaceRecord>()), !places.isEmpty else { return nil }
        let location = CLLocation(latitude: latitude, longitude: longitude)

        return places
            .compactMap { place -> (PlaceRecord, CLLocationDistance)? in
                let distance = location.distance(
                    from: CLLocation(latitude: place.latitude, longitude: place.longitude)
                )
                let allowedDistance = max(place.radius, horizontalAccuracy)
                guard distance <= allowedDistance else { return nil }
                return (place, distance)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func preservedExistingPlace(
        for episode: TimelineEpisode,
        visit: VisitEvidence,
        in context: ModelContext
    ) -> PlaceRecord? {
        guard let placeID = episode.placeID,
              let places = try? context.fetch(FetchDescriptor<PlaceRecord>()),
              let place = places.first(where: { $0.id == placeID }) else {
            return nil
        }

        let distance = CLLocation(latitude: visit.latitude, longitude: visit.longitude).distance(
            from: CLLocation(latitude: place.latitude, longitude: place.longitude)
        )
        let accuracyAllowance: CLLocationDistance
        if visit.horizontalAccuracy >= 0 {
            accuracyAllowance = min(max(visit.horizontalAccuracy, Self.maximumPlaceResolutionAccuracy), 1_000)
        } else {
            accuracyAllowance = Self.maximumPlaceResolutionAccuracy
        }

        guard distance <= max(place.radius, accuracyAllowance) else {
            return nil
        }
        return place
    }

    private func coordinateOverride(
        for episode: TimelineEpisode,
        visit: VisitEvidence,
        resolvedPlace: PlaceRecord?,
        startLocation: LocationEvidence?,
        didResolveFromStartLocation: Bool
    ) -> CLLocationCoordinate2D? {
        if didResolveFromStartLocation, let resolvedPlace {
            return CLLocationCoordinate2D(
                latitude: resolvedPlace.latitude,
                longitude: resolvedPlace.longitude
            )
        }

        if let startLocation,
           visit.horizontalAccuracy < 0 || visit.horizontalAccuracy > Self.maximumPlaceResolutionAccuracy {
            return CLLocationCoordinate2D(
                latitude: startLocation.latitude,
                longitude: startLocation.longitude
            )
        }

        guard episode.placeID != nil,
              resolvedPlace?.id == episode.placeID,
              visit.horizontalAccuracy < 0 || visit.horizontalAccuracy > Self.maximumPlaceResolutionAccuracy else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: resolvedPlace?.latitude ?? episode.latitude ?? visit.latitude,
            longitude: resolvedPlace?.longitude ?? episode.longitude ?? visit.longitude
        )
    }

    private func representativeStartLocation(
        for episode: TimelineEpisode,
        visit: VisitEvidence,
        locations: [LocationEvidence]
    ) -> LocationEvidence? {
        guard visit.horizontalAccuracy < 0 || visit.horizontalAccuracy > Self.maximumPlaceResolutionAccuracy else {
            return nil
        }

        let start = min(episode.startDate, visit.arrivalDate ?? episode.startDate)
        let end = min(
            start.addingTimeInterval(45 * 60),
            visit.departureDate ?? start.addingTimeInterval(45 * 60)
        )
        let candidates = locations.filter {
            $0.timestamp >= start
                && $0.timestamp <= end
                && $0.horizontalAccuracy >= 0
                && $0.horizontalAccuracy <= Self.maximumPlaceResolutionAccuracy
        }

        return candidates.min {
            if $0.horizontalAccuracy == $1.horizontalAccuracy {
                return $0.timestamp < $1.timestamp
            }
            return $0.horizontalAccuracy < $1.horizontalAccuracy
        }
    }

    private func inferredConfidence(
        for visit: VisitEvidence,
        resolvedPlace: PlaceRecord?
    ) -> EpisodeConfidence {
        if visit.source == .inferredStop {
            return .low
        }

        guard visit.horizontalAccuracy >= 0 else { return .low }

        if resolvedPlace != nil {
            return visit.horizontalAccuracy <= 75 ? .high : .medium
        }
        return visit.horizontalAccuracy <= 100 ? .medium : .low
    }

    private func visitStart(_ visit: VisitEvidence) -> Date {
        visit.arrivalDate ?? visit.departureDate ?? visit.observedAt
    }

    private func visitStart(
        _ visit: VisitEvidence,
        inferredArrivalsByVisitID: [UUID: Date]
    ) -> Date {
        visit.arrivalDate ?? inferredArrivalsByVisitID[visit.id] ?? visit.departureDate ?? visit.observedAt
    }

    private func inferredDepartureOnlyArrivals(
        for visits: [VisitEvidence],
        locations: [LocationEvidence],
        horizon: Date
    ) -> [UUID: Date] {
        var arrivals: [UUID: Date] = [:]

        for visit in visits {
            guard visit.arrivalDate == nil,
                  let departure = visit.departureDate else {
                continue
            }

            let lookbackStart = max(horizon, departure.addingTimeInterval(-12 * 60 * 60))
            let visitLocation = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
            let candidates = locations.filter { location in
                guard location.timestamp >= lookbackStart,
                      location.timestamp <= departure,
                      location.horizontalAccuracy >= 0,
                      location.horizontalAccuracy <= Self.maximumPlaceResolutionAccuracy,
                      location.source == .standardLocation || location.source == .significantChange else {
                    return false
                }

                let locationPoint = CLLocation(latitude: location.latitude, longitude: location.longitude)
                let allowance = max(
                    Self.maximumPlaceResolutionAccuracy,
                    max(visit.horizontalAccuracy, location.horizontalAccuracy)
                )
                return visitLocation.distance(from: locationPoint) <= allowance
            }

            if let first = candidates.min(by: { $0.timestamp < $1.timestamp }) {
                arrivals[visit.id] = first.timestamp
            }
        }

        return arrivals
    }

    private func title(for visit: VisitEvidence) -> String {
        switch visit.source {
        case .inferredStop:
            "推定した停車"
        default:
            "未設定の場所"
        }
    }

    private func subtitle(for visit: VisitEvidence, resolvedPlace: PlaceRecord?) -> String? {
        if resolvedPlace != nil {
            return visit.source == .inferredStop ? "位置サンプルから推定" : nil
        }

        return switch visit.source {
        case .inferredStop:
            "位置サンプルから推定・確認してください"
        default:
            "場所を確認"
        }
    }
}
