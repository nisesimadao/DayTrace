import SwiftUI

struct DaytraceWordmark: View {
    var markSize: Double = 27
    var color: Color? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            DaytraceBrandMark(size: markSize, showsBackground: false)
            Text("DayTrace")
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
