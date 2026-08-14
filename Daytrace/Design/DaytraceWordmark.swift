import SwiftUI

struct DaytraceWordmark: View {
    var markSize: Double = 27
    var color: Color? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("D")
            DaytraceBrandMark(size: markSize, showsBackground: false)
                .padding(.horizontal, 1)
            Text("ytrace")
        }
        .font(.system(.headline, design: .rounded, weight: .bold))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .foregroundStyle(wordmarkColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("DayTrace")
    }

    private var wordmarkColor: Color {
        color ?? .primary
    }
}
