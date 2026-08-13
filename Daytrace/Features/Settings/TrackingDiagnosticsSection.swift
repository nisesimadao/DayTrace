import CoreLocation
import SwiftUI
import UIKit

struct TrackingDiagnosticsSection: View {
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
