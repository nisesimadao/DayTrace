import Foundation
import SwiftUI

extension Notification.Name {
    static let daytraceOpenToday = Notification.Name("daytrace.openToday")
}

struct AppShellView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView()
            }
            .tabItem {
                Label("今日", systemImage: "clock")
            }
            .tag(AppTab.today)

            NavigationStack {
                HistoryRootView()
            }
            .tabItem {
                Label("履歴", systemImage: "calendar")
            }
            .tag(AppTab.history)
        }
        .onReceive(NotificationCenter.default.publisher(for: .daytraceOpenToday)) { _ in
            selectedTab = .today
        }
        .onOpenURL { url in
            guard url.scheme == "daytrace" else { return }
            if url.host == "today" {
                selectedTab = .today
            }
        }
    }
}

enum AppTab: Hashable {
    case today
    case history
}
