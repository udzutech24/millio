//
//  MainSurfaceStyle.swift
//  millio
//
//  Created by Codex on 05.04.2026.
//

import SwiftUI

/// Reusable surfaces for the redesigned main screen.
enum MainSurfaceStyle {
    static let outerFill = LinearGradient(
        colors: [
            Color(hex: "141821").opacity(0.96),
            Color(hex: "0A0D13").opacity(0.98)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let innerFill = LinearGradient(
        colors: [
            Color.white.opacity(0.065),
            Color.white.opacity(0.028)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let border = Color.white.opacity(0.09)
    static let secondaryBorder = Color.white.opacity(0.05)
    static let shadow = Color.black.opacity(0.28)
}

struct MainSectionSurfaceModifier: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MainSurfaceStyle.outerFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(0.18),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(MainSurfaceStyle.border, lineWidth: 0.8)
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                            .blur(radius: 0.5)
                            .mask(
                                LinearGradient(
                                    colors: [.white, .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .shadow(color: MainSurfaceStyle.shadow, radius: 22, x: 0, y: 14)
            )
    }
}

struct MainInnerSurfaceModifier: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MainSurfaceStyle.innerFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(0.10),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(MainSurfaceStyle.secondaryBorder, lineWidth: 0.8)
                    )
            )
    }
}

extension View {
    func mainSectionSurface(
        tint: Color = AppColors.brandPrimary,
        cornerRadius: CGFloat = 30
    ) -> some View {
        modifier(MainSectionSurfaceModifier(tint: tint, cornerRadius: cornerRadius))
    }

    func mainInnerSurface(
        tint: Color = AppColors.brandPrimary,
        cornerRadius: CGFloat = 24
    ) -> some View {
        modifier(MainInnerSurfaceModifier(tint: tint, cornerRadius: cornerRadius))
    }
}
