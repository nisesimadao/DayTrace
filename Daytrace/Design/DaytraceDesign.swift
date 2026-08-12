import SwiftUI

enum DS {
    static let horizontalPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 28
    static let compactSpacing: CGFloat = 10
    static let timelineDot: CGFloat = 12
    static let timelineLine: CGFloat = 2
    static let mapHeight: CGFloat = 142

    static let contentCornerRadius: CGFloat = 22
    static let controlCornerRadius: CGFloat = 18
}

struct GlassActionButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                configuration.label
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(
                        prominent
                            ? .regular.tint(.accentColor.opacity(0.22)).interactive()
                            : .regular.interactive(),
                        in: .rect(cornerRadius: DS.controlCornerRadius)
                    )
            } else {
                configuration.label
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(
                        prominent ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(.thinMaterial),
                        in: RoundedRectangle(cornerRadius: DS.controlCornerRadius, style: .continuous)
                    )
            }
        }
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassActionButtonStyle {
    static var daytraceGlass: GlassActionButtonStyle { .init(prominent: false) }
    static var daytraceGlassProminent: GlassActionButtonStyle { .init(prominent: true) }
}
