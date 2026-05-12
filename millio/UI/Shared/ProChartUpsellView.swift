//
//  ProChartUpsellView.swift
//  millio
//
//  Blur-preview upsell: показывает размытый фейковый график, поверх — тёмный оверлей и кнопка.
//  Пользователь видит «что теряет», а не пустой замок — конверсия выше.
//

import SwiftUI

struct ProChartUpsellMetrics: Equatable {
    enum Size: Equatable {
        case compact
        case regular
    }

    let titlePointSize: CGFloat
    let ctaPointSize: CGFloat
    let ctaVerticalPadding: CGFloat
    let blurRadius: CGFloat

    static func make(for size: Size) -> ProChartUpsellMetrics {
        switch size {
        case .compact:
            return .init(titlePointSize: 14, ctaPointSize: 13, ctaVerticalPadding: 8, blurRadius: 8)
        case .regular:
            return .init(titlePointSize: 15, ctaPointSize: 15, ctaVerticalPadding: 11, blurRadius: 10)
        }
    }
}

struct ProChartUpsellView: View {
    let titleKey: LocalizedStringKey?
    let subtitleKey: LocalizedStringKey?
    let ctaKey: LocalizedStringKey
    let size: ProChartUpsellMetrics.Size
    let onTapCTA: () -> Void

    private var metrics: ProChartUpsellMetrics {
        ProChartUpsellMetrics.make(for: size)
    }

    var body: some View {
        ZStack {
            FakeLineChartView()
                .blur(radius: metrics.blurRadius)
                .clipped()
                .overlay(Color.black.opacity(0.55))

            VStack(spacing: 10) {
                if let titleKey {
                    Text(titleKey)
                        .font(.system(size: metrics.titlePointSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                Button(action: onTapCTA) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: metrics.ctaPointSize - 2, weight: .semibold))
                        Text(ctaKey)
                            .font(.system(size: metrics.ctaPointSize, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 18)
                    .padding(.vertical, metrics.ctaVerticalPadding)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.07))
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(ctaKey))
            }
        }
    }
}

// MARK: - Fake chart background

private struct FakeLineChartView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts: [CGPoint] = [
                .init(x: 0,       y: h * 0.68),
                .init(x: w * 0.1, y: h * 0.58),
                .init(x: w * 0.2, y: h * 0.72),
                .init(x: w * 0.3, y: h * 0.48),
                .init(x: w * 0.42, y: h * 0.55),
                .init(x: w * 0.55, y: h * 0.32),
                .init(x: w * 0.65, y: h * 0.42),
                .init(x: w * 0.75, y: h * 0.28),
                .init(x: w * 0.88, y: h * 0.38),
                .init(x: w,       y: h * 0.22),
            ]

            // Залитая область под линией
            Path { path in
                path.move(to: .init(x: 0, y: h))
                path.addLine(to: pts[0])
                smoothCurve(through: pts, into: &path)
                path.addLine(to: .init(x: w, y: h))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color(hex: "4B76FF").opacity(0.55), Color(hex: "4B76FF").opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Линия графика
            Path { path in
                path.move(to: pts[0])
                smoothCurve(through: pts, into: &path)
            }
            .stroke(Color(hex: "5B86FF"), lineWidth: 2)

            // Точки на линии
            ForEach(Array(pts.enumerated()), id: \.offset) { _, pt in
                Circle()
                    .fill(Color(hex: "5B86FF"))
                    .frame(width: 4, height: 4)
                    .position(pt)
            }
        }
        .background(Color(hex: "0D0D1A"))
    }
}

struct FakeDonutBackground: View {
    let accentColor: Color

    var body: some View {
        HStack(spacing: 20) {
            Circle()
                .strokeBorder(accentColor.opacity(0.9), lineWidth: 24)
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 10) {
                ForEach([CGFloat(90), 65, 110], id: \.self) { w in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentColor.opacity(0.4))
                        .frame(width: w, height: 10)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private func smoothCurve(through pts: [CGPoint], into path: inout Path) {
    guard pts.count > 1 else { return }
    for i in 1..<pts.count {
        let prev = pts[i - 1], curr = pts[i]
        let cp1 = CGPoint(x: (prev.x + curr.x) / 2, y: prev.y)
        let cp2 = CGPoint(x: (prev.x + curr.x) / 2, y: curr.y)
        path.addCurve(to: curr, control1: cp1, control2: cp2)
    }
}
