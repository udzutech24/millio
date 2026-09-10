//
//  AIChatOrb.swift
//  millio
//

import SwiftUI

/// Орб чата: угловой градиент под размытием, медленно вращающийся вокруг центра.
/// Шейдеров здесь намеренно нет — крутится один слой, это дёшево и не роняет кадры на списке.
struct AIChatOrb: View {
    var diameter: CGFloat = 96
    /// Идёт генерация — орб дышит. В покое анимация только вращения.
    var isActive: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0
    @State private var pulse: Bool = false

    /// Замкнутый набор цветов: без повтора первого цвета в конце на шве видна резкая граница.
    private var ring: [Color] {
        let base = AppColors.financesGradient
        return base + base.reversed() + [base.first ?? .cyan]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: ring, center: .center))
                .blur(radius: diameter * 0.16)
                .rotationEffect(.degrees(angle))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.55), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.46
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(pulse ? 1.05 : 1)
        .onAppear { startAnimations() }
        .onChange(of: isActive) { _, _ in updatePulse() }
        .accessibilityHidden(true)
    }

    private func startAnimations() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
            angle = 360
        }
        updatePulse()
    }

    private func updatePulse() {
        guard !reduceMotion else { return }
        if isActive {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        } else {
            withAnimation(AppAnimation.springGentle) { pulse = false }
        }
    }
}
