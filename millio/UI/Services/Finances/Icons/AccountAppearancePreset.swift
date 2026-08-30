import SwiftUI

/// Кодовый каталог дизайнов счёта (Ф2). В БД (`AccountAppearance.presetRaw`) хранится ТОЛЬКО
/// `rawValue`: добавление/правка пресета не требует миграции схемы и не раздувает бэкап.
///
/// Пары hex взяты из градиентов `AppColors` (`financesGradient`, `cashflowGradient`, …), чтобы
/// оформление счетов не выпадало из цветовой системы приложения. Хранить их здесь строками, а не
/// ссылками на `[Color]`, обязательно: бейдж строки списка красится ОДНИМ hex-акцентом
/// (`AccountIconBadgeView`), а из `Color` его обратно не достать.
///
/// Светлых пресетов нет намеренно: `AppColors.backgroundTop` — чёрный, приложение работает только
/// в тёмной теме, и белый текст hero-карточки обязан читаться на любом пресете.
enum AccountAppearancePreset: String, CaseIterable, Identifiable {
    case ocean
    case mint
    case royal
    case violet
    case ember
    case premium
    case gold
    case forest
    case sky
    case crimson
    case copper
    case graphite

    var id: String { rawValue }

    var titleKey: String { "account.appearance.preset.\(rawValue)" }

    /// Градиент карточки: слева-сверху → справа-снизу.
    var gradientHexes: [String] {
        switch self {
        case .ocean:    return ["#1D7BFF", "#29D3FF"]   // AppColors.financesGradient
        case .mint:     return ["#18C57A", "#00E0B8"]   // AppColors.coursesGradient
        case .royal:    return ["#2B8CFF", "#005BFF"]   // AppColors.cashbackGradient
        case .violet:   return ["#6A5CFF", "#D02BFF"]   // AppColors.cashflowGradient
        case .ember:    return ["#FF6B35", "#FF2D55"]   // AppColors.subscriptionsGradient
        case .premium:  return ["#0081E7", "#BD00E7"]   // AppColors.premiumGradient
        case .gold:     return ["#FFD60A", "#FF9F0A"]   // AppColors.investmentsGradient (yellow → orange)
        case .forest:   return ["#1EE688", "#0FB5A6"]   // AppColors.incomeActionGradient
        case .sky:      return ["#80B8FF", "#68A5FF"]   // AppColors.transferActionGradient
        case .crimson:  return ["#FF7070", "#FF4444"]   // AppColors.expenseActionGradient
        case .copper:   return ["#FF9F0A", "#8B5A2B"]   // AppColors.cardIndexGradient (orange → brown)
        case .graphite: return ["#636366", "#3A3A3C"]
        }
    }

    /// Акцент для бейджа строки списка — первый цвет градиента.
    var accentHex: String { gradientHexes[0] }

    var gradientColors: [Color] { gradientHexes.map { Color(hex: $0) } }

    /// Неизвестный `rawValue` (бэкап из будущей версии приложения) — не ошибка: счёт просто
    /// возвращается к вычисляемому дефолту, а не роняет экран.
    static func resolve(_ raw: String?) -> AccountAppearancePreset? {
        guard let raw else { return nil }
        return AccountAppearancePreset(rawValue: raw)
    }
}
