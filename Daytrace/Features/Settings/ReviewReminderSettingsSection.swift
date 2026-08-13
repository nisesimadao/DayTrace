import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct ReviewReminderSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(ReviewReminderService.enabledKey) private var reviewReminderEnabled = false
    @AppStorage(ReviewReminderService.hourKey) private var reviewReminderHour = ReviewReminderService.defaultHour
    @AppStorage(ReviewReminderService.minuteKey) private var reviewReminderMinute = ReviewReminderService.defaultMinute

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var errorMessage: String?

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { reviewReminderEnabled },
            set: { enabled in
                if enabled {
                    Task { @MainActor in
                        await enableReminder()
                    }
                } else {
                    reviewReminderEnabled = false
                    Task { @MainActor in
                        await ReviewReminderService.disable()
                        authorizationStatus = await ReviewReminderService.authorizationStatus()
                    }
                }
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: reviewReminderHour,
                    minute: reviewReminderMinute,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                reviewReminderHour = components.hour ?? ReviewReminderService.defaultHour
                reviewReminderMinute = components.minute ?? ReviewReminderService.defaultMinute

                guard reviewReminderEnabled else { return }
                Task { @MainActor in
                    do {
                        try await ReviewReminderService.refresh(in: modelContext)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    var body: some View {
        Section {
            Toggle("夜に振り返る", isOn: reminderBinding)

            if reviewReminderEnabled {
                DatePicker(
                    "通知時刻",
                    selection: reminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )
            }

            if authorizationStatus == .denied {
                Button("通知設定を開く") {
                    openSystemSettings()
                }
            }
        } header: {
            Text("振り返り")
        } footer: {
            Text("指定した時刻に一度だけ振り返りを促します。通知には場所名を表示しません。日記を書いた日は、その日の通知を取り消します。")
        }
        .alert(
            "振り返り通知を設定できません",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await synchronizeAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { @MainActor in
                await synchronizeAuthorization()
            }
        }
    }

    @MainActor
    private func enableReminder() async {
        do {
            var status = await ReviewReminderService.authorizationStatus()

            if status == .notDetermined {
                let granted = try await ReviewReminderService.requestAuthorization()
                status = await ReviewReminderService.authorizationStatus()
                authorizationStatus = status
                guard granted else {
                    reviewReminderEnabled = false
                    errorMessage = "通知が許可されませんでした。必要ならiPhoneの設定から通知を有効にできます。"
                    return
                }
            }

            guard isUsable(status) else {
                authorizationStatus = status
                reviewReminderEnabled = false
                errorMessage = "通知がiPhoneの設定でオフになっています。"
                return
            }

            authorizationStatus = status
            reviewReminderEnabled = true
            try await ReviewReminderService.refresh(in: modelContext)
        } catch {
            reviewReminderEnabled = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func synchronizeAuthorization() async {
        let status = await ReviewReminderService.authorizationStatus()
        authorizationStatus = status

        guard reviewReminderEnabled, !isUsable(status) else { return }
        await ReviewReminderService.disable()
    }

    private func isUsable(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
