import CoreLocation
import Foundation
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationRecorder.self) private var recorder

    @Query(sort: \TimelineEpisode.startDate) private var episodes: [TimelineEpisode]
    @Query(sort: \JournalEntry.dayAnchor) private var journals: [JournalEntry]
    @Query(sort: \MomentNote.timestamp) private var momentNotes: [MomentNote]
    @Query(sort: \PlaceRecord.name) private var places: [PlaceRecord]
    @Query(sort: \UserAssertion.createdAt) private var assertions: [UserAssertion]
    @Query(sort: \LocationEvidence.timestamp) private var locations: [LocationEvidence]

    @AppStorage("rawEvidenceRetentionDays") private var rawEvidenceRetentionDays = 90
    @AppStorage("appLockEnabled") private var appLockEnabled = false

    @State private var exportDocument: DayTraceExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = "DayTrace"
    @State private var isExportPresented = false
    @State private var exportErrorMessage: String?
    @State private var appLockErrorMessage: String?
    @State private var privacyActionErrorMessage: String?
    @State private var isHistoryDeletionConfirmationPresented = false

    private var suppressedCount: Int {
        TimelineVisibility.suppressedEpisodeIDs(from: assertions).count
    }

    private var visibleEpisodes: [TimelineEpisode] {
        let suppressed = TimelineVisibility.suppressedEpisodeIDs(from: assertions)
        return episodes.filter { !suppressed.contains($0.id) }
    }

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { appLockEnabled },
            set: { enabled in
                if enabled {
                    if AppLockAvailability.canEnable() {
                        appLockEnabled = true
                    } else {
                        appLockErrorMessage = "端末のパスコードまたは生体認証を有効にしてから、もう一度試してください。"
                    }
                } else {
                    appLockEnabled = false
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                TrackingDiagnosticsSection()

                ReviewReminderSettingsSection()

                Section {
                    Toggle("アプリをロック", isOn: appLockBinding)
                        .alert(
                            "アプリをロックできません",
                            isPresented: Binding(
                                get: { appLockErrorMessage != nil },
                                set: { if !$0 { appLockErrorMessage = nil } }
                            )
                        ) {
                            Button("OK", role: .cancel) { appLockErrorMessage = nil }
                        } message: {
                            Text(appLockErrorMessage ?? "")
                        }

                    Picker("生の位置データ", selection: $rawEvidenceRetentionDays) {
                        Text("30日").tag(30)
                        Text("90日").tag(90)
                        Text("1年").tag(365)
                        Text("ずっと").tag(0)
                    }
                    .onChange(of: rawEvidenceRetentionDays) { _, days in
                        recorder.applyRetentionPolicy(days: days)
                    }
                } header: {
                    Text("プライバシー")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("アプリロックを有効にすると、次回からFace ID・Touch ID・端末パスコードで位置履歴と日記を保護します。App Switcherでは設定に関係なく内容を隠します。")
                        Text("保持期間を短くすると、それより古い生の位置データを削除します。日記と確定したTimelineは残ります。")
                    }
                }

                Section("データ") {
                    LabeledContent("保存先", value: "このiPhone")

                    if suppressedCount > 0 {
                        Button("非表示をすべて戻す（\(suppressedCount)）") {
                            restoreAllSuppressed()
                        }
                    }

                    Menu {
                        Button {
                            prepareExport(.json)
                        } label: {
                            Label("JSON バックアップ", systemImage: "curlybraces")
                        }

                        Button {
                            prepareExport(.markdown)
                        } label: {
                            Label("Markdown 日記", systemImage: "doc.plaintext")
                        }

                        Button {
                            prepareExport(.gpx)
                        } label: {
                            Label("GPX 生位置データ", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        .disabled(locations.isEmpty)
                    } label: {
                        Label("書き出す", systemImage: "square.and.arrow.up")
                    }

                    Text("JSONはTimeline・場所・日記・修正履歴を保存します。Markdownは読み返し用です。GPXには現在保持している生の位置データ（\(locations.count)点）が含まれます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("位置履歴をすべて削除…", role: .destructive) {
                        isHistoryDeletionConfirmationPresented = true
                    }
                    .alert(
                        "位置履歴をすべて削除しますか？",
                        isPresented: $isHistoryDeletionConfirmationPresented
                    ) {
                        Button("位置履歴を削除", role: .destructive, action: deleteLocationHistory)
                        Button("キャンセル", role: .cancel) { }
                    } message: {
                        Text("生の位置データ、Timeline、記憶した場所、位置修正履歴を削除します。自分で書いた日記と今メモは残ります。自動記録はそのまま続き、削除後の記録だけが新しく作られます。")
                    }
                } header: {
                    Text("削除")
                } footer: {
                    Text("削除した位置履歴は元に戻せません。必要なら先にJSONまたはGPXを書き出してください。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $isExportPresented,
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportFilename
            ) { result in
                if case .failure(let error) = result {
                    exportErrorMessage = error.localizedDescription
                }
                exportDocument = nil
            }
            .alert(
                "書き出せません",
                isPresented: Binding(
                    get: { exportErrorMessage != nil },
                    set: { if !$0 { exportErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { exportErrorMessage = nil }
            } message: {
                Text(exportErrorMessage ?? "")
            }
            .alert(
                "操作できませんでした",
                isPresented: Binding(
                    get: { privacyActionErrorMessage != nil },
                    set: { if !$0 { privacyActionErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { privacyActionErrorMessage = nil }
            } message: {
                Text(privacyActionErrorMessage ?? "")
            }
        }
    }

    private func prepareExport(_ format: DayTraceExportFormat) {
        do {
            let data: Data
            switch format {
            case .json:
                data = try DayTraceExportBuilder.json(
                    episodes: episodes,
                    journals: journals,
                    momentNotes: momentNotes,
                    places: places,
                    assertions: assertions
                )
            case .markdown:
                data = Data(DayTraceExportBuilder.markdown(
                    episodes: visibleEpisodes,
                    journals: journals,
                    momentNotes: momentNotes
                ).utf8)
            case .gpx:
                data = Data(DayTraceExportBuilder.gpx(locations: locations).utf8)
            }

            exportDocument = DayTraceExportDocument(data: data)
            exportContentType = format.contentType
            exportFilename = "DayTrace-\(DayTraceExportBuilder.filenameDate()).\(format.fileExtension)"
            isExportPresented = true
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func deleteLocationHistory() {
        do {
            try recorder.deleteLocationHistoryKeepingJournal()
        } catch {
            privacyActionErrorMessage = error.localizedDescription
        }
    }

    private func restoreAllSuppressed() {
        do {
            try TimelineEditingService().restoreAllSuppressed(in: modelContext)
            try TimelineEngine().rebuildRecentTimeline(in: modelContext)
        } catch {
            privacyActionErrorMessage = error.localizedDescription
        }
    }
}

private struct TrackingDiagnosticsSection: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LocationRecorder.self) private var recorder

    @AppStorage("detailedRoutesEnabled") private var detailedRoutesEnabled = false

    var body: some View {
        Section {
            LabeledContent("状態", value: healthLabel)
            LabeledContent("位置情報", value: authorizationLabel)
            LabeledContent("正確な位置情報", value: accuracyLabel)
            LabeledContent("記録エンジン", value: recorder.isRecording ? "動作中" : "停止中")
            LabeledContent("最後の位置", value: lastEvidenceLabel)

            permissionRecoveryControl

            if canRequestSnapshot {
                Button("記録状態を再確認") {
                    recorder.requestForegroundSnapshot()
                }
            }

            Toggle("詳細な移動経路を記録", isOn: $detailedRoutesEnabled)
                .onChange(of: detailedRoutesEnabled) { _, enabled in
                    recorder.setDetailedRoutesEnabled(enabled)
                }
        } header: {
            Text("自動記録")
        } footer: {
            Text("「最後の位置」はDayTraceが最後に受け取った位置・訪問の時刻です。長時間更新がない場合でも、推測で履歴を埋めません。詳細な経路は位置更新を増やすため、バッテリー消費が増える場合があります。")
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, canRequestSnapshot else { return }
            recorder.requestForegroundSnapshot()
        }
    }

    private var canRequestSnapshot: Bool {
        recorder.authorizationStatus == .authorizedAlways
            || recorder.authorizationStatus == .authorizedWhenInUse
    }

    @ViewBuilder
    private var permissionRecoveryControl: some View {
        switch recorder.authorizationStatus {
        case .notDetermined:
            Button("位置情報を許可") {
                recorder.requestWhenInUse()
            }
        case .authorizedWhenInUse:
            if recorder.canRequestAlwaysInApp {
                Button("閉じている間も記録する") {
                    recorder.requestAlways()
                }
            } else {
                Button("設定で「常に許可」に変更") {
                    openSystemSettings()
                }
            }
        case .denied:
            Button("位置情報をオンにする") {
                openSystemSettings()
            }
        case .restricted:
            Text("この端末では位置情報の変更が制限されています。")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .authorizedAlways:
            if recorder.accuracyAuthorization == .reducedAccuracy {
                Button("設定で「正確な位置情報」をオン") {
                    openSystemSettings()
                }
            }
        @unknown default:
            EmptyView()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private var healthLabel: String {
        switch recorder.health {
        case .healthy: "正常"
        case .limitedAccuracy: "精度を制限中"
        case .needsPermission: "オフ"
        case .stale: "最近の記録なし"
        case .unavailable: "要確認"
        case .notConfigured: "確認中"
        }
    }

    private var authorizationLabel: String {
        switch recorder.authorizationStatus {
        case .authorizedAlways: "常に許可"
        case .authorizedWhenInUse: "使用中のみ"
        case .denied: "許可しない"
        case .restricted: "制限あり"
        case .notDetermined: "未設定"
        @unknown default: "不明"
        }
    }

    private var accuracyLabel: String {
        switch recorder.accuracyAuthorization {
        case .fullAccuracy: "オン"
        case .reducedAccuracy: "オフ"
        @unknown default: "不明"
        }
    }

    private var lastEvidenceLabel: String {
        guard let date = recorder.lastEvidenceAt else { return "まだなし" }
        let age = max(0, Date.now.timeIntervalSince(date))

        if age < 60 {
            return "たった今"
        }
        if age < 60 * 60 {
            return "\(Int(age / 60))分前"
        }
        if age < 24 * 60 * 60 {
            return "\(Int(age / 3_600))時間前"
        }

        return date.formatted(
            .dateTime.month().day().hour().minute().locale(Locale(identifier: "ja_JP"))
        )
    }
}
