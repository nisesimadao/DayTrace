import Foundation
import SwiftUI

extension Notification.Name {
    static let daytraceOpenToday = Notification.Name("daytrace.openToday")
}

struct AppShellView: View {
    @State private var selectedTab: AppTab

    init() {
#if DEBUG
        let requestedTab = ProcessInfo.processInfo.environment["DAYTRACE_START_TAB"]
        _selectedTab = State(initialValue: requestedTab == "history" ? .history : .today)
#else
        _selectedTab = State(initialValue: .today)
#endif
    }

    var body: some View {
        GeometryReader { geometry in
            TabView(selection: $selectedTab) {
                Tab("今日", systemImage: "sun.max", value: AppTab.today) {
                    NavigationStack {
                        TodayView()
                    }
                }

                Tab("履歴", systemImage: "calendar", value: AppTab.history) {
                    NavigationStack {
                        HistoryRootView()
                    }
                }
            }
            .daytraceModernTabBar()
            .overlay(alignment: .top) {
                DaytraceDeviceTopBrand(
                    topInset: geometry.safeAreaInsets.top,
                    availableWidth: geometry.size.width
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .daytraceOpenToday)) { _ in
                selectedTab = .today
            }
            .onOpenURL { url in
                guard url.scheme == "daytrace" else { return }
                switch url.host {
                case "today":
                    selectedTab = .today
                case "history":
                    selectedTab = .history
                default:
                    break
                }
            }
        }
    }
}

enum AppTab: Hashable {
    case today
    case history
}
