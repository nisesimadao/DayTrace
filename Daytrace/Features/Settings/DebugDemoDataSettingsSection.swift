#if DEBUG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DebugDemoDataSettingsSection: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isInstalled = false
    @State private var errorMessage: String?
    @State private var fixturePath: String?
    @State private var importResult: DebugMarketingFixtureService.ImportResult?
    @State private var isMarketingImportConfirmationPresented = false
    @State private var isMarketingFixtureImporterPresented = false

    var body: some View {
        Section {
            LabeledContent("デモデータ", value: isInstalled ? "追加済み" : "未追加")

            if isInstalled {
                Button("デモデータを削除", systemImage: "trash", role: .destructive, action: remove)
            } else {
                Button("7日分のデモデータを追加", systemImage: "sparkles", action: install)
            }

            Divider()

            LabeledContent("撮影素材Fixture", value: fixturePath == nil ? "未検出" : "検出済み")

            Button("Fixtureで撮影用データに置き換え", systemImage: "camera.metering.matrix") {
                isMarketingImportConfirmationPresented = true
            }
            .disabled(fixturePath == nil)

            Button("Fixture JSONを選んで読み込む", systemImage: "doc.badge.plus") {
                isMarketingFixtureImporterPresented = true
            }

            if let importResult {
                Text("読み込み済み: 滞在/移動 \(importResult.episodes)件、場所 \(importResult.places)件、位置点 \(importResult.rawLocations)件")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("開発")
        } footer: {
            Text("Debugビルドだけに表示されます。Fixture読み込みは既存の位置履歴・日記・修正履歴を撮影用データで全置換します。")
        }
        .task {
            await refreshState()
        }
        .confirmationDialog(
            "撮影用データで全置換しますか？",
            isPresented: $isMarketingImportConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("全データを置き換える", role: .destructive, action: importMarketingFixture)
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("現在のDebugビルド内データは削除され、FixtureのTimeline・場所・位置点・日記・修正履歴に置き換わります。")
        }
        .fileImporter(
            isPresented: $isMarketingFixtureImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importMarketingFixtureFile
        )
        .alert(
            "開発データを更新できません",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) { } message: {
            Text(errorMessage ?? "")
        }
    }

    private func install() {
        do {
            try DebugDemoDataService().install(in: modelContext)
            WidgetSnapshotService.refresh(in: modelContext)
            isInstalled = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try DebugDemoDataService().remove(in: modelContext)
            WidgetSnapshotService.refresh(in: modelContext)
            isInstalled = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshState() async {
        do {
            isInstalled = try DebugDemoDataService().isInstalled(in: modelContext)
            fixturePath = DebugMarketingFixtureService().fixtureURL()?.path
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importMarketingFixture() {
        do {
            let service = DebugMarketingFixtureService()
            importResult = try service.importFixture(in: modelContext)
            WidgetSnapshotService.refresh(in: modelContext)
            isInstalled = try DebugDemoDataService().isInstalled(in: modelContext)
            fixturePath = service.fixtureURL()?.path
        } catch {
            errorMessage = [
                error.localizedDescription,
                (error as? LocalizedError)?.recoverySuggestion
            ]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        }
    }

    private func importMarketingFixtureFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let service = DebugMarketingFixtureService()
            importResult = try service.importFixture(from: url, in: modelContext)
            WidgetSnapshotService.refresh(in: modelContext)
            isInstalled = try DebugDemoDataService().isInstalled(in: modelContext)
            fixturePath = service.fixtureURL()?.path
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
