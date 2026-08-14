#if DEBUG
import SwiftData
import SwiftUI

struct DebugDemoDataSettingsSection: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isInstalled = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            LabeledContent("デモデータ", value: isInstalled ? "追加済み" : "未追加")

            Button("7日分のデモデータを追加", systemImage: "sparkles", action: install)
                .disabled(isInstalled)

            if isInstalled {
                Button("デモデータを削除", systemImage: "trash", role: .destructive, action: remove)
            }
        } header: {
            Text("開発")
        } footer: {
            Text("Debugビルドだけに表示されます。日記・滞在・場所・今メモを追加し、同じ項目からデモ分だけ削除できます。")
        }
        .task {
            await refreshState()
        }
        .alert(
            "デモデータを更新できません",
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
