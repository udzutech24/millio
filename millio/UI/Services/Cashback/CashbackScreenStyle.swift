//
//  CashbackScreenStyle.swift
//  millio
//
//  Created by Codex on 03.03.2026.
//

import SwiftUI

enum CashbackScreenStyle {
    static let neonCyan = Color(hex: "47D7FF")
    static let neonViolet = Color(hex: "8A6BFF")
    static let accent: Color = AppColors.cashbackGradient.first ?? .purple

    static let cardFill = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.07, blue: 0.11),
            Color.black
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let rowFill = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.14, blue: 0.23),
            Color(red: 0.07, green: 0.10, blue: 0.18)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let listFill = LinearGradient(
        colors: [
            Color(red: 0.13, green: 0.13, blue: 0.16),
            Color(red: 0.10, green: 0.10, blue: 0.13)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let neonBorder = LinearGradient(
        colors: [
            neonCyan.opacity(0.72),
            neonViolet.opacity(0.62)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let glow = LinearGradient(
        colors: [
            accent.opacity(0.18),
            Color.clear
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let subduedCircleFill = Color.white.opacity(0.08)

    static let fabFill = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.07, blue: 0.11),
            Color(red: 0.02, green: 0.04, blue: 0.06),
            Color.black
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let toolbarCapsuleFill = Color.white.opacity(0.08)
    static let toolbarCapsuleStroke = Color.white.opacity(0.14)
    static let rowDivider = Color.white.opacity(0.17)
}
