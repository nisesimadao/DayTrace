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
                    Annotation(episode.title, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                        Button {
                            withAnimation(.snappy) {
                                selectedEpisodeID = episode.id
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.background)
                                    .frame(width: selectedEpisodeID == episode.id ? 34 : 28)
                                    .shadow(radius: 3, y: 1)
                                Circle()
                                    .fill(episode.confidence == .low ? .secondary : .tint)
                                    .frame(width: selectedEpisodeID == episode.id ? 18 : 14)
                            }
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
