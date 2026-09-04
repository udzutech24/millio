import SwiftUI

/// Оформление экранов кредита. У каждого сервиса приложения свой акцент
/// (`CashflowSurfaceStyle`, `CashbackScreenStyle`) — у кредита это медь макета.
enum LoanScreenStyle {
    /// Медь #E0A458 — единственный цвет, которого не было в палитре (разведка UI §5).
    static let accent = Color(hex: "E0A458")
    /// Текст на медной заливке: белый по меди не читается, макет даёт тёмный #1A1206.
    static let accentContrast = Color(hex: "1A1206")
    /// Тихая кнопка рядом с акцентной — та же подложка, что у нейтральных действий вклада.
    static let quietFill = AppColors.iconBackground

    /// Тело долга и проценты — существующие роли палитры, новых токенов под один экран не заводим
    /// (спека §11): точные хексы макета отличаются от `positiveColor`/`negativeColor` оттенком.
    static let principalColor = AppColors.positiveColor
    static let interestColor = AppColors.negativeColor

    static let buttonCornerRadius: CGFloat = AppSpacing.m
    static let buttonHeight: CGFloat = 52
}
