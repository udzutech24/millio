import Foundation
import SwiftData

/// Конвертация легаси-счёта (Card/Credit/Investment) в счёт нового ядра event-sourcing (Track C, MVP).
///
/// MVP: только opening-balance (текущий баланс легаси), БЕЗ реплея истории — история остаётся
/// видимой в легаси-архиве до Фазы 6b. Сервис легаси-агностичен: НЕ импортирует легаси-модели
/// (Core не зависит от UI-слоя), сторону легаси (`archivedAt`/restore) вызывающий код передаёт
/// замыканием. Атомарность (риск №8 плана): создание core-двойника и скрытие легаси — один
/// синхронный акт; при сбое скрытия только что созданный двойник откатывается (компенсация),
/// иначе в тотале появился бы двойной счёт.
@MainActor
final class LegacyAccountConverter {

    /// Параметры создания core-двойника. `openingBalance` уже приведён к знаку движка вызывающим
    /// кодом (для `.loan` — магнитуда, движок C сам инвертирует), см. `LegacyAccountConversion.plan`.
    struct Input {
        let legacyUniqueID: String
        let name: String
        let currency: String
        let kind: AccountKind
        let openingBalance: Decimal
        let group: AccountGroup?
        let cardMeta: CardMeta?
        let loanMeta: LoanMeta?
        let manualAssetMeta: ManualAssetMeta?
    }

    private let modelContext: ModelContext
    private let coreService: AccountsCoreService
    private let registry: LegacyConversionRegistry

    init(modelContext: ModelContext, registry: LegacyConversionRegistry) {
        self.modelContext = modelContext
        self.coreService = AccountsCoreService(modelContext: modelContext)
        self.registry = registry
    }

    func isConverted(legacyUniqueID: String) -> Bool {
        registry.isConverted(legacyUniqueID: legacyUniqueID)
    }

    /// Создаёт core-двойник и скрывает легаси (замыкание) атомарно. `hideLegacy` устанавливает
    /// `archivedAt` у легаси-модели и сохраняет контекст; при его ошибке двойник и запись реестра
    /// откатываются (компенсация), ошибка пробрасывается.
    @discardableResult
    func convert(_ input: Input, date: Date = Date(), hideLegacy: () throws -> Void) throws -> Account {
        let account = try coreService.createAccount(
            name: input.name,
            kind: input.kind,
            currency: input.currency,
            openingBalance: input.openingBalance,
            group: input.group,
            cardMeta: input.cardMeta,
            loanMeta: input.loanMeta,
            manualAssetMeta: input.manualAssetMeta,
            date: date
        )
        registry.record(legacyUniqueID: input.legacyUniqueID, coreAccountID: account.id)

        do {
            try hideLegacy()
        } catch {
            // Компенсация: убрать только что созданный двойник и запись реестра — иначе в тотале
            // останутся ОБА (легаси не скрыто + core-двойник), это и есть double-count из риска №8.
            registry.remove(legacyUniqueID: input.legacyUniqueID)
            try? coreService.physicallyDelete(account)
            throw error
        }
        return account
    }

    /// Откат конвертации: удаляет core-двойник (по записи реестра) и запись реестра, затем
    /// восстанавливает легаси (замыкание снимает `archivedAt`). Двойник удаляется ПЕРВЫМ, чтобы при
    /// сбое восстановления не осталось обоих активными (double-count) — легаси в этом случае
    /// остаётся archivedAt-скрытым и восстановимо повторно через архив (под-count безопаснее).
    func unconvert(legacyUniqueID: String, restoreLegacy: () throws -> Void) throws {
        if let coreID = registry.coreAccountID(forLegacyUniqueID: legacyUniqueID) {
            let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == coreID })
            if let twin = try? modelContext.fetch(descriptor).first {
                try coreService.physicallyDelete(twin)
            }
        }
        registry.remove(legacyUniqueID: legacyUniqueID)
        try restoreLegacy()
    }
}
