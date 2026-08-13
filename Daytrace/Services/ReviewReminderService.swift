import Foundation
import SwiftData
import UserNotifications

@MainActor
enum ReviewReminderService {
    static let enabledKey = "reviewReminderEnabled"
    static let hourKey = "reviewReminderHour"
    static let minuteKey = "reviewReminderMinute"

    static let defaultHour = 21
    static let defaultMinute = 0

    private static let identifierPrefix = "daytrace.review."
    private static let schedulingHorizonDays = 30

    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func refresh(in context: ModelContext, now: Date = .now) async throws {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else {
            await cancelAllManaged()
            return
        }

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            await cancelAllManaged()
            return
        }

        let journals = try context.fetch(FetchDescriptor<JournalEntry>())
        let completedDays = Set(journals.map { TimelineDayProjection.day(for: $0) })
        let hour = storedHour
        let minute = storedMinute
        let calendar = Calendar.current

        await cancelAllManaged()

        for offset in 0..<schedulingHorizonDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let day = CalendarDay(containing: date, timeZone: .current)
            guard !completedDays.contains(day) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = minute
            components.second = 0
            components.timeZone = .current

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            guard let triggerDate = trigger.nextTriggerDate(), triggerDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "今日を振り返る？"
            content.body = "今日の記録を見返して、残したいことを書いておけます。"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifier(for: day),
                content: content,
                trigger: trigger
            )
            try await UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancel(for day: CalendarDay) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(for: day)]
        )
    }

    static func disable() async {
        UserDefaults.standard.set(false, forKey: enabledKey)
        await cancelAllManaged()
    }

    static var storedHour: Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: hourKey) != nil else {
            defaults.set(defaultHour, forKey: hourKey)
            return defaultHour
        }
        return min(max(defaults.integer(forKey: hourKey), 0), 23)
    }

    static var storedMinute: Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: minuteKey) != nil else {
            defaults.set(defaultMinute, forKey: minuteKey)
            return defaultMinute
        }
        return min(max(defaults.integer(forKey: minuteKey), 0), 59)
    }

    static func identifier(for day: CalendarDay) -> String {
        String(
            format: "%@%04d-%02d-%02d",
            identifierPrefix,
            day.year,
            day.month,
            day.day
        )
    }

    private static func cancelAllManaged() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let managedIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        guard !managedIDs.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: managedIDs)
    }
}
