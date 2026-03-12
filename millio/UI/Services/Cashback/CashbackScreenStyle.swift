//
//  CashbackScreenStyle.swift
//  millio
//
//  Created by Codex on 03.03.2026.
//

import SwiftUI

enum CashbackScreenStyle {
    static let rowCornerRadius: CGFloat = 18
    static let neonCyan = Color(hex: "47D7FF")
    static let neonViolet = Color(hex: "8A6BFF")
    static let accent: Color = AppColors.cashbackGradient.first ?? .purple
    static let accentSoft = Color(hex: "6FD9FF")
    static let mintAccent = Color(hex: "72F1D3")
    static let deepBlue = Color(hex: "0D1424")
    static let deepNavy = Color(hex: "111A30")

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

    static let heroFill = LinearGradient(
        colors: [
            deepBlue,
            deepNavy,
            Color(hex: "19243F")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroStroke = LinearGradient(
        colors: [
            accentSoft.opacity(0.65),
            neonViolet.opacity(0.25),
            Color.white.opacity(0.14)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let spotlightFill = LinearGradient(
        colors: [
            Color(hex: "121625"),
            Color(hex: "171C30")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let spotlightStroke = LinearGradient(
        colors: [
            accent.opacity(0.45),
            Color.white.opacity(0.10)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let percentagePillFill = LinearGradient(
        colors: [
            accent.opacity(0.26),
            mintAccent.opacity(0.18)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let iconTintFill = LinearGradient(
        colors: [
            accent.opacity(0.24),
            neonViolet.opacity(0.16)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let converterRowFill = LinearGradient(
        colors: [Color(hex: "1F2430"), Color(hex: "1A1F2B")],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let iconBoxFill = Color(hex: "141A25")
    static let converterInactiveStroke = Color.white.opacity(0.07)
    static let converterActiveStroke = LinearGradient(
        colors: [
            neonCyan.opacity(0.72),
            neonViolet.opacity(0.62)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let showcaseCardFill = LinearGradient(
        colors: [
            Color(hex: "111827"),
            Color(hex: "1B2232"),
            Color(hex: "20283A")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let showcaseCardStroke = LinearGradient(
        colors: [
            Color(hex: "0A84FF").opacity(0.88),
            Color(hex: "00D1C7").opacity(0.88)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let showcaseInsetStroke = Color.white.opacity(0.06)
    static let showcaseStrokeWidth: CGFloat = 0.8
    static let showcasePercentTint = LinearGradient(
        colors: [
            Color(hex: "89C7FF"),
            Color.white,
            Color(hex: "6EF0E3")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
