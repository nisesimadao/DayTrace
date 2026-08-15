import SwiftUI

struct DaytraceDeviceTopBrand: View {
    let topInset: Double
    let availableWidth: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if topInset >= 55 {
            ZStack {
                DaytraceBrandMark(size: 24, showsBackground: false)
                    .offset(x: -min(availableWidth * 0.27, 112))

                Text("DayTrace")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.daytraceInk)
                    .offset(x: min(availableWidth * 0.22, 92))
            }
            .frame(height: 28)
            .offset(y: -(topInset / 2 + 14))
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}
