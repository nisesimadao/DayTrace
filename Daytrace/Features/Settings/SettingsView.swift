import Foundation
import SwiftData
import SwiftUI
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
