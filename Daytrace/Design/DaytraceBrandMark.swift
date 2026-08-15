import SwiftUI

struct DaytraceBrandMark: View {
    var size: Double = 80
    var showsBackground = true

    var body: some View {
        Image("DaytraceBrandMark")
            .resizable()
            .scaledToFit()
            .padding(showsBackground ? size * 0.08 : 0)
            .frame(width: size, height: size)
            .background(showsBackground ? Color.daytracePaper : .clear)
            .clipShape(.rect(cornerRadius: showsBackground ? size * 0.22 : 0))
            .accessibilityHidden(true)
    }
}
