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
            currentLocation: currentLocation,
            options: .preview
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
                    interactionModes: onExpand == nil ? [.pan, .zoom] : [],
                    routeOptions: .preview
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

    @State private var currentLocationFocusRequest = 0

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
                interactionModes: [.pan, .zoom],
                routeOptions: .preview,
                currentLocationFocusRequest: currentLocationFocusRequest
            )
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                ExpandedMapTimelinePanel(
                    pointCount: locatablePointCount,
                    episodes: locatableEpisodes,
                    currentLocation: currentLocation,
                    selectedEpisodeID: selectedEpisodeID,
                    select: select,
                    focusCurrentLocation: focusCurrentLocation
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

    private var locatableEpisodes: [TimelineEpisode] {
        episodes
            .filter { $0.kind == .stay && $0.latitude != nil && $0.longitude != nil }
            .sorted { $0.startDate < $1.startDate }
    }

    private func select(_ episode: TimelineEpisode) {
        selectedEpisodeID = episode.id
    }

    private func focusCurrentLocation() {
        selectedEpisodeID = nil
        currentLocationFocusRequest += 1
    }
}

private struct ExpandedMapTimelinePanel: View {
    let pointCount: Int
    let episodes: [TimelineEpisode]
    let currentLocation: CurrentLocationContext?
    let selectedEpisodeID: UUID?
    let select: (TimelineEpisode) -> Void
    let focusCurrentLocation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                pointCount >= 2 ? "番号順に、地点間を直線で表示" : "記録された地点を表示",
                systemImage: "map"
            )
            .font(.subheadline.weight(.semibold))

            ScrollView {
                LazyVStack(spacing: 8) {
                    if let currentLocation {
                        ExpandedMapCurrentLocationRow(
                            currentLocation: currentLocation,
                            index: episodes.count + 1,
                            action: focusCurrentLocation
                        )
                    }

                    if episodes.isEmpty {
                        Text("タイムラインに地点が入ると、ここから地図を移動できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                            ExpandedMapTimelineRow(
                                index: index + 1,
                                episode: episode,
                                isSelected: selectedEpisodeID == episode.id
                            ) {
                                select(episode)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.cardPadding)
        .daytraceGlassSurface()
    }
}

private struct ExpandedMapCurrentLocationRow: View {
    let currentLocation: CurrentLocationContext
    let index: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CurrentLocationMapMarker(index: index)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text("現在地")
                        .font(.subheadline.weight(.semibold))

                    Text("少なくとも \(TimelineFormatting.clock(currentLocation.startDate, timeZoneIdentifier: currentLocation.timeZoneIdentifier)) から")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("最後に確認 \(TimelineFormatting.clock(currentLocation.lastEvidenceAt, timeZoneIdentifier: currentLocation.timeZoneIdentifier))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                Image(systemName: "scope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("現在地へ移動")
    }
}

private struct ExpandedMapTimelineRow: View {
    let index: Int
    let episode: TimelineEpisode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(index, format: .number)
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? Color(.systemBackground) : Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(TimelineFormatting.clock(
                            episode.startDate,
                            timeZoneIdentifier: episode.timeZoneIdentifier
                        ))
                        .font(.caption.monospacedDigit())

                        if let duration = TimelineFormatting.duration(from: episode.startDate, to: episode.endDate) {
                            Text(duration)
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)

                    if let subtitle = episode.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground).opacity(0.74),
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.48) : Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(index)番目、\(episode.title)へ移動")
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
    let routeOptions: DayRouteProjection.Options
    var currentLocationFocusRequest: Int = 0

    @State private var position: MapCameraPosition = .automatic

    private var locatableEpisodes: [TimelineEpisode] {
        episodes
            .filter { $0.kind == .stay && $0.latitude != nil && $0.longitude != nil }
            .sorted { $0.startDate < $1.startDate }
    }

    private var routeSnapshot: DayRouteSnapshot {
        let routePoints = DayRouteProjection.points(
            episodes: episodes,
            locationEvidence: routeLocations,
            currentLocation: currentLocation,
            options: routeOptions
        )
        return DayRouteSnapshot(points: routePoints)
    }

    var body: some View {
        let route = routeSnapshot

        Map(position: $position, interactionModes: interactionModes) {
            if route.coordinates.count >= 2 {
                MapPolyline(coordinates: route.coordinates, contourStyle: .straight)
                    .stroke(
                        Color(.systemBackground).opacity(0.82),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )

                MapPolyline(coordinates: route.coordinates, contourStyle: .straight)
                    .stroke(
                        Color.accentColor.opacity(0.72),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
            }

            ForEach(route.movementSamplePoints) { point in
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

            ForEach(Array(locatableEpisodes.enumerated()), id: \.element.id) { index, episode in
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
        .transaction { transaction in
            transaction.animation = nil
        }
        .onChange(of: selectedEpisodeID) { _, selectedID in
            focusMap(on: selectedID)
        }
        .onChange(of: currentLocationFocusRequest) { _, _ in
            focusMapOnCurrentLocation()
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

    private func focusMapOnCurrentLocation() {
        guard let currentLocation else { return }

        let coordinate = CLLocationCoordinate2D(
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude
        )
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 1_200,
            longitudinalMeters: 1_200
        )

        withAnimation(reduceMotion ? nil : .snappy) {
            position = .region(region)
        }
    }
}

private struct DayRouteSnapshot {
    let coordinates: [CLLocationCoordinate2D]
    let movementSamplePoints: [DayRoutePoint]

    init(points: [DayRoutePoint]) {
        coordinates = points.map(\.coordinate)
        movementSamplePoints = points.filter { $0.kind == .movementSample }
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
