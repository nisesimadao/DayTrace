import CoreLocation
import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(LocationRecorder.self) private var recorder
    @Query(sort: \TimelineEpisode.startDate) private var episodes: [TimelineEpisode]
    @Query(sort: \JournalEntry.dayAnchor) private var journals: [JournalEntry]
    @Query(sort: \UserAssertion.createdAt) private var assertions: [UserAssertion]
    @Query(sort: \LocationEvidence.timestamp) private var locationEvidence: [LocationEvidence]
    @Query private var places: [PlaceRecord]

    @State private var selectedEpisodeID: UUID?
    @State private var isSettingsPresented: Bool
    @State private var isMapExpanded = false
    @State private var stayEditSelection: StayEditSelection?
    @State private var undoSuppressedEpisodeID: UUID?
    @State private var isTimelineErrorPresented = false
    @State private var timelineErrorMessage = ""

    init() {
#if DEBUG
        _isSettingsPresented = State(
            initialValue: ProcessInfo.processInfo.environment["DAYTRACE_SHOW_SETTINGS"] == "1"
        )
#else
        _isSettingsPresented = State(initialValue: false)
#endif
    }

    private var day: DayInterval {
        DayInterval(containing: .now, timeZone: .current)
    }

    private var suppressedEpisodeIDs: Set<UUID> {
        TimelineVisibility.suppressedEpisodeIDs(from: assertions)
    }

    private var todayEpisodes: [TimelineEpisode] {
        episodes.filter {
            !suppressedEpisodeIDs.contains($0.id)
                && day.intersects(start: $0.startDate, end: $0.endDate)
        }
    }

    private var todayRouteLocations: [LocationEvidence] {
        locationEvidence.filter {
            $0.timestamp >= day.start && $0.timestamp < day.end
        }
    }

    private var todayPreviewRouteLocations: [LocationEvidence] {
        let stays = todayEpisodes
            .filter { $0.kind == .stay && $0.latitude != nil && $0.longitude != nil }
            .sorted { $0.startDate < $1.startDate }

        guard stays.count >= 2, let latestCompletedRouteEnd = stays.last?.startDate else {
            return []
        }

        return todayRouteLocations.filter { $0.timestamp < latestCompletedRouteEnd }
    }

    private var currentLocation: CurrentLocationContext? {
        CurrentLocationProjection.project(
            evidence: locationEvidence,
            dayStart: day.start
        )
    }

    private var provisionalCurrentLocation: CurrentLocationContext? {
        guard let currentLocation else { return nil }
        let alreadyRepresented = todayEpisodes.contains {
            CurrentLocationProjection.matches($0, currentLocation: currentLocation)
        }
        return alreadyRepresented ? nil : currentLocation
    }

    private var mapCurrentLocation: CurrentLocationContext? {
        guard let currentLocation = provisionalCurrentLocation else { return nil }
        let bucketInterval: TimeInterval = 20
        let bucketEnd = Date(
            timeIntervalSinceReferenceDate: floor(currentLocation.lastEvidenceAt.timeIntervalSinceReferenceDate / bucketInterval) * bucketInterval
        )
        let evidence = todayRouteLocations.last { location in
            location.timestamp <= bucketEnd
                && location.timestamp >= currentLocation.startDate
                && location.horizontalAccuracy >= 0
                && location.horizontalAccuracy <= 1_000
        }

        guard let evidence else { return currentLocation }
        return CurrentLocationContext(
            startDate: currentLocation.startDate,
            lastEvidenceAt: evidence.timestamp,
            latitude: evidence.latitude,
            longitude: evidence.longitude,
            horizontalAccuracy: evidence.horizontalAccuracy,
            timeZoneIdentifier: evidence.timeZoneIdentifier
        )
    }

    private var currentLocationName: String {
        guard let currentLocation = provisionalCurrentLocation else { return "現在地" }
        return CurrentLocationProjection.placeName(for: currentLocation, places: places) ?? "現在地"
    }

    private var hasMapContent: Bool {
        todayEpisodes.contains { episode in
            episode.kind == .stay && episode.latitude != nil && episode.longitude != nil
        } || provisionalCurrentLocation != nil
    }

    private var currentMapSequenceNumber: Int {
        todayEpisodes.count {
            $0.kind == .stay && $0.latitude != nil && $0.longitude != nil
        } + 1
    }

    private var todayJournal: JournalEntry? {
        journals.first { $0.dayAnchor >= day.start && $0.dayAnchor < day.end }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.sectionSpacing) {
                TodayHeader(
                    episodes: todayEpisodes,
                    openSettings: { isSettingsPresented = true }
                )

                JournalComposer(day: day, existingJournal: todayJournal)

                LocationContextHeader()

                if recorder.health != .healthy {
                    TrackingHealthBanner(
                        health: recorder.health,
                        action: trackingHealthAction
                    )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if hasMapContent {
                    DayMap(
                        episodes: todayEpisodes,
                        routeLocations: todayPreviewRouteLocations,
                        currentLocation: mapCurrentLocation,
                        selectedEpisodeID: $selectedEpisodeID,
                        onExpand: showExpandedMap
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if todayEpisodes.isEmpty && provisionalCurrentLocation == nil {
                    EmptyTimelineState()
                } else if !todayEpisodes.isEmpty {
                    DayTimeline(
                        episodes: todayEpisodes,
                        selectedEpisodeID: $selectedEpisodeID,
                        lastEvidenceAt: nil,
                        currentLocation: currentLocation,
                        connectsToCurrentLocation: provisionalCurrentLocation != nil,
                        onEdit: { episode in
                            stayEditSelection = StayEditSelection(episode: episode)
                        },
                        onSuppress: suppress
                    )
                }

                if let provisionalCurrentLocation {
                    CurrentLocationTimelineRow(
                        currentLocation: provisionalCurrentLocation,
                        placeName: currentLocationName,
                        mapSequenceNumber: currentMapSequenceNumber,
                        connectsFromPrevious: !todayEpisodes.isEmpty,
                        onRegisterStay: registerCurrentLocationAsStay
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, DS.horizontalPadding)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: recorder.health == .healthy)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: hasMapContent)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: provisionalCurrentLocation != nil)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .sheet(item: $stayEditSelection) { selection in
            StayEditorSheet(episode: selection.episode)
        }
        .fullScreenCover(isPresented: $isMapExpanded) {
            ExpandedDayMapView(
                title: "今日の足あと",
                episodes: todayEpisodes,
                routeLocations: todayPreviewRouteLocations,
                currentLocation: mapCurrentLocation,
                selectedEpisodeID: $selectedEpisodeID,
                onRegisterCurrentLocation: registerCurrentLocationAsStay
            )
        }
        .navigationDestination(for: CalendarDay.self) { day in
            HistoricalDayDetailView(day: day)
        }
        .alert("タイムラインを更新できません", isPresented: $isTimelineErrorPresented) { } message: {
            Text(timelineErrorMessage)
        }
        .task {
            recorder.requestForegroundSnapshot()
            try? TimelineEngine().rebuildRecentTimeline(in: modelContext)
        }
        .safeAreaInset(edge: .bottom) {
            if let episodeID = undoSuppressedEpisodeID {
                HStack(spacing: 12) {
                    Text("滞在を非表示にしました")
                        .font(.subheadline)
                    Spacer()
                    Button("元に戻す") {
                        restoreSuppressed(episodeID)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .daytraceGlassSurface(cornerRadius: 22)
                .padding(.horizontal, DS.horizontalPadding)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: undoSuppressedEpisodeID)
    }

    private func suppress(_ episode: TimelineEpisode) {
        guard episode.kind == .stay else { return }
        do {
            try TimelineEditingService().setSuppressed(
                episodeID: episode.id,
                suppressed: true,
                in: modelContext
            )
            try TimelineEngine().rebuildRecentTimeline(in: modelContext)
            if selectedEpisodeID == episode.id {
                selectedEpisodeID = nil
            }
            undoSuppressedEpisodeID = episode.id
        } catch {
            timelineErrorMessage = error.localizedDescription
            isTimelineErrorPresented = true
        }
    }

    private func showExpandedMap() {
        isMapExpanded = true
    }

    private func registerCurrentLocationAsStay() {
        guard let currentLocation = provisionalCurrentLocation else { return }

        let title = currentLocationName == "現在地" ? "未設定の場所" : currentLocationName
        let episode = TimelineEpisode(
            kind: .stay,
            startDate: currentLocation.startDate,
            endDate: nil,
            title: title,
            subtitle: "手動で追加",
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude,
            confidence: .medium,
            sourceVersion: TimelineEngine.sourceVersion,
            timeZoneIdentifier: currentLocation.timeZoneIdentifier
        )

        do {
            modelContext.insert(episode)
            modelContext.insert(UserAssertion(
                episodeID: episode.id,
                type: .reposition,
                replacementLatitude: currentLocation.latitude,
                replacementLongitude: currentLocation.longitude
            ))
            if title != "未設定の場所" {
                modelContext.insert(UserAssertion(
                    episodeID: episode.id,
                    type: .rename,
                    replacementTitle: title
                ))
            }
            try modelContext.save()
            selectedEpisodeID = episode.id
            isMapExpanded = false
            DispatchQueue.main.async {
                stayEditSelection = StayEditSelection(episode: episode)
            }
        } catch {
            timelineErrorMessage = error.localizedDescription
            isTimelineErrorPresented = true
        }
    }

    private var trackingHealthAction: TrackingHealthBanner.Action? {
        switch recorder.health {
        case .needsPermission:
            switch recorder.authorizationStatus {
            case .notDetermined:
                return .init(title: "位置情報を許可", systemImage: "location") {
                    recorder.requestWhenInUse()
                }
            case .authorizedWhenInUse:
                if recorder.canRequestAlwaysInApp {
                    return .init(title: "常に許可へ進む", systemImage: "location.fill") {
                        recorder.requestAlways()
                    }
                }
                return settingsAction(title: "設定で常に許可", systemImage: "gearshape")
            case .denied:
                return systemSettingsAction(title: "位置情報をオン", systemImage: "gearshape")
            default:
                return settingsAction(title: "記録状態を見る", systemImage: "gearshape")
            }
        case .limitedAccuracy:
            return systemSettingsAction(title: "正確な位置情報をオン", systemImage: "scope")
        case .stale:
            return .init(title: "記録を再確認", systemImage: "arrow.clockwise") {
                recorder.requestForegroundSnapshot()
            }
        case .unavailable:
            return systemSettingsAction(title: "設定を開く", systemImage: "gearshape")
        case .notConfigured:
            return settingsAction(title: "記録状態を見る", systemImage: "gearshape")
        case .healthy:
            return nil
        }
    }

    private func settingsAction(title: String, systemImage: String) -> TrackingHealthBanner.Action {
        .init(title: title, systemImage: systemImage) {
            isSettingsPresented = true
        }
    }

    private func systemSettingsAction(title: String, systemImage: String) -> TrackingHealthBanner.Action {
        .init(title: title, systemImage: systemImage) {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
        }
    }

    private func restoreSuppressed(_ episodeID: UUID) {
        do {
            try TimelineEditingService().setSuppressed(
                episodeID: episodeID,
                suppressed: false,
                in: modelContext
            )
            try TimelineEngine().rebuildRecentTimeline(in: modelContext)
            undoSuppressedEpisodeID = nil
        } catch {
            timelineErrorMessage = error.localizedDescription
            isTimelineErrorPresented = true
        }
    }
}

private struct StayEditSelection: Identifiable {
    let episode: TimelineEpisode
    var id: UUID { episode.id }
}

private struct TodayHeader: View {
    let episodes: [TimelineEpisode]
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                DaytraceWordmark(markSize: 29)

                Spacer()

                Button("設定", systemImage: "gearshape", action: openSettings)
                    .font(.subheadline.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .buttonStyle(.daytraceGlass)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "ja_JP"))))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(Date.now.formatted(.dateTime.month(.wide).day().locale(Locale(identifier: "ja_JP"))))
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)

                if !episodes.isEmpty {
                    let stays = episodes.count { $0.kind == .stay }
                    Label("\(stays)か所が、今日の手がかりになっています", systemImage: "sparkle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("まだ何も起きていない日も、ちゃんと一日です。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DS.cardPadding)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.contentCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DS.contentCornerRadius)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .padding(.top, 8)
    }
}

private struct LocationContextHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日の手がかり")
                .font(.title2.bold())

            Text("場所と移動は、思い出すための背景です。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyTimelineState: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "location.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text("まだ記録がありません")
                    .font(.body.weight(.semibold))
                Text("移動すると訪れた場所がここに並びます。日記だけ先に残しても大丈夫です。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.cardPadding)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: DS.contentCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

private struct TrackingHealthBanner: View {
    struct Action {
        let title: String
        let systemImage: String
        let handler: () -> Void
    }

    let health: LocationRecorder.Health
    let action: Action?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let action {
                Button {
                    action.handler()
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.daytraceGlassProminent)
            }
        }
        .padding(DS.cardPadding)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: DS.contentCornerRadius))
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch health {
        case .limitedAccuracy: "location.slash"
        case .stale: "clock.badge.exclamationmark"
        case .unavailable: "exclamationmark.triangle"
        case .needsPermission: "location"
        default: "wave.3.right"
        }
    }

    private var title: String {
        switch health {
        case .limitedAccuracy: "位置の精度が制限されています"
        case .stale: "最近の位置を確認できていません"
        case .unavailable: "自動記録を確認してください"
        case .needsPermission: "自動記録はオフです"
        default: "記録を準備しています"
        }
    }

    private var detail: String {
        switch health {
        case .limitedAccuracy: "正確な位置情報をオンにすると、滞在場所を修正しやすくなります"
        case .stale: "最後に確認できた時刻以降は、推測せず空白として扱います"
        case .unavailable(let reason): reason
        case .needsPermission: "位置情報を許可すると、今日のタイムラインに現在地が出ます"
        default: "位置情報の状態を確認しています"
        }
    }
}

struct StayEditorSheet: View {
    let episode: TimelineEpisode
    let rebuildHistoricalTransitions: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimelineEpisode.startDate) private var allEpisodes: [TimelineEpisode]
    @Query(sort: \UserAssertion.createdAt) private var allAssertions: [UserAssertion]
    @Query(sort: \PlaceRecord.name) private var allPlaces: [PlaceRecord]

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isOngoing: Bool
    @State private var shouldConfirmLocation = false
    @State private var isLocationEditorPresented = false
    @State private var saveErrorMessage: String?
    @State private var selectedLatitude: Double
    @State private var selectedLongitude: Double
    @State private var selectedMergePlaceID: UUID?

    init(episode: TimelineEpisode, rebuildHistoricalTransitions: Bool = false) {
        self.episode = episode
        self.rebuildHistoricalTransitions = rebuildHistoricalTransitions
        _title = State(initialValue: episode.title == "未設定の場所" ? "" : episode.title)
        _startDate = State(initialValue: episode.startDate)
        _endDate = State(initialValue: episode.endDate ?? .now)
        _isOngoing = State(initialValue: episode.endDate == nil)
        _selectedLatitude = State(initialValue: episode.latitude ?? 0)
        _selectedLongitude = State(initialValue: episode.longitude ?? 0)
    }

    private var originalDisplayTitle: String {
        episode.title == "未設定の場所" ? "" : episode.title
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasEditedPlaceName: Bool {
        trimmedTitle != originalDisplayTitle
    }

    private var hasEditableCoordinate: Bool {
        episode.latitude != nil && episode.longitude != nil
    }

    private var hasEditedCoordinate: Bool {
        guard let latitude = episode.latitude, let longitude = episode.longitude else { return false }
        return abs(selectedLatitude - latitude) >= 0.000_001
            || abs(selectedLongitude - longitude) >= 0.000_001
    }

    private var shouldApplyConfirmation: Bool {
        shouldConfirmLocation
            && !trimmedTitle.isEmpty
            && (episode.confidence != .high || hasEditedPlaceName || hasEditedCoordinate)
    }

    private var proposedEndDate: Date? {
        isOngoing ? nil : endDate
    }

    private var hasEditedTime: Bool {
        startDate != episode.startDate || proposedEndDate != episode.endDate
    }

    private var mergeCandidates: [PlaceRecord] {
        let candidates = allPlaces.filter { $0.id != episode.placeID }
        guard let latitude = episode.latitude, let longitude = episode.longitude else {
            return Array(candidates.prefix(12))
        }

        let episodeLocation = CLLocation(latitude: latitude, longitude: longitude)
        return candidates
            .sorted { lhs, rhs in
                let leftDistance = episodeLocation.distance(from: CLLocation(latitude: lhs.latitude, longitude: lhs.longitude))
                let rightDistance = episodeLocation.distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
                return leftDistance < rightDistance
            }
            .prefix(12)
            .map { $0 }
    }

    private var intervalValidationError: TimelineEditingError? {
        guard hasEditedTime else { return nil }
        return StayIntervalValidator.validationError(
            episodeID: episode.id,
            startDate: startDate,
            endDate: proposedEndDate,
            episodes: allEpisodes,
            suppressedEpisodeIDs: TimelineVisibility.suppressedEpisodeIDs(from: allAssertions)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("場所") {
                    TextField("場所の名前", text: $title)
                        .textInputAutocapitalization(.never)

                    if let originalLatitude = episode.latitude,
                       let originalLongitude = episode.longitude {
                        StayLocationPicker(
                            latitude: selectedLatitude,
                            longitude: selectedLongitude,
                            originalLatitude: originalLatitude,
                            originalLongitude: originalLongitude,
                            onEdit: showLocationEditor
                        )
                    }

                    if episode.confidence == .high && !hasEditedPlaceName && !hasEditedCoordinate {
                        Label("この場所は高い確度で記録されています", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("この場所として覚える", isOn: $shouldConfirmLocation)
                            .disabled(trimmedTitle.isEmpty)
                    }
                }

                if !mergeCandidates.isEmpty {
                    Section {
                        Picker("結合先", selection: $selectedMergePlaceID) {
                            Text("結合しない").tag(UUID?.none)
                            ForEach(mergeCandidates) { place in
                                Text(mergeCandidateTitle(for: place))
                                    .tag(Optional(place.id))
                            }
                        }
                        .onChange(of: selectedMergePlaceID) { _, placeID in
                            applyMergeSelection(placeID)
                        }
                    } header: {
                        Text("同じ場所として結合")
                    } footer: {
                        Text("同じ場所なのに別名・別地点として出ている場合は、既存の場所へまとめます。再解析後もこの紐付けを優先します。")
                    }
                }

                Section {
                    DatePicker("到着", selection: $startDate)
                    Toggle("まだここにいる", isOn: $isOngoing)

                    if !isOngoing {
                        DatePicker("出発", selection: $endDate)
                    }
                } header: {
                    Text("時刻")
                } footer: {
                    if let intervalValidationError {
                        Text(intervalValidationError.localizedDescription)
                            .foregroundStyle(.red)
                    } else {
                        Text("ここで直した内容は、位置情報を再解析しても優先して残します。")
                    }
                }
            }
            .navigationDestination(isPresented: $isLocationEditorPresented) {
                if let originalLatitude = episode.latitude,
                   let originalLongitude = episode.longitude {
                    StayLocationEditor(
                        latitude: selectedLatitude,
                        longitude: selectedLongitude,
                        originalLatitude: originalLatitude,
                        originalLongitude: originalLongitude,
                        onConfirm: applyLocationSelection
                    )
                }
            }
            .navigationTitle("滞在を修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isLocationEditorPresented {
                        Button("キャンセル") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isLocationEditorPresented {
                        Button("保存", action: save)
                            .disabled(intervalValidationError != nil)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .alert(
            "保存できません",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func showLocationEditor() {
        isLocationEditorPresented = true
    }

    private func applyLocationSelection(
        latitude: Double,
        longitude: Double,
        suggestedTitle: String?
    ) {
        let hadCustomTitle = hasEditedPlaceName
        selectedLatitude = latitude
        selectedLongitude = longitude
        if let suggestedTitle {
            title = suggestedTitle
        } else if !hadCustomTitle {
            title = ""
        }
        shouldConfirmLocation = false
    }

    private func save() {
        let originalStart = episode.startDate
        let originalEnd = episode.endDate
        let timeWasEdited = hasEditedTime

        do {
            try TimelineEditingService().saveStay(
                episode,
                title: title,
                startDate: startDate,
                endDate: proposedEndDate,
                latitude: hasEditableCoordinate ? selectedLatitude : nil,
                longitude: hasEditableCoordinate ? selectedLongitude : nil,
                confirmLocation: shouldApplyConfirmation,
                mergePlaceID: selectedMergePlaceID,
                in: modelContext
            )
            if rebuildHistoricalTransitions {
                if timeWasEdited {
                    var boundaryDates = [originalStart, startDate]
                    if let originalEnd { boundaryDates.append(originalEnd) }
                    if let proposedEndDate { boundaryDates.append(proposedEndDate) }

                    if let first = boundaryDates.min(), let last = boundaryDates.max() {
                        let rebuildInterval = DateInterval(
                            start: first.addingTimeInterval(-1),
                            end: last.addingTimeInterval(1)
                        )
                        try TimelineEngine().rebuildTransitions(
                            covering: rebuildInterval,
                            in: modelContext
                        )
                    }
                }
            } else {
                try TimelineEngine().rebuildRecentTimeline(in: modelContext)
            }
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func mergeCandidateTitle(for place: PlaceRecord) -> String {
        guard let latitude = episode.latitude, let longitude = episode.longitude else {
            return place.name
        }
        let distance = CLLocation(latitude: latitude, longitude: longitude).distance(
            from: CLLocation(latitude: place.latitude, longitude: place.longitude)
        )
        if distance < 1_000 {
            return "\(place.name)（約\(Int(distance))m）"
        }
        let kilometers = distance / 1_000
        return "\(place.name)（約\(String(format: "%.1f", kilometers))km）"
    }

    private func applyMergeSelection(_ placeID: UUID?) {
        guard let placeID,
              let place = allPlaces.first(where: { $0.id == placeID }) else {
            return
        }
        title = place.name
        selectedLatitude = place.latitude
        selectedLongitude = place.longitude
        shouldConfirmLocation = true
    }
}
