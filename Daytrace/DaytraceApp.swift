import SwiftData
import SwiftUI
import UIKit
import UserNotifications

final class DaytraceAppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if userInfo[ReviewReminderService.destinationKey] as? String == ReviewReminderService.todayDestination {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .daytraceOpenToday, object: nil)
            }
        }
        completionHandler()
    }
}

@main
struct DaytraceApp: App {
    @UIApplicationDelegateAdaptor(DaytraceAppDelegate.self) private var appDelegate

    private let container: ModelContainer = {
        let schema = Schema([
            LocationEvidence.self,
            VisitEvidence.self,
            PlaceRecord.self,
            TimelineEpisode.self,
            UserAssertion.self,
            JournalEntry.self,
            MomentNote.self,
        ])

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Daytrace store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(container)
    }
}
