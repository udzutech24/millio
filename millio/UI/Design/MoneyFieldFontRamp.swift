import SwiftUI

/// Ступени шрифта для ПОЛЯ ВВОДА денежной суммы: чем длиннее число, тем мельче токен.
///
/// `minimumScaleFactor` здесь не работает как механизм: `TextField` не сжимает содержимое, а
/// прокручивает его, и старшие разряды уезжают за границу поля — пользователь перестаёт видеть,
/// что вводит (репорт с устройства: сумма от ~40 млн в карточке условий вклада).
///
/// Ширину предсказываем по числу НЕПРОБЕЛЬНЫХ символов (цифры + десятичный разделитель):
/// разделитель разрядов у SF заметно уже цифры, а вот точка по ширине от цифры почти не отличается,
/// поэтому «9 999.99» шире, чем «999 999», при одинаковом числе цифр.
enum MoneyFieldFontRamp {
    case display
    case title
    case title3
    case headline

    /// Пороги подобраны так, чтобы строка до 11 символов помещалась в ~127pt — ширину поля суммы
    /// в карточке условий вклада на экране 390pt (замеры — в `MoneyFieldFontRampTests`).
    static func step(for displayText: String) -> Self {
        switch displayText.filter({ !$0.isWhitespace }).count {
        case ...6: .display
        case 7: .title
        case 8...9: .title3
        default: .headline
        }
    }

    static func font(for displayText: String) -> Font {
        step(for: displayText).font
    }

    var font: Font {
        switch self {
        case .display: .millioDisplay
        case .title: .millioTitle
        case .title3: .millioTitle3
        case .headline: .millioHeadline
        }
    }

    /// Метрики токена наружу — только для измерения ширины в тестах: `Font` размер не отдаёт.
    /// Зеркалят `AppTypography`; меняешь там — поправь здесь, иначе тест ширины начнёт врать.
    var pointSize: CGFloat {
        switch self {
        case .display: 30
        case .title: 24
        case .title3: 20
        case .headline: 16
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .title: .bold
        case .title3, .headline: .semibold
        }
    }
}
