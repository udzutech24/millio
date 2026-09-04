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

    // MARK: - Досрочное погашение (ЭКРАН 4)

    /// Подложка тега выгоды и карточки экономии — та же зелень, что у тела долга, приглушённая до
    /// фона. Отдельного токена под неё не заводим: цвет тот же, меняется только насыщенность.
    static let positiveFill = AppColors.positiveColor.opacity(0.10)
    /// Та же роль для роста переплаты при недоплате.
    static let negativeFill = AppColors.negativeColor.opacity(0.10)
    static let radioSize: CGFloat = 20
    static let radioDotSize: CGFloat = 10

    // MARK: - График платежей (ЭКРАН 3)

    /// Подсветка текущего периода: та же подложка, что у тихой кнопки, приглушённая до фона строки —
    /// на полную яркость `iconBackground` двухцветная полоса теряет контраст.
    static let currentRowFill = AppColors.iconBackground.opacity(0.4)
    /// Внесённые платежи не прячем, а приглушаем: строка «N впереди» на деталке должна сходиться
    /// с тем, что видно на экране.
    static let paidRowOpacity: Double = 0.45
    static let shareBarHeight: CGFloat = 8
    /// Колонки строки графика фиксированы, иначе полосы 60 строк встали бы «лесенкой»
    /// (у дифференцированного графика сумма платежа в каждой строке своя).
    static let scheduleMonthColumnWidth: CGFloat = 62
    static let scheduleAmountColumnWidth: CGFloat = 96
    static let scheduleRowHeight: CGFloat = 40
}
