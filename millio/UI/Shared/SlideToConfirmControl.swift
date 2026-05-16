//
//  SlideToConfirmControl.swift
//  millio
//
//  Created by Codex on 06.03.2026.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SlideToConfirmControl: View {
    let title: String
    let subtitle: String
    let loadingTitle: String
    let loadingSubtitle: String
    let icon: String
    let gradientColors: [Color]
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var lastHapticStep: Int = -1

    private let knobSize: CGFloat = 56
    private let horizontalPadding: CGFloat = 8

    init(
        title: String,
        subtitle: String,
        loadingTitle: String = "Создаем резервную копию...",
        loadingSubtitle: String? = nil,
        icon: String,
        gradientColors: [Color],
        isEnabled: Bool,
        isLoading: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.loadingTitle = loadingTitle
        self.loadingSubtitle = loadingSubtitle ?? subtitle
        self.icon = icon
        self.gradientColors = gradientColors
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        GeometryReader { proxy in
            let maxOffset = max(0, proxy.size.width - knobSize - horizontalPadding * 2)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    )

                VStack(alignment: .center, spacing: 3) {
                    Text(isLoading ? loadingTitle : title)
                        .font(.millioSubheadline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(isLoading ? loadingSubtitle : subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, knobSize)

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: knobSize, height: knobSize)
                .padding(.leading, horizontalPadding)
                .offset(x: dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            guard isEnabled, !isLoading else { return }
                            let nextOffset = min(max(0, value.translation.width), maxOffset)
                            dragOffset = nextOffset
                            handleDragProgress(offset: nextOffset, maxOffset: maxOffset)
                        }
                        .onEnded { _ in
                            guard isEnabled, !isLoading else {
                                resetSliderPosition()
                                return
                            }
                            let progress = maxOffset > 0 ? dragOffset / maxOffset : 0
                            if SlideToConfirmHapticsPlan.isCompletionReached(for: Double(progress)) {
                                triggerSuccessHaptic()
                                action()
                            }
                            resetSliderPosition()
                        }
                )
                .allowsHitTesting(isEnabled && !isLoading)
            }
        }
        .frame(height: 72)
        .opacity(isEnabled || isLoading ? 1 : 0.45)
        .animation(AppAnimation.standard, value: isEnabled)
        .animation(AppAnimation.standard, value: isLoading)
    }

    private func handleDragProgress(offset: CGFloat, maxOffset: CGFloat) {
        guard maxOffset > 0 else { return }
        let progress = offset / maxOffset
        let currentStep = SlideToConfirmHapticsPlan.progressStep(for: Double(progress))

        if currentStep > lastHapticStep,
           let feedback = SlideToConfirmHapticsPlan.feedback(for: currentStep) {
            triggerProgressHaptic(feedback)
        }

        lastHapticStep = currentStep
    }

    private func resetSliderPosition() {
        lastHapticStep = -1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = 0
        }
    }

    private func triggerProgressHaptic(_ feedback: SlideToConfirmHapticsPlan.ProgressFeedback) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: impactStyle(for: feedback.style))
        generator.prepare()
        generator.impactOccurred(intensity: feedback.intensity)
        #endif
    }

    private func triggerSuccessHaptic() {
        #if canImport(UIKit)
        let feedback = SlideToConfirmHapticsPlan.completionFeedback
        let impactGenerator = UIImpactFeedbackGenerator(style: impactStyle(for: feedback.primaryStyle))
        impactGenerator.prepare()
        impactGenerator.impactOccurred(intensity: feedback.primaryIntensity)

        DispatchQueue.main.asyncAfter(deadline: .now() + feedback.settleDelay) {
            let settleGenerator = UIImpactFeedbackGenerator(style: impactStyle(for: feedback.settleStyle))
            settleGenerator.prepare()
            settleGenerator.impactOccurred(intensity: feedback.settleIntensity)

            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(.success)
        }
        #endif
    }

    #if canImport(UIKit)
    private func impactStyle(for style: SlideToConfirmHapticsPlan.ImpactStyle) -> UIImpactFeedbackGenerator.FeedbackStyle {
        switch style {
        case .soft:
            return .soft
        case .light:
            return .light
        case .medium:
            return .medium
        case .rigid:
            return .rigid
        case .heavy:
            return .heavy
        }
    }
    #endif
}
