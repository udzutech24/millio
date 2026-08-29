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
    /// `rawValue` дизайна из кодового каталога (Ф2). Хранится строкой, а не типом, чтобы значение
    /// из бэкапа будущей версии приложения не ломало декодирование — резолв делает UI-слой.
    let presetRaw: String?
    let isFavorite: Bool

    init(
        iconName: String? = nil,
        tintHex: String? = nil,
        presetRaw: String? = nil,
        isFavorite: Bool = false
    ) {
        self.iconName = iconName
        self.tintHex = tintHex
        self.presetRaw = presetRaw
        self.isFavorite = isFavorite
    }

    init(_ appearance: AccountAppearance) {
        self.init(
            iconName: appearance.iconName,
            tintHex: appearance.tintHex,
            presetRaw: appearance.presetRaw,
            isFavorite: appearance.isFavorite
        )
    }
}
