import MapKit

@MainActor
enum PlaceSearchService {
    static func search(
        query: String,
        near coordinate: CLLocationCoordinate2D
    ) async throws -> [PlaceSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 30_000,
            longitudinalMeters: 30_000
        )
        request.resultTypes = [.address, .pointOfInterest]

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(10).compactMap(makeResult)
    }

    private static func makeResult(from item: MKMapItem) -> PlaceSearchResult? {
        guard let title = cleaned(item.name) else { return nil }
        let coordinate = coordinate(for: item)
        return PlaceSearchResult(
            title: title,
            subtitle: subtitle(for: item),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private static func coordinate(for item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            item.location.coordinate
        } else {
            item.placemark.coordinate
        }
    }

    private static func subtitle(for item: MKMapItem) -> String? {
        if #available(iOS 26.0, *) {
            cleaned(item.address?.shortAddress)
                ?? cleaned(item.addressRepresentations?.fullAddress(
                    includingRegion: false,
                    singleLine: true
                ))
        } else {
            cleaned(item.placemark.title)
        }
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
