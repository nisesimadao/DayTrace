import SwiftUI

struct DaytraceDeviceTopBrand: View {
    let topInset: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if topInset >= 55 {
            ZStack {
                HStack(spacing: 0) {
                    Text("D")
                        .frame(width: 64, alignment: .trailing)

                    Color.clear
                        .frame(width: 132, height: 1)

                    Text("ytrace")
                        .frame(width: 90, alignment: .leading)
                }
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.daytraceInk)

                DaytraceBrandMark(size: 30, showsBackground: false)
            }
            .frame(height: 34)
            .offset(y: -topInset + 10)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}
