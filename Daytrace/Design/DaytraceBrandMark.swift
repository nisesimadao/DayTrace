import SwiftUI

struct DaytraceBrandMark: View {
    var size: Double = 80
    var showsBackground = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("DaytraceBrandMark")
            .resizable()
            .scaledToFit()
            .padding(usesBackground ? size * 0.08 : 0)
            .frame(width: size, height: size)
            .background(usesBackground ? Color.daytracePaper : .clear)
            .clipShape(.rect(cornerRadius: usesBackground ? size * 0.22 : 0))
            .accessibilityHidden(true)
    }

    private var usesBackground: Bool {
        showsBackground || colorScheme == .dark
    }
}
