import Foundation
import SwiftData

/// Оркестратор одноразового переноса полей легаси-групп (`FinanceGroup`) на канонические
/// `AccountGroup` нового ядра — Фаза 1.5 плана 6b «Путь B» (слияние моделей групп).
///
/// Для каждой активной `FinanceGroup` резолвит/создаёт одноимённую `AccountGroup` (переиспользует
/// `AccountsCoreAdditionBridge.resolveAccountGroup` — тот же мост по имени, что Фаза 1) и ОДИН РАЗ
/// переносит `isFavorite`/`usesManualAccountOrdering`/`priorityRaw`/`colorHex`/`displayCurrency`/`order`.
///
/// **Идемпотентность.** Держится на ХРАНИМОМ `AccountGroup.legacyFieldsMigratedAt` (SwiftData,
/// переносится при restore) — по тому же принципу, что `archivedAt` у легаси-счетов в Фазе 1:
/// не UserDefaults-флаг, а постоянный признак «перенос для этой группы уже сделан». Даже при утере
/// реестра/флага (restore на новом устройстве) повторный прогон — no-op: маркер переехал вместе с
/// группой. Повторный прогон НЕ затирает поля, отредактированные пользователем после миграции.
///
/// Модель `FinanceGroup` в этой фазе НЕ удаляется (снос — Фаза 5): только читатели групп
/// переключаются на `AccountGroup`, а данные полей переезжают сюда.
///
/// **Известное ограничение (не гардится намеренно, ревью 2026-07-09).** Мостик `resolveAccountGroup`
/// резолвит `AccountGroup` ПО ИМЕНИ — две активные `FinanceGroup` с одинаковым именем схлопнутся
/// в одну `AccountGroup` (первая мигрирует поля, вторая логируется как дубль и пропускается, её
/// core-счета попадут в ту же группу). UI создания/редактирования группы (`FinanceGroupService`)
/// не проверяет уникальность имени — теоретически возможно, но не наблюдалось в проде (1–2 юзера).
/// Не гардим полноценно (доп. UI-валидация — отдельная задача вне скоупа слияния моделей), но НЕ
/// молчим: `Summary.skippedDuplicateName` + warning-лог с именем группы.
@MainActor
final class GroupsMigrator {

    struct Summary: Equatable {
        var migrated = 0
        var skippedAlreadyMigrated = 0
        var skippedUngrouped = 0
        /// Счётчик дублей имён легаси-групп (см. докстринг класса, «Известное ограничение»).
        var skippedDuplicateName = 0

        var total: Int { migrated + skippedAlreadyMigrated + skippedUngrouped + skippedDuplicateName }
    }

    private let modelContext: ModelContext
    private let defaults: UserDefaults
    private let nowProvider: () -> Date

    /// per-scope UserDefaults-ключ (как у `LegacyAccountsMigrator`) — лишь короткое замыкание;
    /// корректность идемпотентности от него НЕ зависит (см. docstring класса).
    private static let flagKeyPrefix = "migration.groupsMerge.v1."

    init(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.defaults = defaults
        self.nowProvider = nowProvider
    }

    /// Разовый per-scope прогон с UserDefaults-коротким замыканием.
    @discardableResult
    func migrateIfNeeded(scopeIdentifier: String) -> Summary {
        let flagKey = Self.flagKeyPrefix + scopeIdentifier
        guard !defaults.bool(forKey: flagKey) else { return Summary() }

        let summary = migrateAll()
        defaults.set(true, forKey: flagKey)
        return summary
    }

    /// Идемпотентно переносит поля всех легаси-групп на одноимённые `AccountGroup` (без флаг-гейта —
    /// ядро `migrateIfNeeded` и точка входа для теста повторного прогона).
    @discardableResult
    func migrateAll() -> Summary {
        var summary = Summary()
        let financeGroups = (try? modelContext.fetch(FetchDescriptor<FinanceGroup>())) ?? []
        // Дефект 2 (ревью 2026-07-09): резолвер мостика по имени коллапсирует ДВЕ разные `FinanceGroup`
        // с одинаковым именем в ОДНУ `AccountGroup`. UI создания группы не гарантирует уникальность
        // имени (нет проверки в `FinanceGroupService.updateGroup`) — теоретически возможно, хоть и не
        // наблюдалось в проде (1–2 юзера). Здесь НЕ молчим: первая группа с именем мигрирует поля,
        // повторные с тем же именем детектируются явно (см. ниже) и логируются как дубль, а не тихо
        // классифицируются "уже мигрировано".
        var seenNames = Set<String>()

        for financeGroup in financeGroups {
            // Ungrouped/пустое имя не имеет собственной `AccountGroup` (core-семантика: group == nil).
            guard financeGroup.name != FinanceSystemGroups.ungroupedName, !financeGroup.name.isEmpty else {
                summary.skippedUngrouped += 1
                continue
            }

            guard let coreGroup = AccountsCoreAdditionBridge.resolveAccountGroup(
                matching: financeGroup, in: modelContext
            ) else {
                summary.skippedUngrouped += 1
                continue
            }

            if !seenNames.insert(financeGroup.name).inserted {
                summary.skippedDuplicateName += 1
                AppLogger.log(.warning, category: "AccountsCore",
                              "GroupsMigrator: дубль имени легаси-группы \"\(financeGroup.name)\" — " +
                              "поля этой группы НЕ перенесены (уже перенесены с первой одноимённой), " +
                              "её core-счета схлопнутся в ту же AccountGroup")
                continue
            }

            guard coreGroup.legacyFieldsMigratedAt == nil else {
                summary.skippedAlreadyMigrated += 1
                continue
            }

            coreGroup.isFavorite = financeGroup.isFavorite
            coreGroup.usesManualAccountOrdering = financeGroup.usesManualAccountOrdering
            coreGroup.priorityRaw = financeGroup.priorityRaw
            coreGroup.colorHex = financeGroup.colorHex
            coreGroup.displayCurrency = financeGroup.displayCurrency
            coreGroup.order = financeGroup.order
            coreGroup.legacyFieldsMigratedAt = nowProvider()
            summary.migrated += 1
        }

        if summary.migrated > 0 {
            do {
                try modelContext.save()
            } catch {
                AppLogger.log(.error, category: "AccountsCore",
                              "Groups migration save failed: \(error.localizedDescription)")
            }
        }

        return summary
    }
}
