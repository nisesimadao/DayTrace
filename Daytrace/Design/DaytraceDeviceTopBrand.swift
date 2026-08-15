import SwiftUI

struct DaytraceDeviceTopBrand: View {
    let topInset: Double
    let availableWidth: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if topInset >= 55 {
            ZStack {
                if availableWidth >= 440 {
                    Text("DayTrace")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.daytraceInk)
                    .offset(x: 112)
                }

                DaytraceBrandMark(size: 24, showsBackground: false)
            }
            .frame(height: 28)
            .offset(y: -topInset + 10)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}
