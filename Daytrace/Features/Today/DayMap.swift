import MapKit
import SwiftUI

struct DayMap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let episodes: [TimelineEpisode]
    let currentLocation: CurrentLocationContext?
    @Binding var selectedEpisodeID: UUID?

    init(
        episodes: [TimelineEpisode],
        currentLocation: CurrentLocationContext? = nil,
        selectedEpisodeID: Binding<UUID?>
    ) {
        self.episodes = episodes
        self.currentLocation = currentLocation
        _selectedEpisodeID = selectedEpisodeID
    }

    @State private var position: MapCameraPosition = .automatic

    private var locatableEpisodes: [TimelineEpisode] {
        episodes.filter { $0.kind == .stay && $0.latitude != nil && $0.longitude != nil }
    }

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(locatableEpisodes) { episode in
                if let latitude = episode.latitude, let longitude = episode.longitude {
                    Annotation(
                        episode.title,
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    ) {
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy) {
                                selectedEpisodeID = episode.id
                            }
                        } label: {
                            DayMapMarker(
                                isSelected: selectedEpisodeID == episode.id,
                                confidence: episode.confidence
                            )
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(episode.title)を選択")
                    }
                }
            }

            if let currentLocation {
                Annotation(
                    "現在地",
                    coordinate: CLLocationCoordinate2D(
                        latitude: currentLocation.latitude,
                        longitude: currentLocation.longitude
                    )
                ) {
                    CurrentLocationMapMarker()
                        .accessibilityLabel("現在地")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: DS.mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: DS.contentCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.contentCornerRadius, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
        }
        .onChange(of: selectedEpisodeID) { _, selectedID in
            focusMap(on: selectedID)
        }
        .sensoryFeedback(.selection, trigger: selectedEpisodeID)
    }

    private func focusMap(on episodeID: UUID?) {
        guard let episodeID,
              let episode = locatableEpisodes.first(where: { $0.id == episodeID }),
              let latitude = episode.latitude,
              let longitude = episode.longitude else {
            return
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 900,
            longitudinalMeters: 900
        )

        withAnimation(reduceMotion ? nil : .snappy) {
            position = .region(region)
        }
    }
}

private struct CurrentLocationMapMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.tint.opacity(0.16))
                .frame(width: 40, height: 40)

            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 25, height: 25)
                .shadow(radius: 3, y: 1)

            Circle()
                .fill(.tint)
                .frame(width: 15, height: 15)
        }
        .frame(width: 44, height: 44)
    }
}

private struct DayMapMarker: View {
    let isSelected: Bool
    let confidence: EpisodeConfidence

    private var outerSize: CGFloat { isSelected ? 34 : 28 }
    private var innerSize: CGFloat { isSelected ? 18 : 14 }
    private var innerColor: Color { confidence == .low ? .secondary : .accentColor }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: outerSize, height: outerSize)
                .shadow(radius: 3, y: 1)

            Circle()
                .fill(innerColor)
                .frame(width: innerSize, height: innerSize)
        }
    }
}
