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
    typealias SaveOperation = (ModelContext) throws -> Void

    enum ConversionError: Error, Equatable {
        case dirtyContext
    }

    /// Параметры создания core-двойника. `openingBalance` уже приведён к знаку движка вызывающим
    /// кодом (для `.loan` — магнитуда, движок C сам инвертирует), см. `LegacyAccountConversion.plan`.
    struct Input {
        let legacyUniqueID: String
        let name: String
        let currency: String
        let productType: AccountProductType
        let openingBalance: Decimal
        let group: AccountGroup?
        let metadata: AccountProductMetadata
        let initialMarketPurchase: InitialMarketPurchase?
        let includeInTotal: Bool
    }

    private let modelContext: ModelContext
    private let registry: LegacyConversionRegistry
    private let saveOperation: SaveOperation

    init(
        modelContext: ModelContext,
        registry: LegacyConversionRegistry,
        saveOperation: @escaping SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.registry = registry
        self.saveOperation = saveOperation
    }

    func isConverted(legacyUniqueID: String) -> Bool {
        registry.isConverted(legacyUniqueID: legacyUniqueID)
    }

    /// Создаёт core-двойник и скрывает легаси (замыкание) атомарно. `hideLegacy` устанавливает
    /// `archivedAt` у легаси-модели и сохраняет контекст; при его ошибке двойник и запись реестра
    /// откатываются (компенсация), ошибка пробрасывается.
    @discardableResult
    func convert(_ input: Input, date: Date = Date(), hideLegacy: () throws -> Void) throws -> Account {
        guard !modelContext.hasChanges else { throw ConversionError.dirtyContext }
        do {
            let graph = try AccountProductGraphBuilder.build(CreateProductCommand(
                productType: input.productType,
                name: input.name,
                currency: input.currency,
                openingBalance: input.openingBalance,
                includeInTotal: input.includeInTotal,
                groupID: input.group?.id,
                metadata: input.metadata,
                date: date,
                initialMarketPurchase: input.initialMarketPurchase
            ), in: modelContext)
            try hideLegacy()
            try saveOperation(modelContext)
            registry.record(legacyUniqueID: input.legacyUniqueID, coreAccountID: graph.account.id)
            return graph.account
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Откат конвертации: удаляет core-двойник (по записи реестра) и запись реестра, затем
    /// восстанавливает легаси (замыкание снимает `archivedAt`). Двойник удаляется ПЕРВЫМ, чтобы при
    /// сбое восстановления не осталось обоих активными (double-count) — легаси в этом случае
    /// остаётся archivedAt-скрытым и восстановимо повторно через архив (под-count безопаснее).
    func unconvert(legacyUniqueID: String, restoreLegacy: () throws -> Void) throws {
        guard !modelContext.hasChanges else { throw ConversionError.dirtyContext }
        do {
            if let coreID = registry.coreAccountID(forLegacyUniqueID: legacyUniqueID) {
                let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == coreID })
                if let twin = try modelContext.fetch(descriptor).first {
                    modelContext.delete(twin)
                }
            }
            try restoreLegacy()
            try saveOperation(modelContext)
            registry.remove(legacyUniqueID: legacyUniqueID)
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
