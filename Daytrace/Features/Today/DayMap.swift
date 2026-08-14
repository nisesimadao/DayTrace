import MapKit
import SwiftUI

struct DayMap: View {
    let episodes: [TimelineEpisode]
    let routeLocations: [LocationEvidence]
    let currentLocation: CurrentLocationContext?
    @Binding var selectedEpisodeID: UUID?
    let onExpand: (() -> Void)?

    init(
        episodes: [TimelineEpisode],
        routeLocations: [LocationEvidence] = [],
        currentLocation: CurrentLocationContext? = nil,
        selectedEpisodeID: Binding<UUID?>,
        onExpand: (() -> Void)? = nil
    ) {
        self.episodes = episodes
        self.routeLocations = routeLocations
        self.currentLocation = currentLocation
        _selectedEpisodeID = selectedEpisodeID
        self.onExpand = onExpand
    }

    private var pointCount: Int {
        episodes.count {
            $0.kind == .stay && $0.latitude != nil && $0.longitude != nil
        } + (currentLocation == nil ? 0 : 1)
    }

    private var routeDescription: String {
        let sampleCount = DayRouteProjection.movementSampleCount(
            episodes: episodes,
            locationEvidence: routeLocations,
            currentLocation: currentLocation
        )
        if sampleCount > 0 {
            return "移動中\(sampleCount)点を含む"
        }
        if pointCount >= 2 {
            return "\(pointCount)地点を時系列の直線で表示"
        } else {
            return "記録された地点を表示"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.compactSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Label("足あとマップ", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.headline)

                Spacer()

                Text(routeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            ZStack(alignment: .bottomTrailing) {
                DayMapCanvas(
                    episodes: episodes,
                    routeLocations: routeLocations,
                    currentLocation: currentLocation,
                    selectedEpisodeID: $selectedEpisodeID,
                    interactionModes: onExpand == nil ? [.pan, .zoom] : []
                )
                .allowsHitTesting(onExpand == nil)

                if let onExpand {
                    Button(action: onExpand) {
                        ZStack(alignment: .bottomTrailing) {
                            Color.clear

                            Label("拡大", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(.regularMaterial, in: .capsule)
                                .padding(10)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("足あとマップを拡大")
                    .accessibilityHint("全画面の地図で地点と移動順を確認します")
                }
            }
            .frame(height: DS.mapHeight)
            .clipShape(.rect(cornerRadius: DS.contentCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DS.contentCornerRadius)
                    .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct ExpandedDayMapView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let episodes: [TimelineEpisode]
    let routeLocations: [LocationEvidence]
    let currentLocation: CurrentLocationContext?
    @Binding var selectedEpisodeID: UUID?

    private var selectedEpisode: TimelineEpisode? {
        guard let selectedEpisodeID else { return nil }
        return episodes.first { $0.id == selectedEpisodeID }
    }

    private var selectedPointNumber: Int? {
        guard let selectedEpisodeID else { return nil }
        let locatableEpisodes = episodes
            .filter { $0.kind == .stay && $0.latitude != nil && $0.longitude != nil }
            .sorted { $0.startDate < $1.startDate }
        guard let index = locatableEpisodes.firstIndex(where: { $0.id == selectedEpisodeID }) else {
            return nil
        }
        return index + 1
    }

    private var locatablePointCount: Int {
        episodes.count {
            $0.kind == .stay && $0.latitude != nil && $0.longitude != nil
        } + (currentLocation == nil ? 0 : 1)
    }

    var body: some View {
        NavigationStack {
            DayMapCanvas(
                episodes: episodes,
                routeLocations: routeLocations,
                currentLocation: currentLocation,
                selectedEpisodeID: $selectedEpisodeID,
                interactionModes: [.pan, .zoom]
            )
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                ExpandedMapStatusCard(
                    pointCount: locatablePointCount,
                    selectedEpisode: selectedEpisode,
                    selectedPointNumber: selectedPointNumber
                )
                .padding(.horizontal, DS.horizontalPadding)
                .padding(.bottom, 8)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", systemImage: "xmark", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

private struct ExpandedMapStatusCard: View {
    let pointCount: Int
    let selectedEpisode: TimelineEpisode?
    let selectedPointNumber: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let selectedEpisode {
                if let selectedPointNumber {
                    Label("地図の\(selectedPointNumber)番", systemImage: "mappin.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                }

                Text(selectedEpisode.title)
                    .font(.headline)

                Text(TimelineFormatting.clock(
                    selectedEpisode.startDate,
                    timeZoneIdentifier: selectedEpisode.timeZoneIdentifier
                ))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Label(
                    pointCount >= 2 ? "番号順に、地点間を直線で表示" : "記録された地点を表示",
                    systemImage: "map"
                )
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.cardPadding)
        .daytraceGlassSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct DayMapCanvas: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let episodes: [TimelineEpisode]
    let routeLocations: [LocationEvidence]
    let currentLocation: CurrentLocationContext?
    @Binding var selectedEpisodeID: UUID?
    let interactionModes: MapInteractionModes

    @State private var position: MapCameraPosition = .automatic

    private var locatableEpisodes: [TimelineEpisode] {
        episodes
            .filter { $0.kind == .stay && $0.latitude != nil && $0.longitude != nil }
            .sorted { $0.startDate < $1.startDate }
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        routePoints.map(\.coordinate)
    }

    private var routePoints: [DayRoutePoint] {
        DayRouteProjection.points(
            episodes: episodes,
            locationEvidence: routeLocations,
            currentLocation: currentLocation
        )
    }

    private var movementSamplePoints: [DayRoutePoint] {
        routePoints.filter { $0.kind == .movementSample }
    }

    var body: some View {
        Map(position: $position, interactionModes: interactionModes) {
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates, contourStyle: .straight)
                    .stroke(
                        Color(.systemBackground).opacity(0.82),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )

                MapPolyline(coordinates: routeCoordinates, contourStyle: .straight)
                    .stroke(
                        Color.accentColor.opacity(0.72),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
            }

            ForEach(movementSamplePoints) { point in
                Annotation("移動中の記録", coordinate: point.coordinate) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.58))
                        .frame(width: 7, height: 7)
                        .overlay {
                            Circle()
                                .stroke(Color(.systemBackground).opacity(0.85), lineWidth: 1)
                        }
                        .accessibilityLabel("移動中の位置")
                }
            }

            ForEach(locatableEpisodes.indices, id: \.self) { index in
                let episode = locatableEpisodes[index]
                if let latitude = episode.latitude, let longitude = episode.longitude {
                    Annotation(
                        episode.title,
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    ) {
                        Button {
                            select(episode)
                        } label: {
                            DayMapMarker(
                                index: index + 1,
                                isSelected: selectedEpisodeID == episode.id,
                                confidence: episode.confidence
                            )
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(index + 1)番目、\(episode.title)を選択")
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
                    CurrentLocationMapMarker(index: locatableEpisodes.count + 1)
                        .accessibilityLabel("\(locatableEpisodes.count + 1)番目、現在地")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onChange(of: selectedEpisodeID) { _, selectedID in
            focusMap(on: selectedID)
        }
        .sensoryFeedback(.selection, trigger: selectedEpisodeID)
    }

    private func select(_ episode: TimelineEpisode) {
        withAnimation(reduceMotion ? nil : .snappy) {
            selectedEpisodeID = episode.id
        }
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
    let index: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(.tint.opacity(0.18))
                .frame(width: 40, height: 40)

            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 29, height: 29)
                .shadow(radius: 3, y: 1)

            Text(index, format: .number)
                .font(.caption.bold())
                .foregroundStyle(.tint)
        }
        .frame(width: 44, height: 44)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.tint)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle().stroke(Color(.systemBackground), lineWidth: 2)
                }
        }
    }
}

private struct DayMapMarker: View {
    let index: Int
    let isSelected: Bool
    let confidence: EpisodeConfidence

    private var outerSize: CGFloat { isSelected ? 36 : 31 }
    private var foregroundStyle: Color {
        confidence == .low ? .secondary : .accentColor
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: outerSize, height: outerSize)
                .shadow(radius: 3, y: 1)

            Circle()
                .stroke(foregroundStyle, lineWidth: isSelected ? 3 : 2)
                .frame(width: outerSize - 5, height: outerSize - 5)

            Text(index, format: .number)
                .font(.caption.bold())
                .foregroundStyle(foregroundStyle)
        }
    }
}
