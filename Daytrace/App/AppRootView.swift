import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var locationRecorder = LocationRecorder.shared

    var body: some View {
        AppShellView()
            .environment(locationRecorder)
            .fullScreenCover(isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { if !$0 { hasCompletedOnboarding = true } }
            )) {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
                .environment(locationRecorder)
            }
            .task {
                locationRecorder.attach(context: modelContext)
                locationRecorder.configureIfNeeded()
            }
    }
}
