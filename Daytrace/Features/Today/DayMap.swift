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
        if !routeLocations.isEmpty {
            return "移動中の記録を間引いて表示"
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
                    interactionModes: [.pan, .zoom],
                    routeOptions: .preview,
                    visualStyle: .compactCard
                )
                .equatable()
                .simultaneousGesture(
                    TapGesture(count: 1).onEnded {
                        onExpand?()
                    }
                )

                if let onExpand {
                    Button(action: onExpand) {
                        Label("拡大", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.daytraceInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.regularMaterial, in: .capsule)
                            .overlay {
                                Capsule()
                                    .stroke(Color.daytraceInk.opacity(0.16), lineWidth: 1)
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
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
    let onRegisterCurrentLocation: (() -> Void)?

    @State private var currentLocationFocusRequest = 0

    init(
        title: String,
        episodes: [TimelineEpisode],
        routeLocations: [LocationEvidence],
        currentLocation: CurrentLocationContext?,
        selectedEpisodeID: Binding<UUID?>,
        onRegisterCurrentLocation: (() -> Void)? = nil
    ) {
        self.title = title
        self.episodes = episodes
        self.routeLocations = routeLocations
        self.currentLocation = currentLocation
        _selectedEpisodeID = selectedEpisodeID
        self.onRegisterCurrentLocation = onRegisterCurrentLocation
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
                interactionModes: [.pan, .zoom],
                routeOptions: .preview,
                visualStyle: .expanded,
                currentLocationFocusRequest: currentLocationFocusRequest
            )
            .equatable()
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                ExpandedMapTimelinePanel(
                    pointCount: locatablePointCount,
                    episodes: locatableEpisodes,
                    currentLocation: currentLocation,
                    selectedEpisodeID: selectedEpisodeID,
                    select: select,
                    focusCurrentLocation: focusCurrentLocation,
                    registerCurrentLocation: onRegisterCurrentLocation
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
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
    let registerCurrentLocation: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    pointCount >= 2 ? "タイムライン順" : "記録された地点",
                    systemImage: "map"
                )
                .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(pointCount)地点")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
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

                    if let currentLocation {
                        if !episodes.isEmpty {
                            Divider()
                                .padding(.leading, 48)
                        }

                        ExpandedMapCurrentLocationRow(
                            currentLocation: currentLocation,
                            index: episodes.count + 1,
                            focus: focusCurrentLocation,
                            register: registerCurrentLocation
                        )
                    }
                }
            }
            .frame(maxHeight: 236)
            .scrollContentBackground(.hidden)
            .background(.thinMaterial, in: .rect(cornerRadius: DS.controlCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DS.controlCornerRadius)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .daytraceGlassSurface(tint: Color(.systemBackground).opacity(0.18))
    }
}

private struct ExpandedMapCurrentLocationRow: View {
    let currentLocation: CurrentLocationContext
    let index: Int
    let focus: () -> Void
    let register: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(index, format: .number)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color(.tertiarySystemGroupedBackground), in: .circle)

            VStack(alignment: .leading, spacing: 8) {
                Button(action: focus) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(TimelineFormatting.clock(
                            currentLocation.startDate,
                            timeZoneIdentifier: currentLocation.timeZoneIdentifier
                        ))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                        Text("現在地")
                            .font(.subheadline.weight(.semibold))

                        Spacer(minLength: 8)

                        Image(systemName: "scope")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text("少なくとも \(TimelineFormatting.clock(currentLocation.startDate, timeZoneIdentifier: currentLocation.timeZoneIdentifier)) から")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("最後に確認 \(TimelineFormatting.clock(currentLocation.lastEvidenceAt, timeZoneIdentifier: currentLocation.timeZoneIdentifier))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                if let register {
                    Button(action: register) {
                        Label("ここを滞在として登録", systemImage: "plus.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.primary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
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
            HStack(alignment: .top, spacing: 12) {
                Text(index, format: .number)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemGroupedBackground), in: .circle)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(TimelineFormatting.clock(
                            episode.startDate,
                            timeZoneIdentifier: episode.timeZoneIdentifier
                        ))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                        Text(episode.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if let duration = TimelineFormatting.duration(from: episode.startDate, to: episode.endDate) {
                            Text(duration)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let subtitle = episode.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.daytraceInk : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(isSelected ? Color.daytraceInk : .clear)
                    .frame(width: 3, height: 28)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(index)番目、\(episode.title)へ移動")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityElement(children: .combine)
    }
}

private struct DayMapCanvas: View, Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let stayPoints: [DayMapStayPoint]
    let routeLocations: [DayMapRouteLocation]
    let currentLocation: DayMapCurrentLocation?
    let selectedEpisodeSnapshotID: UUID?
    @Binding var selectedEpisodeID: UUID?
    let interactionModes: MapInteractionModes
    let routeOptions: DayRouteProjection.Options
    let visualStyle: DayMapVisualStyle
    var currentLocationFocusRequest: Int = 0

    @State private var position: MapCameraPosition = .automatic
    @State private var hasInitializedCamera = false

    init(
        episodes: [TimelineEpisode],
        routeLocations: [LocationEvidence],
        currentLocation: CurrentLocationContext?,
        selectedEpisodeID: Binding<UUID?>,
        interactionModes: MapInteractionModes,
        routeOptions: DayRouteProjection.Options,
        visualStyle: DayMapVisualStyle = .expanded,
        currentLocationFocusRequest: Int = 0
    ) {
        stayPoints = episodes
            .compactMap(DayMapStayPoint.init)
            .sorted { $0.startDate < $1.startDate }
        self.routeLocations = routeLocations
            .map(DayMapRouteLocation.init)
            .sorted { $0.timestamp < $1.timestamp }
        self.currentLocation = currentLocation.map(DayMapCurrentLocation.init)
        selectedEpisodeSnapshotID = selectedEpisodeID.wrappedValue
        _selectedEpisodeID = selectedEpisodeID
        self.interactionModes = interactionModes
        self.routeOptions = routeOptions
        self.visualStyle = visualStyle
        self.currentLocationFocusRequest = currentLocationFocusRequest
    }

    nonisolated static func == (lhs: DayMapCanvas, rhs: DayMapCanvas) -> Bool {
        lhs.stayPoints == rhs.stayPoints
            && lhs.routeLocations == rhs.routeLocations
            && lhs.currentLocation == rhs.currentLocation
            && lhs.selectedEpisodeSnapshotID == rhs.selectedEpisodeSnapshotID
            && lhs.routeOptions == rhs.routeOptions
            && lhs.visualStyle == rhs.visualStyle
            && lhs.currentLocationFocusRequest == rhs.currentLocationFocusRequest
    }

    private var routeSnapshot: DayRouteSnapshot {
        DayRouteSnapshot(points: routePoints())
    }

    var body: some View {
        let route = routeSnapshot

        Map(position: $position, interactionModes: interactionModes) {
            if route.coordinates.count >= 2 {
                MapPolyline(coordinates: route.coordinates, contourStyle: .straight)
                    .stroke(
                        visualStyle.routeHaloColor,
                        style: StrokeStyle(lineWidth: visualStyle.routeHaloWidth, lineCap: .round, lineJoin: .round)
                    )

                MapPolyline(coordinates: route.coordinates, contourStyle: .straight)
                    .stroke(
                        visualStyle.routeColor,
                        style: StrokeStyle(lineWidth: visualStyle.routeWidth, lineCap: .round, lineJoin: .round)
                    )
            }

            ForEach(visibleMovementSamplePoints(in: route)) { point in
                Annotation("移動中の記録", coordinate: point.coordinate) {
                    Circle()
                        .fill(visualStyle.movementSampleColor)
                        .frame(width: visualStyle.movementSampleSize, height: visualStyle.movementSampleSize)
                        .overlay {
                            Circle()
                                .stroke(visualStyle.markerBackgroundColor.opacity(0.72), lineWidth: 0.75)
                        }
                        .allowsHitTesting(false)
                        .zIndex(0)
                        .accessibilityLabel("移動中の位置")
                }
            }

            ForEach(Array(stayPoints.enumerated()), id: \.element.id) { index, point in
                Annotation(
                    point.title,
                    coordinate: point.coordinate
                ) {
                    Button {
                        select(point)
                    } label: {
                        DayMapMarker(
                            index: index + 1,
                            isSelected: selectedEpisodeID == point.id,
                            confidence: point.confidence,
                            visualStyle: visualStyle
                        )
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .zIndex(selectedEpisodeID == point.id ? 2_000 : 1_000 + Double(index))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(index + 1)番目、\(point.title)を選択")
                }
            }

            if let currentLocation {
                Annotation(
                    "現在地",
                    coordinate: currentLocation.coordinate
                ) {
                    CurrentLocationMapMarker(index: stayPoints.count + 1, visualStyle: visualStyle)
                        .zIndex(3_000)
                        .accessibilityLabel("\(stayPoints.count + 1)番目、現在地")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            initializeCameraIfNeeded()
        }
        .onChange(of: stayPoints) { _, _ in
            initializeCameraIfNeeded()
        }
        .onChange(of: routeLocations) { _, _ in
            initializeCameraIfNeeded()
        }
        .onChange(of: currentLocation) { _, _ in
            initializeCameraIfNeeded()
        }
        .onChange(of: selectedEpisodeID) { _, selectedID in
            focusMap(on: selectedID)
        }
        .onChange(of: currentLocationFocusRequest) { _, _ in
            focusMapOnCurrentLocation()
        }
        .sensoryFeedback(.selection, trigger: selectedEpisodeID)
    }

    private func initializeCameraIfNeeded() {
        guard !hasInitializedCamera else { return }
        let route = routeSnapshot
        var coordinates = route.coordinates + stayPoints.map(\.coordinate)
        if let currentLocation {
            coordinates.append(currentLocation.coordinate)
        }
        guard let region = regionFitting(coordinates: coordinates) else { return }
        position = .region(region)
        hasInitializedCamera = true
    }

    private func regionFitting(coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        let validCoordinates = coordinates.filter {
            CLLocationCoordinate2DIsValid($0)
        }
        guard let first = validCoordinates.first else { return nil }
        guard validCoordinates.count > 1 else {
            return MKCoordinateRegion(
                center: first,
                latitudinalMeters: visualStyle.singlePointCameraMeters,
                longitudinalMeters: visualStyle.singlePointCameraMeters
            )
        }

        let minLatitude = validCoordinates.map(\.latitude).min() ?? first.latitude
        let maxLatitude = validCoordinates.map(\.latitude).max() ?? first.latitude
        let minLongitude = validCoordinates.map(\.longitude).min() ?? first.longitude
        let maxLongitude = validCoordinates.map(\.longitude).max() ?? first.longitude
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )

        let latitudeMeters = max((maxLatitude - minLatitude) * 111_000, visualStyle.minimumCameraMeters)
        let longitudeMeters = max(
            (maxLongitude - minLongitude) * 111_000 * max(cos(center.latitude * .pi / 180), 0.25),
            visualStyle.minimumCameraMeters
        )
        let paddedLatitudeMeters = min(latitudeMeters * visualStyle.cameraPaddingMultiplier, 80_000)
        let paddedLongitudeMeters = min(longitudeMeters * visualStyle.cameraPaddingMultiplier, 80_000)

        return MKCoordinateRegion(
            center: center,
            latitudinalMeters: paddedLatitudeMeters,
            longitudinalMeters: paddedLongitudeMeters
        )
    }

    private func routePoints() -> [DayRoutePoint] {
        DayRouteProjection.points(
            stays: stayPoints.map { point in
                DayRouteStayInput(
                    id: point.id,
                    startDate: point.startDate,
                    endDate: point.endDate,
                    latitude: point.latitude,
                    longitude: point.longitude
                )
            },
            locationEvidence: routeLocations.map { location in
                DayRouteLocationInput(
                    id: location.id,
                    timestamp: location.timestamp,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    horizontalAccuracy: location.horizontalAccuracy,
                    source: location.source
                )
            },
            currentLocation: currentLocation.map { location in
                DayRouteCurrentLocationInput(
                    startDate: location.startDate,
                    lastEvidenceAt: location.lastEvidenceAt,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    horizontalAccuracy: location.horizontalAccuracy,
                    timeZoneIdentifier: location.timeZoneIdentifier
                )
            },
            options: routeOptions
        )
    }

    private func visibleMovementSamplePoints(in route: DayRouteSnapshot) -> [DayRoutePoint] {
        var anchors = stayPoints.map(\.coordinate)
        if let currentLocation {
            anchors.append(currentLocation.coordinate)
        }
        guard !anchors.isEmpty else { return route.movementSamplePoints }
        return route.movementSamplePoints.filter { sample in
            !anchors.contains { anchor in
                CLLocation(latitude: sample.latitude, longitude: sample.longitude).distance(
                    from: CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
                ) <= visualStyle.movementSampleAnchorExclusionMeters
            }
        }
    }

    private func select(_ point: DayMapStayPoint) {
        withAnimation(reduceMotion ? nil : .snappy) {
            selectedEpisodeID = point.id
        }
    }

    private func focusMap(on episodeID: UUID?) {
        guard let episodeID,
              let point = stayPoints.first(where: { $0.id == episodeID }) else {
            return
        }

        let region = focusRegion(
            center: point.coordinate,
            meters: 900
        )

        withAnimation(reduceMotion ? nil : .snappy) {
            position = .region(region)
        }
    }

    private func focusMapOnCurrentLocation() {
        guard let currentLocation else { return }

        let region = focusRegion(
            center: currentLocation.coordinate,
            meters: 1_200
        )

        withAnimation(reduceMotion ? nil : .snappy) {
            position = .region(region)
        }
    }

    private func focusRegion(center coordinate: CLLocationCoordinate2D, meters: CLLocationDistance) -> MKCoordinateRegion {
        var region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )
        region.center.latitude -= region.span.latitudeDelta * visualStyle.focusPanelLatitudeOffsetRatio
        return region
    }
}

private enum DayMapVisualStyle: Equatable {
    case compactCard
    case expanded

    var routeColor: Color {
        switch self {
        case .compactCard:
            Color.daytraceInk.opacity(0.64)
        case .expanded:
            Color.primary.opacity(0.58)
        }
    }

    var routeHaloColor: Color {
        switch self {
        case .compactCard:
            Color(.systemBackground).opacity(0.90)
        case .expanded:
            Color(.systemBackground).opacity(0.82)
        }
    }

    var routeWidth: CGFloat {
        switch self {
        case .compactCard: 2.6
        case .expanded: 3
        }
    }

    var routeHaloWidth: CGFloat {
        switch self {
        case .compactCard: 6
        case .expanded: 7
        }
    }

    var movementSampleColor: Color {
        switch self {
        case .compactCard:
            Color.daytraceInk.opacity(0.34)
        case .expanded:
            Color.primary.opacity(0.30)
        }
    }

    var movementSampleSize: CGFloat {
        switch self {
        case .compactCard: 5.5
        case .expanded: 5
        }
    }

    var movementSampleAnchorExclusionMeters: CLLocationDistance {
        switch self {
        case .compactCard: 70
        case .expanded: 110
        }
    }

    var markerForegroundColor: Color {
        switch self {
        case .compactCard:
            Color.daytraceInk.opacity(0.76)
        case .expanded:
            Color.primary.opacity(0.72)
        }
    }

    var selectedMarkerColor: Color {
        switch self {
        case .compactCard:
            Color.daytraceInk
        case .expanded:
            Color.primary
        }
    }

    var markerBackgroundColor: Color {
        switch self {
        case .compactCard:
            Color(.secondarySystemGroupedBackground)
        case .expanded:
            Color(.systemBackground)
        }
    }

    var currentLocationHaloColor: Color {
        switch self {
        case .compactCard:
            Color.daytraceInk.opacity(0.09)
        case .expanded:
            Color.primary.opacity(0.10)
        }
    }

    var singlePointCameraMeters: CLLocationDistance {
        switch self {
        case .compactCard: 2_600
        case .expanded: 1_400
        }
    }

    var minimumCameraMeters: CLLocationDistance {
        switch self {
        case .compactCard: 1_800
        case .expanded: 900
        }
    }

    var cameraPaddingMultiplier: Double {
        switch self {
        case .compactCard: 1.9
        case .expanded: 1.45
        }
    }

    var focusPanelLatitudeOffsetRatio: Double {
        switch self {
        case .compactCard: 0
        case .expanded: 0.20
        }
    }
}

private struct DayMapStayPoint: Identifiable, Equatable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date?
    let latitude: Double
    let longitude: Double
    let confidence: EpisodeConfidence

    init?(_ episode: TimelineEpisode) {
        guard episode.kind == .stay,
              let latitude = episode.latitude,
              let longitude = episode.longitude else {
            return nil
        }
        id = episode.id
        title = episode.title
        startDate = episode.startDate
        endDate = episode.endDate
        self.latitude = latitude
        self.longitude = longitude
        confidence = episode.confidence
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct DayMapRouteLocation: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let source: EvidenceSource

    init(_ evidence: LocationEvidence) {
        id = evidence.id
        timestamp = evidence.timestamp
        latitude = evidence.latitude
        longitude = evidence.longitude
        horizontalAccuracy = evidence.horizontalAccuracy
        source = evidence.source
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

private struct DayMapCurrentLocation: Equatable {
    let startDate: Date
    let lastEvidenceAt: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timeZoneIdentifier: String

    init(_ currentLocation: CurrentLocationContext) {
        startDate = currentLocation.startDate
        lastEvidenceAt = currentLocation.lastEvidenceAt
        latitude = currentLocation.latitude
        longitude = currentLocation.longitude
        horizontalAccuracy = currentLocation.horizontalAccuracy
        timeZoneIdentifier = currentLocation.timeZoneIdentifier
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
    let visualStyle: DayMapVisualStyle

    var body: some View {
        ZStack {
            Circle()
                .fill(visualStyle.currentLocationHaloColor)
                .frame(width: 40, height: 40)

            Circle()
                .fill(visualStyle.markerBackgroundColor)
                .frame(width: 29, height: 29)
                .shadow(radius: 3, y: 1)

            Text(index, format: .number)
                .font(.caption.bold())
                .foregroundStyle(visualStyle.selectedMarkerColor)
        }
        .frame(width: 44, height: 44)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(visualStyle.selectedMarkerColor.opacity(0.78))
                .frame(width: 9, height: 9)
                .overlay {
                    Circle().stroke(visualStyle.markerBackgroundColor, lineWidth: 2)
                }
        }
    }
}

private struct DayMapMarker: View {
    let index: Int
    let isSelected: Bool
    let confidence: EpisodeConfidence
    let visualStyle: DayMapVisualStyle

    private var outerSize: CGFloat { isSelected ? 36 : 31 }
    private var foregroundStyle: Color {
        if isSelected {
            return visualStyle.selectedMarkerColor
        }
        return confidence == .low ? Color.secondary : visualStyle.markerForegroundColor
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(visualStyle.markerBackgroundColor)
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
