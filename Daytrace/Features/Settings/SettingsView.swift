import Foundation
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(LocationRecorder.self) private var recorder

    @Query(sort: \TimelineEpisode.startDate) private var episodes: [TimelineEpisode]
    @Query(sort: \JournalEntry.dayAnchor) private var journals: [JournalEntry]
    @Query(sort: \MomentNote.timestamp) private var momentNotes: [MomentNote]
    @Query(sort: \PlaceRecord.name) private var places: [PlaceRecord]
    @Query(sort: \UserAssertion.createdAt) private var assertions: [UserAssertion]
    @Query(sort: \LocationEvidence.timestamp) private var locations: [LocationEvidence]

    @AppStorage("detailedRoutesEnabled") private var detailedRoutesEnabled = false
    @AppStorage("rawEvidenceRetentionDays") private var rawEvidenceRetentionDays = 90
    @AppStorage("appLockEnabled") private var appLockEnabled = false

    @State private var exportDocument: DayTraceExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = "DayTrace"
    @State private var isExportPresented = false
    @State private var exportErrorMessage: String?
    @State private var appLockErrorMessage: String?
    @State private var privacyActionErrorMessage: String?
    @State private var isRawDeletionConfirmationPresented = false
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
                Section {
                    LabeledContent("状態", value: healthLabel)
                    LabeledContent("位置情報", value: authorizationLabel)

                    permissionRecoveryControl

                    Toggle("詳細な移動経路を記録", isOn: $detailedRoutesEnabled)
                        .onChange(of: detailedRoutesEnabled) { _, enabled in
                            recorder.setDetailedRoutesEnabled(enabled)
                        }
                } header: {
                    Text("自動記録")
                } footer: {
                    Text("詳細な経路は必要な場面で位置更新を増やすため、バッテリー消費が増える場合があります。")
                }

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
                    Button("生の位置データを今すぐ削除…", role: .destructive) {
                        isRawDeletionConfirmationPresented = true
                    }
                    .alert("生の位置データを削除しますか？", isPresented: $isRawDeletionConfirmationPresented) {
                        Button("削除", role: .destructive, action: deleteRawLocationEvidence)
                        Button("キャンセル", role: .cancel) { }
                    } message: {
                        Text("保存しているLocation/Visitの生データを削除します。確定したTimelineと日記は残ります。")
                    }

                    Button("位置履歴をすべて削除…", role: .destructive) {
                        isHistoryDeletionConfirmationPresented = true
                    }
                    .alert("位置履歴をすべて削除しますか？", isPresented: $isHistoryDeletionConfirmationPresented) {
                        Button("位置履歴を削除", role: .destructive, action: deleteLocationHistory)
                        Button("キャンセル", role: .cancel) { }
                    } message: {
                        Text("生の位置データ、Timeline、記憶した場所、位置修正履歴を削除します。自分で書いた日記と今メモは残ります。自動記録はそのまま続きます。")
                    }
                } header: {
                    Text("削除")
                } footer: {
                    Text("削除した位置データは元に戻せません。必要なら先に書き出してください。")
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
            EmptyView()
        @unknown default:
            EmptyView()
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

    private func deleteRawLocationEvidence() {
        do {
            try recorder.deleteRawLocationEvidence()
        } catch {
            privacyActionErrorMessage = error.localizedDescription
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
}

private enum DayTraceExportFormat {
    case json
    case markdown
    case gpx

    var contentType: UTType {
        switch self {
        case .json: .json
        case .markdown: .dayTraceMarkdown
        case .gpx: .dayTraceGPX
        }
    }

    var fileExtension: String {
        switch self {
        case .json: "json"
        case .markdown: "md"
        case .gpx: "gpx"
        }
    }
}

private extension UTType {
    static var dayTraceMarkdown: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    static var dayTraceGPX: UTType {
        UTType(filenameExtension: "gpx") ?? .xml
    }
}

private struct DayTraceExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json, .dayTraceMarkdown, .dayTraceGPX, .plainText, .xml]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
private enum DayTraceExportBuilder {
    struct Snapshot: Codable {
        let schemaVersion: Int
        let exportedAt: Date
        let rawLocationEvidenceIncluded: Bool
        let episodes: [Episode]
        let journals: [Journal]
        let momentNotes: [Moment]
        let places: [Place]
        let assertions: [Assertion]
    }

    struct Episode: Codable {
        let id: UUID
        let kind: String
        let startDate: Date
        let endDate: Date?
        let title: String
        let subtitle: String?
        let latitude: Double?
        let longitude: Double?
        let confidence: String
        let placeID: UUID?
        let sourceVisitID: UUID?
        let sourceVersion: Int
        let timeZoneIdentifier: String
    }

    struct Journal: Codable {
        let id: UUID
        let dayAnchor: Date
        let body: String
        let createdAt: Date
        let updatedAt: Date
        let timeZoneIdentifier: String
    }

    struct Moment: Codable {
        let id: UUID
        let timestamp: Date
        let body: String
        let timeZoneIdentifier: String
    }

    struct Place: Codable {
        let id: UUID
        let name: String
        let latitude: Double
        let longitude: Double
        let radius: Double
        let source: String
        let isPrivate: Bool
    }

    struct Assertion: Codable {
        let id: UUID
        let episodeID: UUID?
        let type: String
        let createdAt: Date
        let replacementStart: Date?
        let replacementEnd: Date?
        let replacementTitle: String?
        let replacementLatitude: Double?
        let replacementLongitude: Double?
        let isActive: Bool
    }

    static func json(
        episodes: [TimelineEpisode],
        journals: [JournalEntry],
        momentNotes: [MomentNote],
        places: [PlaceRecord],
        assertions: [UserAssertion],
        now: Date = .now
    ) throws -> Data {
        let snapshot = Snapshot(
            schemaVersion: 1,
            exportedAt: now,
            rawLocationEvidenceIncluded: false,
            episodes: episodes.map {
                Episode(
                    id: $0.id,
                    kind: $0.kind.rawValue,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    title: $0.title,
                    subtitle: $0.subtitle,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    confidence: $0.confidence.rawValue,
                    placeID: $0.placeID,
                    sourceVisitID: $0.sourceVisitID,
                    sourceVersion: $0.sourceVersion,
                    timeZoneIdentifier: $0.timeZoneIdentifier
                )
            },
            journals: journals.map {
                Journal(
                    id: $0.id,
                    dayAnchor: $0.dayAnchor,
                    body: $0.body,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    timeZoneIdentifier: $0.timeZoneIdentifier
                )
            },
            momentNotes: momentNotes.map {
                Moment(
                    id: $0.id,
                    timestamp: $0.timestamp,
                    body: $0.body,
                    timeZoneIdentifier: $0.timeZoneIdentifier
                )
            },
            places: places.map {
                Place(
                    id: $0.id,
                    name: $0.name,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    radius: $0.radius,
                    source: $0.source.rawValue,
                    isPrivate: $0.isPrivate
                )
            },
            assertions: assertions.map {
                Assertion(
                    id: $0.id,
                    episodeID: $0.episodeID,
                    type: $0.type.rawValue,
                    createdAt: $0.createdAt,
                    replacementStart: $0.replacementStart,
                    replacementEnd: $0.replacementEnd,
                    replacementTitle: $0.replacementTitle,
                    replacementLatitude: $0.replacementLatitude,
                    replacementLongitude: $0.replacementLongitude,
                    isActive: $0.isActive
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func markdown(
        episodes: [TimelineEpisode],
        journals: [JournalEntry],
        momentNotes: [MomentNote],
        now: Date = .now
    ) -> String {
        var days = Set<CalendarDay>()
        for episode in episodes {
            days.formUnion(TimelineDayProjection.coveredDays(by: episode, openEndedAt: now, limit: 10_000))
        }
        for journal in journals {
            days.insert(TimelineDayProjection.day(for: journal))
        }
        for note in momentNotes {
            let zone = TimelineDayProjection.timeZone(identifier: note.timeZoneIdentifier)
            days.insert(CalendarDay(containing: note.timestamp, timeZone: zone))
        }

        var lines = [
            "# DayTrace",
            "",
            "書き出し日時: \(iso8601(now))",
            ""
        ]

        for day in days.sorted() {
            lines.append("## \(dayString(day))")
            lines.append("")

            let dayEpisodes = episodes
                .filter { TimelineDayProjection.episode($0, intersects: day, openEndedAt: now) }
                .sorted { $0.startDate < $1.startDate }

            for episode in dayEpisodes {
                let start = TimelineFormatting.clock(
                    episode.startDate,
                    timeZoneIdentifier: episode.timeZoneIdentifier
                )
                let end = episode.endDate.map {
                    TimelineFormatting.clock($0, timeZoneIdentifier: episode.timeZoneIdentifier)
                } ?? "継続中"
                lines.append("- \(start)–\(end)  \(episode.title)")
            }

            let dayNotes = momentNotes
                .filter { note in
                    let zone = TimelineDayProjection.timeZone(identifier: note.timeZoneIdentifier)
                    return CalendarDay(containing: note.timestamp, timeZone: zone) == day
                }
                .sorted { $0.timestamp < $1.timestamp }

            if !dayNotes.isEmpty {
                lines.append("")
                lines.append("### メモ")
                lines.append("")
                for note in dayNotes {
                    let time = TimelineFormatting.clock(
                        note.timestamp,
                        timeZoneIdentifier: note.timeZoneIdentifier
                    )
                    lines.append("- \(time)  \(note.body.replacingOccurrences(of: "\n", with: " "))")
                }
            }

            if let journal = journals.first(where: { TimelineDayProjection.journal($0, belongsTo: day) }),
               !journal.body.isEmpty {
                lines.append("")
                lines.append("### 日記")
                lines.append("")
                lines.append(journal.body)
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func gpx(locations: [LocationEvidence], now: Date = .now) -> String {
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        let segments = splitGPXSegments(sorted)

        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"DayTrace\" xmlns=\"http://www.topografix.com/GPX/1/1\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">",
            "  <metadata>",
            "    <time>\(iso8601(now))</time>",
            "  </metadata>",
            "  <trk>",
            "    <name>DayTrace</name>"
        ]

        for segment in segments {
            lines.append("    <trkseg>")
            for location in segment {
                lines.append(
                    "      <trkpt lat=\"\(decimal(location.latitude))\" lon=\"\(decimal(location.longitude))\"><time>\(iso8601(location.timestamp))</time></trkpt>"
                )
            }
            lines.append("    </trkseg>")
        }

        lines.append("  </trk>")
        lines.append("</gpx>")
        return lines.joined(separator: "\n")
    }

    static func filenameDate(_ date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func splitGPXSegments(_ locations: [LocationEvidence]) -> [[LocationEvidence]] {
        guard let first = locations.first else { return [] }

        var result: [[LocationEvidence]] = []
        var current = [first]

        for location in locations.dropFirst() {
            if let previous = current.last,
               location.timestamp.timeIntervalSince(previous.timestamp) > 10 * 60 {
                result.append(current)
                current = []
            }
            current.append(location)
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func dayString(_ day: CalendarDay) -> String {
        String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
