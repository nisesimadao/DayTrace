import CoreLocation
import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(LocationRecorder.self) private var recorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var didRequestAlwaysAuthorization = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    OnboardingIntroPage()
                        .tag(0)
                    OnboardingLocationPage()
                        .tag(1)
                    OnboardingBackgroundPage()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 12) {
                    Button(actionTitle, action: primaryAction)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.daytraceGlassProminent)

                    if page > 0 {
                        Button("今はしない") {
                            advanceOrFinish()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, DS.horizontalPadding)
                .padding(.bottom, 28)
            }
        }
        .onChange(of: recorder.authorizationStatus) { _, status in
            guard page == 1 else { return }
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                withAnimation(reduceMotion ? nil : .snappy) { page = 2 }
            }
        }
    }

    private var actionTitle: String {
        switch page {
        case 0: "始める"
        case 1:
            recorder.authorizationStatus == .notDetermined ? "この場所を見る" : "次へ"
        default:
            recorder.authorizationStatus == .authorizedWhenInUse
                && recorder.canRequestAlwaysInApp
                && !didRequestAlwaysAuthorization
                    ? "閉じている間も記録する"
                    : "続ける"
        }
    }

    private func primaryAction() {
        switch page {
        case 0:
            withAnimation(reduceMotion ? nil : .snappy) { page = 1 }
        case 1:
            switch recorder.authorizationStatus {
            case .notDetermined:
                recorder.requestWhenInUse()
            case .authorizedWhenInUse, .authorizedAlways:
                withAnimation(reduceMotion ? nil : .snappy) { page = 2 }
            default:
                withAnimation(reduceMotion ? nil : .snappy) { page = 2 }
            }
        default:
            if recorder.authorizationStatus == .authorizedWhenInUse
                && recorder.canRequestAlwaysInApp
                && !didRequestAlwaysAuthorization {
                didRequestAlwaysAuthorization = true
                recorder.requestAlways()
            } else {
                onComplete()
            }
        }
    }

    private func advanceOrFinish() {
        if page < 2 {
            withAnimation(reduceMotion ? nil : .snappy) { page += 1 }
        } else {
            onComplete()
        }
    }
}

private struct OnboardingIntroPage: View {
    var body: some View {
        OnboardingPage(
            symbol: nil,
            eyebrow: "DAYTRACE",
            title: "今日を、あとから\n思い出せるように。",
            message: "訪れた場所や移動の断片を静かに記録して、夜には一日の流れを見返せます。"
        )
    }
}

private struct OnboardingLocationPage: View {
    var body: some View {
        OnboardingPage(
            symbol: "location",
            eyebrow: "位置情報",
            title: "まず、今いる場所から。",
            message: "位置情報は一日の流れを作るために使います。記録は端末内に保存され、あとから修正できます。"
        )
    }
}

private struct OnboardingBackgroundPage: View {
    @Environment(LocationRecorder.self) private var recorder

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text("自動記録")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text("開かなくても、\n一日は続いています。")
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)

                Text("「常に許可」にすると、アプリを閉じている間も訪問や移動を記録できます。あとからいつでも変更できます。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            Label(statusText, systemImage: statusSymbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 36)
    }

    private var statusText: String {
        switch recorder.authorizationStatus {
        case .authorizedAlways: "閉じている間も記録できます"
        case .authorizedWhenInUse: "今はアプリを開いている間だけ記録します"
        case .denied: "位置情報がオフです。あとで設定から変更できます"
        case .restricted: "この端末では位置情報の変更が制限されています"
        default: "許可状態を確認しています"
        }
    }

    private var statusSymbol: String {
        recorder.authorizationStatus == .authorizedAlways ? "checkmark.circle.fill" : "info.circle"
    }
}

private struct OnboardingPage: View {
    let symbol: String?
    let eyebrow: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 42, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            } else {
                DaytraceBrandMark(size: 88)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text(title)
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 36)
    }
}
