import MapKit
import SwiftUI

struct DayMap: View {
    let episodes: [TimelineEpisode]
    @Binding var selectedEpisodeID: UUID?

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
                            withAnimation(.snappy) {
                                selectedEpisodeID = episode.id
                            }
                        } label: {
                            DayMapMarker(
                                isSelected: selectedEpisodeID == episode.id,
                                confidence: episode.confidence
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(episode.title)を選択")
                    }
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
