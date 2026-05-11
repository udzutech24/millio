//
//  FinanceTradeCelebrationOverlay.swift
//  millio
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct FinanceTradeCelebrationOverlay: View {
    let celebration: FinanceTradeCelebration
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var glowExpanded = false
    @State private var orbitDrift = false
    @State private var didScheduleDismiss = false
    @State private var isDismissing = false

    var body: some View {
        ZStack {
            Color.black.opacity(isVisible ? 0.42 : 0)
                .ignoresSafeArea()
                .onTapGesture(perform: dismissAnimated)

            VStack(spacing: 18) {
                heroOrb

                VStack(spacing: 8) {
                    Text(titleText)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(subtitleText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                Text(L("finances.dynamics.trade.celebration.badge"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.82))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                            )
                    )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 30)
            .frame(maxWidth: 340)
            .background(cardBackground)
            .overlay(cardStroke)
            .shadow(color: accentColor.opacity(0.24), radius: 28, y: 18)
            .scaleEffect(isVisible ? 1 : 0.9)
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible ? 0 : 10)
        }
        .compositingGroup()
        .sensoryFeedback(.success, trigger: celebration.id)
        .task(id: celebration.id) {
            await animatePresentation()
        }
    }

    private var titleText: String {
        switch celebration.side {
        case .buy:
            return L("finances.dynamics.trade.celebration.buy.title")
        case .sell:
            return L("finances.dynamics.trade.celebration.sell.title")
        }
    }

    private var subtitleText: String {
        let totalAmountText = FinanceAmountText.decimal(
            value: celebration.totalAmount,
            maximumFractionDigits: 2
        )
        let moneyText = "\(totalAmountText) \(celebration.currency)"
        switch celebration.side {
        case .buy:
            return FinancesL10n.format(
                "finances.dynamics.trade.celebration.buy.subtitle",
                celebration.investmentName,
                moneyText
            )
        case .sell:
            return FinancesL10n.format(
                "finances.dynamics.trade.celebration.sell.subtitle",
                celebration.investmentName,
                moneyText
            )
        }
    }

    private var accentColors: [Color] {
        switch celebration.side {
        case .buy:
            return [Color(hex: "6BE39A"), Color(hex: "29D3FF")]
        case .sell:
            return [Color(hex: "FF9A62"), Color(hex: "FF5E7A")]
        }
    }

    private var accentColor: Color {
        accentColors.first ?? .white
    }

    private var symbolName: String {
        switch celebration.side {
        case .buy:
            return "checkmark"
        case .sell:
            return "arrow.up.right"
        }
    }

    private var heroOrb: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accentColors[0].opacity(0.95),
                            accentColors[1].opacity(0.65),
                            Color.white.opacity(0.08)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 86
                    )
                )
                .frame(width: 110, height: 110)
                .blur(radius: glowExpanded ? 0 : 8)
                .scaleEffect(glowExpanded ? 1 : 0.82)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.7),
                            accentColor.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
                .frame(width: glowExpanded ? 136 : 112, height: glowExpanded ? 136 : 112)
                .opacity(reduceMotion ? 0.45 : 0.85)

            Circle()
                .fill(Color.white.opacity(0.13))
                .frame(width: 82, height: 82)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                )
                .background(.ultraThinMaterial, in: Circle())

            Image(systemName: symbolName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))

            floatingHighlight(size: 14, x: -52, y: orbitDrift ? -50 : -38, opacity: 0.95)
            floatingHighlight(size: 10, x: 46, y: orbitDrift ? 42 : 26, opacity: 0.7)
            floatingHighlight(size: 8, x: orbitDrift ? -38 : -26, y: 48, opacity: 0.55)
        }
        .frame(height: 140)
    }

    private func floatingHighlight(size: CGFloat, x: CGFloat, y: CGFloat, opacity: CGFloat) -> some View {
        Circle()
            .fill(Color.white.opacity(opacity))
            .frame(width: size, height: size)
            .blur(radius: 0.4)
            .offset(x: x, y: y)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.12, blue: 0.16).opacity(0.96),
                        Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        accentColor.opacity(0.32),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private func animatePresentation() async {
        guard !didScheduleDismiss else { return }
        didScheduleDismiss = true

        Task {
            await playHaptics()
        }

        withAnimation(.spring(response: 0.62, dampingFraction: 0.86)) {
            isVisible = true
        }
        withAnimation(
            reduceMotion
                ? .easeOut(duration: 0.24)
                : .spring(response: 0.8, dampingFraction: 0.7).delay(0.05)
        ) {
            glowExpanded = true
        }
        withAnimation(
            reduceMotion
                ? .linear(duration: 0.01)
                : .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
        ) {
            orbitDrift = true
        }

        try? await Task.sleep(for: .seconds(reduceMotion ? 1.8 : 2.4))
        dismissAnimated()
    }

    @MainActor
    private func playHaptics() async {
        #if canImport(UIKit)
        let events = FinanceTradeCelebrationHapticsPlan.events(
            for: celebration.side,
            reduceMotion: reduceMotion
        )
        var elapsed: UInt64 = 0

        for event in events {
            let delta = event.delayNanoseconds > elapsed ? (event.delayNanoseconds - elapsed) : 0
            if delta > 0 {
                try? await Task.sleep(nanoseconds: delta)
            }

            switch event.kind {
            case .softImpact:
                let generator = UIImpactFeedbackGenerator(style: .soft)
                generator.prepare()
                generator.impactOccurred(intensity: event.intensity)
            case .lightImpact:
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred(intensity: event.intensity)
            case .mediumImpact:
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred(intensity: event.intensity)
            case .rigidImpact:
                let generator = UIImpactFeedbackGenerator(style: .rigid)
                generator.prepare()
                generator.impactOccurred(intensity: event.intensity)
            case .successNotification:
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.success)
            }

            elapsed = event.delayNanoseconds
        }
        #endif
    }

    private func dismissAnimated() {
        guard !isDismissing else { return }
        isDismissing = true

        withAnimation(.easeInOut(duration: 0.24)) {
            isVisible = false
        }

        Task {
            try? await Task.sleep(for: .milliseconds(240))
            await MainActor.run {
                onDismiss()
            }
        }
    }
}
