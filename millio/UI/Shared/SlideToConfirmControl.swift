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
                        .font(.system(size: 15, weight: .semibold))
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
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }

    private func handleDragProgress(offset: CGFloat, maxOffset: CGFloat) {
        guard maxOffset > 0 else { return }
        let progress = offset / maxOffset
        let currentStep = SlideToConfirmHapticsPlan.progressStep(for: Double(progress))

        if currentStep > lastHapticStep {
            triggerProgressHaptic()
        }

        lastHapticStep = currentStep
    }

    private func resetSliderPosition() {
        lastHapticStep = -1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = 0
        }
    }

    private func triggerProgressHaptic() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    private func triggerSuccessHaptic() {
        #if canImport(UIKit)
        let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)
        impactGenerator.prepare()
        impactGenerator.impactOccurred(intensity: 1)

        let notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)
        #endif
    }
}
