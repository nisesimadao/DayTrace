import SwiftUI

struct DaytraceBrandMark: View {
    var size: Double = 80
    var showsBackground = true

    var body: some View {
        ZStack {
            if showsBackground {
                Rectangle()
                    .fill(Color.daytracePaper)
            }

            DaytracePageShape()
                .stroke(
                    Color.daytraceIndigo,
                    style: StrokeStyle(
                        lineWidth: size * 0.075,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            DaytraceRouteShape()
                .stroke(
                    Color.daytraceIndigo,
                    style: StrokeStyle(
                        lineWidth: size * 0.065,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            Circle()
                .fill(Color.daytraceTerracotta)
                .frame(width: size * 0.105, height: size * 0.105)
                .offset(x: size * 0.205, y: -size * 0.095)
        }
        .padding(size * 0.17)
        .frame(width: size, height: size)
        .background(showsBackground ? Color.daytracePaper : .clear)
        .clipShape(.rect(cornerRadius: showsBackground ? size * 0.22 : 0))
        .accessibilityHidden(true)
    }
}

private struct DaytracePageShape: Shape {
    func path(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.20, 0.08))
        path.addLine(to: point(0.64, 0.08))
        path.addLine(to: point(0.90, 0.34))
        path.addLine(to: point(0.90, 0.78))
        path.addCurve(to: point(0.70, 0.94), control1: point(0.90, 0.88), control2: point(0.82, 0.94))
        path.addLine(to: point(0.20, 0.94))
        path.addCurve(to: point(0.08, 0.80), control1: point(0.12, 0.94), control2: point(0.08, 0.88))
        path.addLine(to: point(0.08, 0.22))
        path.addCurve(to: point(0.20, 0.08), control1: point(0.08, 0.14), control2: point(0.13, 0.08))
        path.closeSubpath()

        path.move(to: point(0.64, 0.09))
        path.addLine(to: point(0.64, 0.31))
        path.addCurve(to: point(0.87, 0.34), control1: point(0.64, 0.33), control2: point(0.80, 0.34))
        return path
    }
}

private struct DaytraceRouteShape: Shape {
    func path(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.18, 0.82))
        path.addCurve(to: point(0.54, 0.62), control1: point(0.28, 0.68), control2: point(0.50, 0.75))
        path.addCurve(to: point(0.35, 0.49), control1: point(0.58, 0.54), control2: point(0.35, 0.57))
        path.addCurve(to: point(0.70, 0.43), control1: point(0.35, 0.42), control2: point(0.58, 0.43))
        return path
    }
}
