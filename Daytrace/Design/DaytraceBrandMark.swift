import SwiftUI

struct DaytraceBrandMark: View {
    var size: Double = 80
    var showsBackground = true

    var body: some View {
        ZStack {
            if showsBackground {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            }

            mascot
                .padding(showsBackground ? size * 0.08 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var mascot: some View {
        ZStack {
            Circle()
                .fill(navyGradient)
                .frame(width: size * 0.76, height: size * 0.76)
                .offset(x: -size * 0.045, y: size * 0.015)

            DaytraceStemShape()
                .fill(navyGradient)

            Circle()
                .fill(apricotGradient)
                .frame(width: size * 0.58, height: size * 0.58)
                .offset(x: -size * 0.045, y: size * 0.015)

            eye(x: -0.17)
            eye(x: 0.09)

            Path { path in
                path.move(to: CGPoint(x: size * 0.39, y: size * 0.58))
                path.addCurve(
                    to: CGPoint(x: size * 0.57, y: size * 0.58),
                    control1: CGPoint(x: size * 0.43, y: size * 0.65),
                    control2: CGPoint(x: size * 0.53, y: size * 0.65)
                )
            }
            .stroke(
                Color.daytraceInk,
                style: StrokeStyle(lineWidth: size * 0.052, lineCap: .round)
            )

            Image(systemName: "sparkle")
                .font(.system(size: size * 0.13, weight: .semibold))
                .foregroundStyle(Color.daytraceSeafoam)
                .offset(x: size * 0.31, y: -size * 0.34)
        }
        .frame(width: size, height: size)
        .compositingGroup()
    }

    private func eye(x: Double) -> some View {
        Capsule()
            .fill(navyGradient)
            .frame(width: size * 0.105, height: size * 0.15)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.92))
                    .frame(width: size * 0.036, height: size * 0.036)
                    .padding(size * 0.016)
            }
            .offset(x: size * x, y: -size * 0.055)
    }

    private var navyGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.07, green: 0.16, blue: 0.34), Color.daytraceInk],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var apricotGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.74, blue: 0.61), Color(red: 0.98, green: 0.59, blue: 0.43)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct DaytraceStemShape: Shape {
    func path(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.63, 0.22))
        path.addCurve(to: point(0.76, 0.34), control1: point(0.71, 0.22), control2: point(0.76, 0.27))
        path.addLine(to: point(0.76, 0.70))
        path.addCurve(to: point(0.83, 0.76), control1: point(0.76, 0.74), control2: point(0.79, 0.74))
        path.addCurve(to: point(0.85, 0.86), control1: point(0.88, 0.78), control2: point(0.88, 0.83))
        path.addCurve(to: point(0.76, 0.91), control1: point(0.83, 0.90), control2: point(0.78, 0.92))
        path.addCurve(to: point(0.68, 0.82), control1: point(0.71, 0.90), control2: point(0.68, 0.87))
        path.addLine(to: point(0.68, 0.38))
        path.addCurve(to: point(0.63, 0.22), control1: point(0.68, 0.30), control2: point(0.66, 0.25))
        path.closeSubpath()
        return path
    }
}
