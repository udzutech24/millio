import Foundation
import SwiftData

/// Пользовательские атрибуты представления счёта: оформление (пресет/цвет/иконка) и «избранное».
///
/// Отдельная side-таблица, а не поля в `Account`: `Account` входит в checksum замороженных версий
/// схемы V6–V10 (composite `*Meta`), и любая правка его декларации сдвигает checksum задним числом →
/// `NSCocoaErrorDomain 134504` на сторах пользователей (памятка `millio-schema-frozen-types-trap`).
///
/// `accountID` — ОБЫЧНОЕ поле без `@Relationship`, потому что ключ обслуживает два мира счетов
/// сразу: core `Account.id` и легаси `Card.cardUniqueID` (UUID-строка). Реляция была бы возможна
/// только с одним из них.
/// ⚠️ Легаси-карта без заполненного `uniqueID` отдаёт composite-fallback (`Card.swift:272`), который
/// не парсится в UUID — такая карта оформления не получает (дефолтный вид), это осознанный предел.
@Model
final class AccountAppearance: Persistable {
    var id: UUID = UUID()
    var accountID: UUID = UUID()
    var presetRaw: String?
    var tintHex: String?
    var iconName: String?
    var isFavorite: Bool = false
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        accountID: UUID,
        presetRaw: String? = nil,
        tintHex: String? = nil,
        iconName: String? = nil,
        isFavorite: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountID = accountID
        self.presetRaw = presetRaw
        self.tintHex = tintHex
        self.iconName = iconName
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
    }

    /// Пустая запись бессмысленна: она занимает строку, но не меняет ни вид, ни поведение счёта.
    /// Стор использует это, чтобы не плодить мусор при сбросе оформления.
    var isDefault: Bool {
        presetRaw == nil && tintHex == nil && iconName == nil && !isFavorite
    }

    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "AccountAppearance",
            "id": id.uuidString,
            "accountID": accountID.uuidString,
            "isFavorite": isFavorite,
            "updatedAt": updatedAt.timeIntervalSince1970,
        ]
        if let presetRaw { dict["presetRaw"] = presetRaw }
        if let tintHex { dict["tintHex"] = tintHex }
        if let iconName { dict["iconName"] = iconName }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {}
}
