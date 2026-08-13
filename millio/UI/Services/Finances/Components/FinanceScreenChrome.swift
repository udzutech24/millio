//
//  FinanceScreenChrome.swift
//  millio
//
//  Общий visual chrome для финансовых экранов.
//  Держим базовые метрики и цвета централизованно, чтобы главный экран и динамика
//  не расходились по стилю.
//

import SwiftUI

enum FinanceScreenChrome {
    static let heroCornerRadius: CGFloat = 24
    static let sectionCornerRadius: CGFloat = 20
    static let groupRowCornerRadius: CGFloat = 20
    static let controlCornerRadius: CGFloat = 12
    static let actionSheetCornerRadius: CGFloat = 24
    static let headerControlSide: CGFloat = 36
    static let fabDiameter: CGFloat = 56
    static let fabIconSize: CGFloat = 20

    static let surfaceStrokeColor = Color.white.opacity(0.18)
    static let elevatedSurfaceStrokeColor = Color.white.opacity(0.22)

    static var accentColor: Color {
        AppColors.financesGradient.first ?? .cyan
    }

    /// Локальный accent для действий обновления.
    /// Не меняем глобальную finances-палитру приложения, чтобы не словить регрессии
    /// на других экранах ради одного popover.
    static let refreshOverlayAccent = Color(hex: "159A6C")
    static let refreshQuotesTint = Color(hex: "2FC08A")
    static let refreshStocksTint = Color(hex: "D7B45A")

    static var surfaceFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.06, blue: 0.10),
                Color(red: 0.02, green: 0.03, blue: 0.06),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var elevatedSurfaceFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.08, blue: 0.12),
                Color(red: 0.03, green: 0.05, blue: 0.08),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct FinanceChromeCardBackground: View {
    let cornerRadius: CGFloat
    let accentColor: Color
    let isElevated: Bool
    let showsStroke: Bool

    init(
        cornerRadius: CGFloat = FinanceScreenChrome.sectionCornerRadius,
        accentColor: Color = FinanceScreenChrome.accentColor,
        isElevated: Bool = false,
        showsStroke: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.isElevated = isElevated
        self.showsStroke = showsStroke
    }

    var body: some View {
        let fillGradient = isElevated
            ? FinanceScreenChrome.elevatedSurfaceFillGradient
            : FinanceScreenChrome.surfaceFillGradient
        let strokeColor = isElevated
            ? FinanceScreenChrome.elevatedSurfaceStrokeColor
            : FinanceScreenChrome.surfaceStrokeColor

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillGradient)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(isElevated ? 0.10 : 0.06), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(isElevated ? 0.7 : 0.45)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(showsStroke ? strokeColor : Color.clear, lineWidth: 0.9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        showsStroke
                            ? LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.05),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.6
                    )
            )
    }
}
