import MapKit
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationRecorder.self) private var recorder
    @Query(sort: \TimelineEpisode.startDate) private var episodes: [TimelineEpisode]
    @Query(sort: \JournalEntry.dayAnchor) private var journals: [JournalEntry]

    @State private var selectedEpisodeID: UUID?
    @State private var isSettingsPresented = false
    @State private var stayEditSelection: StayEditSelection?

    private var day: DayInterval {
        DayInterval(containing: .now, timeZone: .current)
    }

    private var todayEpisodes: [TimelineEpisode] {
        episodes.filter { day.intersects(start: $0.startDate, end: $0.endDate) }
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
                TodayHeader(episodes: todayEpisodes)

                if recorder.health != .healthy {
                    TrackingHealthBanner(health: recorder.health)
                }

                if hasLocatableStay {
                    DayMap(
                        episodes: todayEpisodes,
                        selectedEpisodeID: $selectedEpisodeID
                    )
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
                        }
                    )
                }

                JournalComposer(day: day, existingJournal: todayJournal)
            }
            .padding(.horizontal, DS.horizontalPadding)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
        .navigationTitle("今日")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("設定")
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .sheet(item: $stayEditSelection) { selection in
            StayEditorSheet(episode: selection.episode)
        }
        .task {
            recorder.requestForegroundSnapshot()
            try? TimelineEngine().rebuildRecentTimeline(in: modelContext)
        }
    }
}

private struct StayEditSelection: Identifiable {
    let episode: TimelineEpisode
    var id: UUID { episode.id }
}

private struct TodayHeader: View {
    let episodes: [TimelineEpisode]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "ja_JP"))))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            Text(Date.now.formatted(.dateTime.month(.wide).day().locale(Locale(identifier: "ja_JP"))))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.7)

            if !episodes.isEmpty {
                let stays = episodes.filter { $0.kind == .stay }.count
                Text("\(stays)か所 · 今日の記録")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
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
        .padding(.vertical, 8)
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
        .padding(.vertical, 4)
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

private struct StayEditorSheet: View {
    let episode: TimelineEpisode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isOngoing: Bool
    @State private var confirmLocation: Bool

    init(episode: TimelineEpisode) {
        self.episode = episode
        _title = State(initialValue: episode.title == "未設定の場所" ? "" : episode.title)
        _startDate = State(initialValue: episode.startDate)
        _endDate = State(initialValue: episode.endDate ?? .now)
        _isOngoing = State(initialValue: episode.endDate == nil)
        _confirmLocation = State(initialValue: episode.confidence == .high)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("場所") {
                    TextField("場所の名前", text: $title)
                        .textInputAutocapitalization(.never)

                    Toggle("この場所で合っている", isOn: $confirmLocation)
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
                    if !isOngoing && endDate <= startDate {
                        Text("出発時刻は到着時刻より後にしてください。")
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
                        .disabled(!isOngoing && endDate <= startDate)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        try? TimelineEditingService().saveStay(
            episode,
            title: title,
            startDate: startDate,
            endDate: isOngoing ? nil : endDate,
            confirmLocation: confirmLocation,
            in: modelContext
        )
        dismiss()
    }
}
