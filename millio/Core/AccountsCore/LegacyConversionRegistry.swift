import Foundation

/// Реестр соответствий «легаси-счёт → счёт нового ядра» для отката конвертации (Track C).
///
/// Хранится в UserDefaults, а НЕ полем в @Model. Причина: добавление поля в SwiftData-модель =
/// изменение схемы (риск №11 плана — V4 in-place уже хрупкая), которого сознательно избегаем.
/// Реестр device-local (бэкапом не переносится): при его утере откат конвертации недоступен, но
/// легаси остаётся `archivedAt`-скрытым — double-count в тотале НЕ возникает (инвариант держится
/// хранимым `archivedAt`, а не реестром). Ключ — легаси `uniqueID` (== `FinanceAccount.accountID`).
@MainActor
final class LegacyConversionRegistry {
    static let shared = LegacyConversionRegistry()

    private let defaults: UserDefaults
    private let storageKey = "legacy_account_conversions_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func load() -> [String: String] {
        defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    private func store(_ map: [String: String]) {
        defaults.set(map, forKey: storageKey)
    }

    /// UUID созданного core-двойника для легаси-счёта, либо nil, если конвертации не было.
    func coreAccountID(forLegacyUniqueID legacyUniqueID: String) -> UUID? {
        guard let raw = load()[legacyUniqueID] else { return nil }
        return UUID(uuidString: raw)
    }

    func isConverted(legacyUniqueID: String) -> Bool {
        coreAccountID(forLegacyUniqueID: legacyUniqueID) != nil
    }

    /// Легаси `uniqueID`, сконвертированный в указанный core-счёт (реверс `coreAccountID`).
    /// Нужен, чтобы восстановить домиграционный баланс core-строки в Динамике: до 6b core-двойника
    /// не существовало, а легаси-предшественник (archived) ещё жив в сторе до Ф5c.
    func legacyUniqueID(forCoreAccountID coreAccountID: UUID) -> String? {
        let target = coreAccountID.uuidString
        return load().first(where: { $0.value == target })?.key
    }

    func record(legacyUniqueID: String, coreAccountID: UUID) {
        var map = load()
        map[legacyUniqueID] = coreAccountID.uuidString
        store(map)
    }

    func remove(legacyUniqueID: String) {
        var map = load()
        map.removeValue(forKey: legacyUniqueID)
        store(map)
    }

    /// Массовый сброс записей конверсии для указанных легаси-ID. Нужен self-heal-миграции
    /// (`LegacyAccountsMigrator`): после замены стора без ядра (restore до-AccountsCore-бэкапа или
    /// recovery-ребилд) реестр помечает эти легаси-ID «сконвертированными», хотя core-двойника в
    /// ТЕКУЩЕМ сторе нет — без сброса гейт мигратора (`guard !isConverted`) пропустит их и ядро не
    /// пересоберётся. Сброс точечный (только переданные ID текущего стора) — записи других scope,
    /// живущие в том же словаре, не затрагиваются.
    func removeAll(legacyUniqueIDs: [String]) {
        guard !legacyUniqueIDs.isEmpty else { return }
        var map = load()
        for id in legacyUniqueIDs {
            map.removeValue(forKey: id)
        }
        store(map)
    }
}
