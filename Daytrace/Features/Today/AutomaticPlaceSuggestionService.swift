import CoreLocation
import Foundation
import MapKit
import SwiftData

@MainActor
enum AutomaticPlaceSuggestionService {
    private static let recentWindow: TimeInterval = 60 * 60 * 48
    private static let maximumSuggestionsPerPass = 2
    private static let maximumAcceptedDistance: CLLocationDistance = 280
    private static var isAnnotating = false

    static func annotateUnresolvedRecentStays(
        in context: ModelContext,
        now: Date = .now
    ) async {
        guard !isAnnotating else { return }
        isAnnotating = true
        defer { isAnnotating = false }

        let horizon = now.addingTimeInterval(-recentWindow)
        let episodeDescriptor = FetchDescriptor<TimelineEpisode>(
            predicate: #Predicate<TimelineEpisode> { episode in
                episode.startDate >= horizon
            }
        )
        let assertionDescriptor = FetchDescriptor<UserAssertion>(
            predicate: #Predicate<UserAssertion> { assertion in
                assertion.isActive
            }
        )
        guard let episodes = try? context.fetch(episodeDescriptor),
              let assertions = try? context.fetch(assertionDescriptor) else {
            return
        }

        let activeAssertionsByEpisode = activeAssertionsByEpisode(from: assertions)
        let candidates = episodes
            .filter {
                shouldRequestSuggestion(
                    for: $0,
                    activeAssertions: activeAssertionsByEpisode[$0.id] ?? []
                )
            }
            .sorted { $0.startDate > $1.startDate }
            .prefix(maximumSuggestionsPerPass)

        for episode in candidates {
            await annotate(episode, in: context)
        }
    }

    static func shouldRequestSuggestion(
        for episode: TimelineEpisode,
        activeAssertions: [UserAssertion]
    ) -> Bool {
        guard episode.kind == .stay,
              episode.placeID == nil,
              coordinate(for: episode) != nil else {
            return false
        }

        let assertionTypes = Set(activeAssertions.map(\.type))
        guard !assertionTypes.contains(.rename),
              !assertionTypes.contains(.automaticPlaceSuggestion),
              !assertionTypes.contains(.confirm),
              !assertionTypes.contains(.suppress) else {
            return false
        }

        return isPlaceholderTitle(episode.title)
    }

    private static func annotate(
        _ episode: TimelineEpisode,
        in context: ModelContext
    ) async {
        guard let coordinate = coordinate(for: episode),
              let suggestion = await suggestion(near: coordinate) else {
            return
        }

        let episodeID = episode.id
        let descriptor = FetchDescriptor<UserAssertion>(
            predicate: #Predicate<UserAssertion> { assertion in
                assertion.isActive && assertion.episodeID == episodeID
            }
        )
        guard let activeAssertions = try? context.fetch(descriptor) else { return }
        guard shouldRequestSuggestion(for: episode, activeAssertions: activeAssertions) else {
            return
        }

        context.insert(UserAssertion(
            episodeID: episode.id,
            type: .automaticPlaceSuggestion,
            replacementTitle: suggestion.title
        ))
        episode.title = suggestion.title
        episode.subtitle = "近くのスポット候補・確認してください"
        if episode.confidence == .high {
            episode.confidence = .medium
        }
        try? context.save()
    }

    private static func suggestion(near coordinate: CLLocationCoordinate2D) async -> PlaceSearchResult? {
        do {
            let results = try await PlaceSearchService.nearbyPointsOfInterest(
                near: coordinate,
                radius: 420
            )
            return bestResult(from: results, near: coordinate)
        } catch {
            return nil
        }
    }

    private static func bestResult(
        from results: [PlaceSearchResult],
        near coordinate: CLLocationCoordinate2D
    ) -> PlaceSearchResult? {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return results
            .compactMap { result -> (PlaceSearchResult, CLLocationDistance)? in
                guard let resultCoordinate = CLLocationCoordinate2D(
                    latitude: result.latitude,
                    longitude: result.longitude
                ).valid else {
                    return nil
                }
                let distance = origin.distance(
                    from: CLLocation(
                        latitude: resultCoordinate.latitude,
                        longitude: resultCoordinate.longitude
                    )
                )
                guard distance <= maximumAcceptedDistance else {
                    return nil
                }
                return (result, distance)
            }
            .min { lhs, rhs in
                let leftHasSubtitle = lhs.0.subtitle?.isEmpty == false
                let rightHasSubtitle = rhs.0.subtitle?.isEmpty == false
                if leftHasSubtitle != rightHasSubtitle {
                    return leftHasSubtitle
                }
                return lhs.1 < rhs.1
            }?
            .0
    }

    private static func activeAssertionsByEpisode(
        from assertions: [UserAssertion]
    ) -> [UUID: [UserAssertion]] {
        var grouped: [UUID: [UserAssertion]] = [:]
        for assertion in assertions where assertion.isActive {
            guard let episodeID = assertion.episodeID else { continue }
            grouped[episodeID, default: []].append(assertion)
        }
        return grouped
    }

    private static func isPlaceholderTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed == "未設定の場所"
            || trimmed == "推定した停車"
    }

    private static func coordinate(for episode: TimelineEpisode) -> CLLocationCoordinate2D? {
        guard let latitude = episode.latitude,
              let longitude = episode.longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude).valid
    }
}

private extension CLLocationCoordinate2D {
    var valid: CLLocationCoordinate2D? {
        CLLocationCoordinate2DIsValid(self) ? self : nil
    }
}
