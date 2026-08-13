import LocalAuthentication
import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appLockEnabled") private var appLockEnabled = false

    @State private var locationRecorder = LocationRecorder.shared
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var authenticationError: String?

    private var shouldCoverContent: Bool {
        scenePhase != .active || (appLockEnabled && !isUnlocked)
    }

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
            .overlay {
                if shouldCoverContent {
                    PrivacyCover(
                        isLocked: appLockEnabled && !isUnlocked,
                        isAuthenticating: isAuthenticating,
                        errorMessage: authenticationError,
                        retry: authenticateIfNeeded
                    )
                    .transition(.opacity)
                }
            }
            .task {
                locationRecorder.attach(context: modelContext)
                locationRecorder.configureIfNeeded()
                try? await ReviewReminderService.refresh(in: modelContext)
                WidgetSnapshotService.refresh(in: modelContext, force: true)

                if appLockEnabled, scenePhase == .active {
                    authenticateIfNeeded()
                } else if !appLockEnabled {
                    isUnlocked = true
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: ModelContext.didSave,
                    object: modelContext
                )
            ) { _ in
                WidgetSnapshotService.refresh(in: modelContext)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    WidgetSnapshotService.refresh(in: modelContext, force: true)
                    if appLockEnabled, !isUnlocked {
                        authenticateIfNeeded()
                    }
                case .inactive, .background:
                    WidgetSnapshotService.refresh(in: modelContext, force: true)
                    if appLockEnabled, !isAuthenticating {
                        isUnlocked = false
                    }
                @unknown default:
                    if appLockEnabled, !isAuthenticating {
                        isUnlocked = false
                    }
                }
            }
            .onChange(of: appLockEnabled) { _, enabled in
                authenticationError = nil
                WidgetSnapshotService.refresh(in: modelContext, force: true)
                if enabled {
                    // The user is already inside an unlocked session when enabling this.
                    // Lock from the next inactive/background transition onward.
                    isUnlocked = true
                } else {
                    isUnlocked = true
                    isAuthenticating = false
                }
            }
            .animation(.snappy(duration: 0.18), value: shouldCoverContent)
    }

    @MainActor
    private func authenticateIfNeeded() {
        guard appLockEnabled,
              scenePhase == .active,
              !isUnlocked,
              !isAuthenticating else {
            return
        }

        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            authenticationError = policyError?.localizedDescription
                ?? "端末のパスコードまたは生体認証を利用できません。"
            return
        }

        authenticationError = nil
        isAuthenticating = true

        Task { @MainActor in
            defer { isAuthenticating = false }
            do {
                let authenticated = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "位置履歴と日記を表示します"
                )
                if authenticated {
                    isUnlocked = true
                    authenticationError = nil
                }
            } catch {
                isUnlocked = false
                if let laError = error as? LAError,
                   laError.code == .userCancel || laError.code == .systemCancel {
                    authenticationError = nil
                } else {
                    authenticationError = error.localizedDescription
                }
            }
        }
    }
}

enum AppLockAvailability {
    static func canEnable() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
}

private struct PrivacyCover: View {
    let isLocked: Bool
    let isAuthenticating: Bool
    let errorMessage: String?
    let retry: @MainActor () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: isLocked ? "lock.fill" : "circle.dotted")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("DayTrace")
                    .font(.title2.bold())

                if isLocked {
                    if isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)
                        }

                        Button("ロック解除", action: retry)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(28)
        }
        .accessibilityElement(children: .contain)
    }
}
