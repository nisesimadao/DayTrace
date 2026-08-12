import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationRecorder.self) private var recorder

    @AppStorage("detailedRoutesEnabled") private var detailedRoutesEnabled = false
    @AppStorage("rawEvidenceRetentionDays") private var rawEvidenceRetentionDays = 90

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("状態", value: healthLabel)
                    LabeledContent("位置情報", value: authorizationLabel)

                    Toggle("詳細な移動経路を記録", isOn: $detailedRoutesEnabled)
                        .onChange(of: detailedRoutesEnabled) { _, enabled in
                            recorder.setDetailedRoutesEnabled(enabled)
                        }
                } header: {
                    Text("自動記録")
                } footer: {
                    Text("詳細な経路は必要な場面で位置更新を増やすため、バッテリー消費が増える場合があります。")
                }

                Section("プライバシー") {
                    Picker("生の位置データ", selection: $rawEvidenceRetentionDays) {
                        Text("30日").tag(30)
                        Text("90日").tag(90)
                        Text("1年").tag(365)
                        Text("ずっと").tag(0)
                    }
                    Text("日記と確定したTimelineは、生のGPSサンプルとは別に保存されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("データ") {
                    LabeledContent("保存先", value: "このiPhone")
                    Button("書き出す") { }
                        .disabled(true)
                    Text("JSON / GPX / Markdown書き出しは次のマイルストーンで接続します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
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
