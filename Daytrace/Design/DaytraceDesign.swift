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
    static let cardPadding: CGFloat = 18
}

extension Color {
    static let daytraceInk = Color(red: 0.035, green: 0.122, blue: 0.263)
    static let daytraceCoral = Color(red: 1.000, green: 0.604, blue: 0.455)
    static let daytraceCoralSoft = Color(red: 1.000, green: 0.788, blue: 0.702)
    static let daytraceSeafoam = Color(red: 0.388, green: 0.792, blue: 0.706)
    static let daytracePaper = Color(red: 0.988, green: 0.969, blue: 0.929)
}

struct GlassActionButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
        .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassActionButtonStyle {
    static var daytraceGlass: GlassActionButtonStyle { .init(prominent: false) }
    static var daytraceGlassProminent: GlassActionButtonStyle { .init(prominent: true) }
}

struct DaytraceRowLinkButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.992 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DaytraceRowLinkButtonStyle {
    static var daytraceRowLink: DaytraceRowLinkButtonStyle { .init() }
}

private struct DaytraceGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(
                    interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                content.glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
            }
        } else {
            content.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

extension View {
    func daytraceGlassSurface(
        cornerRadius: CGFloat = DS.contentCornerRadius,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(
            DaytraceGlassSurface(
                cornerRadius: cornerRadius,
                interactive: interactive,
                tint: tint
            )
        )
    }

    @ViewBuilder
    func daytraceModernTabBar() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
