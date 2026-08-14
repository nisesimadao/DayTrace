import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationRecorder.self) private var recorder
    @Query(sort: \TimelineEpisode.startDate) private var episodes: [TimelineEpisode]
    @Query(sort: \JournalEntry.dayAnchor) private var journals: [JournalEntry]
    @Query(sort: \UserAssertion.createdAt) private var assertions: [UserAssertion]

    @State private var selectedEpisodeID: UUID?
    @State private var isSettingsPresented: Bool
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

    private var hasLocatableStay: Bool {
        todayEpisodes.contains { episode in
            episode.kind == .stay && episode.latitude != nil && episode.longitude != nil
        }
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
                    TrackingHealthBanner(health: recorder.health)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if hasLocatableStay {
                    DayMap(
                        episodes: todayEpisodes,
                        selectedEpisodeID: $selectedEpisodeID
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if todayEpisodes.isEmpty {
                    EmptyTimelineState()
                } else {
                    DayTimeline(
                        episodes: todayEpisodes,
                        selectedEpisodeID: $selectedEpisodeID,
                        lastEvidenceAt: recorder.lastEvidenceAt,
                        onEdit: { episode in
                            stayEditSelection = StayEditSelection(episode: episode)
                        },
                        onSuppress: suppress
                    )
                }
            }
            .padding(.horizontal, DS.horizontalPadding)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: recorder.health == .healthy)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: hasLocatableStay)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .sheet(item: $stayEditSelection) { selection in
            StayEditorSheet(episode: selection.episode)
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

                Button("設定", systemImage: "ellipsis", action: openSettings)
                    .labelStyle(.iconOnly)
                    .font(.headline)
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
    let health: LocationRecorder.Health

    var body: some View {
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
        .padding(DS.cardPadding)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: DS.contentCornerRadius))
        .accessibilityElement(children: .combine)
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
        case .limitedAccuracy: "大まかな訪問履歴として記録します"
        case .stale: "最後に確認できた時刻以降は、推測せず空白として扱います"
        case .unavailable(let reason): reason
        case .needsPermission: "日記はそのまま使えます"
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

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isOngoing: Bool
    @State private var shouldConfirmLocation = false
    @State private var saveErrorMessage: String?
    @State private var isLookingUpPlace = false
    @State private var placeLookupMessage: String?
    @State private var didApplyPlaceSuggestion = false

    init(episode: TimelineEpisode, rebuildHistoricalTransitions: Bool = false) {
        self.episode = episode
        self.rebuildHistoricalTransitions = rebuildHistoricalTransitions
        _title = State(initialValue: episode.title == "未設定の場所" ? "" : episode.title)
        _startDate = State(initialValue: episode.startDate)
        _endDate = State(initialValue: episode.endDate ?? .now)
        _isOngoing = State(initialValue: episode.endDate == nil)
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

    private var shouldApplyConfirmation: Bool {
        shouldConfirmLocation
            && !trimmedTitle.isEmpty
            && (episode.confidence != .high || hasEditedPlaceName)
    }

    private var proposedEndDate: Date? {
        isOngoing ? nil : endDate
    }

    private var hasEditedTime: Bool {
        startDate != episode.startDate || proposedEndDate != episode.endDate
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

    private var canLookUpPlace: Bool {
        episode.latitude != nil && episode.longitude != nil && !isLookingUpPlace
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("場所") {
                    TextField("場所の名前", text: $title)
                        .textInputAutocapitalization(.never)

                    Button(action: lookUpPlaceSuggestion) {
                        if isLookingUpPlace {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Apple Mapsで候補を検索中")
                            }
                        } else {
                            Label("Apple Mapsで候補を探す", systemImage: "map")
                        }
                    }
                    .disabled(!canLookUpPlace)

                    if didApplyPlaceSuggestion {
                        Text("Apple Mapsの候補です。内容を確認し、「この場所で合っている」をオンにすると次回から覚えます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let placeLookupMessage {
                        Text(placeLookupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if episode.confidence == .high && !hasEditedPlaceName {
                        Label("この場所は高い確度で記録されています", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("この場所で合っている", isOn: $shouldConfirmLocation)
                            .disabled(trimmedTitle.isEmpty)
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
            .navigationTitle("滞在を修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(intervalValidationError != nil || isLookingUpPlace)
                }
            }
        }
        .presentationDetents([.medium, .large])
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

    private func lookUpPlaceSuggestion() {
        guard let latitude = episode.latitude, let longitude = episode.longitude else { return }
        isLookingUpPlace = true
        placeLookupMessage = nil
        didApplyPlaceSuggestion = false

        Task {
            do {
                if let suggestion = try await PlaceSuggestionLookup.suggestion(
                    latitude: latitude,
                    longitude: longitude
                ) {
                    title = suggestion
                    shouldConfirmLocation = false
                    didApplyPlaceSuggestion = true
                } else {
                    placeLookupMessage = "この位置では場所の候補を見つけられませんでした。"
                }
            } catch {
                placeLookupMessage = "場所の候補を取得できませんでした。通信状態を確認してもう一度試してください。"
            }
            isLookingUpPlace = false
        }
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
                confirmLocation: shouldApplyConfirmation,
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
}

@MainActor
private enum PlaceSuggestionLookup {
    static func suggestion(latitude: Double, longitude: Double) async throws -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        if #available(iOS 26.0, *) {
            return try await mapKitSuggestion(for: location)
        } else {
            return try await legacySuggestion(for: location)
        }
    }

    @available(iOS 26.0, *)
    private static func mapKitSuggestion(for location: CLLocation) async throws -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = .current

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<String?, Error>) in
            request.getMapItems { [request] items, error in
                _ = request
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let suggestion = items?
                    .lazy
                    .compactMap(preferredLabel(for:))
                    .first
                continuation.resume(returning: suggestion)
            }
        }
    }

    @available(iOS, introduced: 18.0, obsoleted: 26.0)
    private static func legacySuggestion(for location: CLLocation) async throws -> String? {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(
            location,
            preferredLocale: .current
        )

        for placemark in placemarks {
            let candidates = [
                placemark.areasOfInterest?.first,
                placemark.name,
                placemark.locality,
            ]
            if let value = candidates.compactMap(cleaned).first {
                return value
            }
        }
        return nil
    }

    @available(iOS 26.0, *)
    private static func preferredLabel(for item: MKMapItem) -> String? {
        let candidates = [
            item.name,
            item.address?.shortAddress,
            item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true),
            item.address?.fullAddress,
        ]
        return candidates.compactMap(cleaned).first
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
