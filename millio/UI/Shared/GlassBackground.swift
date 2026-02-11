//
//  GlassBackground.swift
//  millio
//
//  Created by Assistant on 10.01.2026.
//

import SwiftUI

struct GlassBackground: View {
    let gradient: [Color]
    let cornerRadius: CGFloat
    let strokeWidth: CGFloat
    let isActive: Bool
    
    init(
        gradient: [Color],
        cornerRadius: CGFloat = 20,
        strokeWidth: CGFloat? = nil,
        isActive: Bool = true
    ) {
        self.gradient = gradient
        self.cornerRadius = cornerRadius
        self.isActive = isActive
        // If strokeWidth is provided, use it. Otherwise 2 if active, 1 if inactive (matching SubscriptionView logic)
        self.strokeWidth = strokeWidth ?? (isActive ? 2 : 1)
    }
    
    var body: some View {
        let accentColor = gradient.first ?? .cyan
        let fillGradient = LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.07, blue: 0.11),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let glowGradient = LinearGradient(
            colors: [
                accentColor.opacity(0.18),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        
        let strokeGradient = isActive
            ? LinearGradient(
                colors: gradient,
                startPoint: .leading,
                endPoint: .trailing
            )
            : LinearGradient(
                colors: [AppColors.textPrimary.opacity(0.1), AppColors.textPrimary.opacity(0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillGradient)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(glowGradient)
                    .opacity(0.6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeGradient, lineWidth: strokeWidth)
            )
    }
}
