import Foundation

/// Неизменяемый срез `AccountAppearance` для UI-слоя.
///
/// Список счетов НЕ держит сами `@Model`-объекты: `DataIntegrityCleaner` удаляет строки-сироты на
/// старте, и удалённый `AccountAppearance` в кэше ViewModel обращением к его полю уронил бы рендер.
/// Плюс `Equatable`-значение даёт SwiftUI дешёвое сравнение строк списка.
struct AccountAppearanceSnapshot: Equatable {
    /// SF Symbol или монограмма вида `monogram:СБ` (см. `AccountIconSet`).
    let iconName: String?
    /// Только hex — сюда никогда не попадает «имя цвета» легаси-поля `Card.cardColor`.
    let tintHex: String?
    let isFavorite: Bool

    init(iconName: String? = nil, tintHex: String? = nil, isFavorite: Bool = false) {
        self.iconName = iconName
        self.tintHex = tintHex
        self.isFavorite = isFavorite
    }

    init(_ appearance: AccountAppearance) {
        self.init(
            iconName: appearance.iconName,
            tintHex: appearance.tintHex,
            isFavorite: appearance.isFavorite
        )
    }
}
