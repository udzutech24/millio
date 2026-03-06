//
//  SlideToConfirmControl.swift
//  millio
//
//  Created by Codex on 06.03.2026.
//

import SwiftUI

struct SlideToConfirmControl: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradientColors: [Color]
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    @State private var dragOffset: CGFloat = 0

    private let knobSize: CGFloat = 56
    private let horizontalPadding: CGFloat = 8

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
                    Text(isLoading ? "Создаем резервную копию..." : title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitle)
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
                            dragOffset = min(max(0, value.translation.width), maxOffset)
                        }
                        .onEnded { _ in
                            guard isEnabled, !isLoading else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                                return
                            }
                            if dragOffset >= maxOffset * 0.82 {
                                action()
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                )
                .allowsHitTesting(isEnabled && !isLoading)
            }
        }
        .frame(height: 72)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}
