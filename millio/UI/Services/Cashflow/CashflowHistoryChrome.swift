//
//  CashflowHistoryChrome.swift
//  millio
//
//  Общий visual chrome для экрана истории операций.
//  Держим метрики и поверхности рядом, чтобы summary, фильтры и список
//  выглядели как одна система, а не как набор разрозненных карточек.
//

import SwiftUI

enum CashflowHistoryChrome {
    static let summaryCornerRadius: CGFloat = 26
    static let chipCornerRadius: CGFloat = 18
    static let rowCornerRadius: CGFloat = 20
    static let toolbarControlSize: CGFloat = 42

    static let subduedStroke = Color.white.opacity(0.10)
    static let strongStroke = Color.white.opacity(0.18)
    static let quietFill = Color.white.opacity(0.04)
    static let elevatedFill = Color.white.opacity(0.06)
    static let accentColor = Color(hex: "47D7FF")
    static let selectionFill = accentColor.opacity(0.13)
    static let selectionStroke = accentColor.opacity(0.38)
}

struct CashflowHistorySurfaceBackground: View {
    let cornerRadius: CGFloat
    let accentColor: Color
    let isElevated: Bool

    init(
        cornerRadius: CGFloat,
        accentColor: Color = CashflowHistoryChrome.accentColor,
        isElevated: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.isElevated = isElevated
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.055, green: 0.07, blue: 0.10).opacity(isElevated ? 0.98 : 0.92),
                        Color(red: 0.03, green: 0.04, blue: 0.06).opacity(0.96),
                        Color.black.opacity(0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(isElevated ? 0.12 : 0.08),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isElevated ? 0.20 : 0.14),
                                Color.white.opacity(0.06),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            )
    }
}

