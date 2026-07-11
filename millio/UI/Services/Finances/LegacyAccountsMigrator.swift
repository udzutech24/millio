import Foundation
import SwiftData

/// Оркестратор одноразовой opening-balance-миграции ВСЕХ активных легаси-счетов
/// (`Card`/`Credit`/`Investment`) в счета нового ядра (`Account`) — Фаза 1 плана 6b «Путь B».
///
/// Поверх готовой Track C-инфраструктуры (`LegacyAccountConverter` + `LegacyConversionRegistry`,
/// покрыты тестами): перебирает активные легаси-счета, для каждого строит `LegacyAccountConversion.Plan`
/// (тот же маппинг знакового вклада в тотал, что `FinanceTotalsService.getAccountAmount`) и вызывает
/// `converter.convert`, который создаёт core-двойник и скрывает легаси (`archivedAt`) одним атомарным
/// актом. История легаси НЕ реплеится (MVP, согласовано владельцем при 1–2 юзерах).
///
/// **Инвариант тотала.** Двойник вносит ровно тот же знаковый вклад, что вносил легаси, а скрытая
/// (`archivedAt`) легаси из тотала выпадает → «Общий баланс» до == после даже в двоемирии (легаси-сумма
/// падает на вклад скрытого счёта, core-сумма растёт на равный вклад двойника). Поэтому переключение
/// чтения на single-world для инварианта НЕ требуется — оно отдельная забота Фазы 2.
///
/// **Идемпотентность.** Держится на ХРАНИМОМ `archivedAt` (SwiftData, переносится при restore) +
/// `registry.isConverted`, а НЕ на UserDefaults-флаге: перечисляются только активные (`archivedAt == nil`)
/// счета, уже мигрированные скрыты и повторно не берутся. Даже при утере реестра/флага (restore на
/// новом устройстве) повторный прогон — no-op: легаси-двойники уже созданы и легаси скрыто.
///
/// **Гэп меты вклада/рынка (§3 плана).** `Input` поддерживает только `cardMeta/loanMeta/manualAssetMeta`.
/// Легаси-вклад (`Investment` preset=deposit) и рыночная позиция (cat=stocks/crypto) мигрируют как
/// `.manualAsset` с opening-balance — теряют ставку/капитализацию/тикер (см. `LegacyAccountConversion`
/// docstring). При 1–2 юзерах и согласованной потере истории — допустимая деградация, TODO ниже.
// TODO(6b/фаза-post): расширить `LegacyAccountConverter.Input` на depositMeta/marketMeta, чтобы
// вклад/рыночная позиция мигрировали без потери ставки/капитализации/тикера (сейчас → manualAsset).
@MainActor
final class LegacyAccountsMigrator {

    struct Summary: Equatable {
        var migrated = 0
        var skippedAlreadyConverted = 0
        var failures = 0

        var total: Int { migrated + skippedAlreadyConverted + failures }
    }

    private let modelContext: ModelContext
    private let registry: LegacyConversionRegistry
    private let converter: LegacyAccountConverter
    private let defaults: UserDefaults
    private let fallbackCurrency: String
    private let nowProvider: () -> Date

    /// per-scope, НЕ глобальный ключ — по той же причине, что у `AccountSnapshotBackfillCoordinator`:
    /// холодный старт создаёт первый `DIContainer` на guest-сторе и только потом второй на user-сторе.
    /// Общий флаг сгорел бы на пустом guest-сторе. Флаг — лишь короткое замыкание; корректность
    /// идемпотентности НЕ зависит от него (см. docstring класса).
    private static let flagKeyPrefix = "migration.legacyAccountsPurge.v1."

    init(
        modelContext: ModelContext,
        registry: LegacyConversionRegistry = .shared,
        defaults: UserDefaults = .standard,
        fallbackCurrency: String = "RUB",
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.registry = registry
        self.converter = LegacyAccountConverter(modelContext: modelContext, registry: registry)
        self.defaults = defaults
        self.fallbackCurrency = fallbackCurrency
        self.nowProvider = nowProvider
    }

    /// Разовый per-scope прогон с UserDefaults-коротким замыканием. Флаг ставится только при отсутствии
    /// сбоев — иначе следующий старт дошагает недомигрированные счета (частичный прогон безопасен:
    /// каждый счёт скрывается атомарно, `registry` не задваивает).
    @discardableResult
    func migrateIfNeeded(scopeIdentifier: String) -> Summary {
        let flagKey = Self.flagKeyPrefix + scopeIdentifier
        guard !defaults.bool(forKey: flagKey) else { return Summary() }

        let summary = migrateAll()

        if summary.failures == 0 {
            defaults.set(true, forKey: flagKey)
        }
        return summary
    }

    /// Идемпотентно мигрирует все активные не-конвертированные легаси-счета (без флаг-гейта — для теста
    /// повторного прогона и как ядро `migrateIfNeeded`).
    @discardableResult
    func migrateAll() -> Summary {
        var summary = Summary()
        let groupNameByLegacyKey = buildGroupNameMap()

        for card in fetchActiveCards() {
            migrateOne(
                legacyKey: "card|\(card.cardUniqueID)",
                plan: LegacyAccountConversion.plan(for: card),
                groupNameByLegacyKey: groupNameByLegacyKey,
                hideLegacy: { card.archivedAt = self.nowProvider(); card.updatedAt = self.nowProvider() },
                into: &summary
            )
        }

        for credit in fetchActiveCredits() {
            migrateOne(
                legacyKey: "credit|\(credit.creditUniqueID)",
                plan: LegacyAccountConversion.plan(for: credit),
                groupNameByLegacyKey: groupNameByLegacyKey,
                hideLegacy: { credit.archivedAt = self.nowProvider(); credit.updatedAt = self.nowProvider() },
                into: &summary
            )
        }

        for investment in fetchActiveInvestments() {
            migrateOne(
                legacyKey: "investment|\(investment.investmentUniqueID)",
                plan: LegacyAccountConversion.plan(for: investment, currency: resolveInvestmentCurrency(investment)),
                groupNameByLegacyKey: groupNameByLegacyKey,
                hideLegacy: { investment.archivedAt = self.nowProvider(); investment.updatedAt = self.nowProvider() },
                into: &summary
            )
        }

        remapCashflowHistory()
        remapCashbackCardIDs()

        return summary
    }

    // MARK: - Ремап Cashback.cardIDs (Фаза 5b плана 6b «Путь B»)

    /// Однократно переписывает `Cashback.cardIDs` с легаси `Card.uniqueID` на `Account.id` core-двойника
    /// (та же денежная проверка kind, что `remapCashflowHistory`). Без этого привязка кэшбэка к карте
    /// осиротевает после сноса легаси-моделей (Фаза 5c) — `CashbackViewModel.cleanInvalidCardIDs`
    /// молча вычистила бы эти ID как «несуществующие». Идемпотентно по построению (см. `remapCashflowHistory`).
    private func remapCashbackCardIDs() {
        let cashbacks = (try? modelContext.fetch(FetchDescriptor<Cashback>())) ?? []
        guard !cashbacks.isEmpty else { return }

        var didChange = false
        for cashback in cashbacks {
            let remapped = cashback.cardIDs.map { remappedCashLikeAccountID(legacyUniqueID: $0) ?? $0 }
            if remapped != cashback.cardIDs {
                cashback.cardIDs = remapped
                didChange = true
            }
        }

        guard didChange else { return }
        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "AccountsCore",
                          "Legacy migration: ремап Cashback.cardIDs — \(error.localizedDescription)")
        }
    }

    // MARK: - Ремап истории Cashflow (Фаза 5a плана 6b «Путь B»)

    /// Однократно переписывает `cardID`/`toCardID`/`investmentID` СУЩЕСТВУЮЩИХ `CashflowTransaction`
    /// (созданных до миграции их счёта) с легаси-`uniqueID` на `Account.id` core-двойника.
    /// `AccountsCoreCashflowBridge.resolveNewCoreAccount` сверяет `cardID` буквально с `Account.id`
    /// (разные пространства UUID, см. докстринг файла) — без ремапа дотранзакционная история теряет
    /// атрибуцию счёта после сноса легаси-моделей (Фаза 5c). Вызывается на КАЖДЫЙ прогон `migrateAll`
    /// (не только когда что-то мигрировано в ЭТОМ вызове) — ловит счета, сконвертированные раньше
    /// (Ф1/Ф3), для которых ремап ещё не выполнялся. Идемпотентно по построению: после первого
    /// прогона `cardID` уже равен UUID двойника и не совпадает ни с одним легаси `uniqueID`.
    private func remapCashflowHistory() {
        let transactions = (try? modelContext.fetch(FetchDescriptor<CashflowTransaction>())) ?? []
        guard !transactions.isEmpty else { return }

        var didChange = false
        for transaction in transactions {
            if let remapped = remappedCashLikeAccountID(legacyUniqueID: transaction.cardID) {
                transaction.cardID = remapped
                didChange = true
            }
            if let remapped = remappedCashLikeAccountID(legacyUniqueID: transaction.toCardID) {
                transaction.toCardID = remapped
                didChange = true
            }
            // Кэш-подобная Investment (isCashflowAccount) хранила свой ID в отдельной колонке
            // `investmentID` (легаси-дизайн — `Card` и `Investment` были разными таблицами).
            // `cardID == nil` — единственный случай легаси-записи такой транзакции (income/expense
            // на кэш-подобный счёт, а не перевод/трейд-нога, которые уже используют cardID).
            // Рыночные/вклад/долг `investmentID` (core-двойник `.manualAsset`) НЕ трогаем — их
            // движок не участвует в Cashflow-леджере (осознанная деградация §3 плана).
            if transaction.cardID == nil, let remapped = remappedCashLikeAccountID(legacyUniqueID: transaction.investmentID) {
                transaction.cardID = remapped
                transaction.investmentID = nil
                didChange = true
            }
        }

        guard didChange else { return }
        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "AccountsCore",
                          "Legacy migration: ремап истории Cashflow — \(error.localizedDescription)")
        }
    }

    /// UUID-строка core-двойника, ЕСЛИ `legacyUniqueID` сконвертирован И двойник — денежный
    /// (`cash`/`debitCard`/`bankAccount`, тот же набор, что `CashflowViewModel+AccountsCore.cashLikeKinds`).
    private func remappedCashLikeAccountID(legacyUniqueID: String?) -> String? {
        guard let legacyUniqueID, let coreID = registry.coreAccountID(forLegacyUniqueID: legacyUniqueID) else {
            return nil
        }
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == coreID })
        guard let account = try? modelContext.fetch(descriptor).first else { return nil }
        let cashLikeKinds: Set<String> = [
            AccountKind.cash.rawValue, AccountKind.debitCard.rawValue, AccountKind.bankAccount.rawValue
        ]
        guard cashLikeKinds.contains(account.kindRaw) else { return nil }
        return coreID.uuidString
    }

    // MARK: - Один счёт

    private func migrateOne(
        legacyKey: String,
        plan: LegacyAccountConversion.Plan,
        groupNameByLegacyKey: [String: String],
        hideLegacy: @escaping () -> Void,
        into summary: inout Summary
    ) {
        guard !registry.isConverted(legacyUniqueID: plan.legacyUniqueID) else {
            summary.skippedAlreadyConverted += 1
            return
        }

        let coreGroup = resolveCoreGroup(name: groupNameByLegacyKey[legacyKey])
        let input = LegacyAccountConverter.Input(
            legacyUniqueID: plan.legacyUniqueID,
            name: plan.name,
            currency: plan.currency,
            kind: plan.kind,
            openingBalance: plan.openingBalance,
            group: coreGroup,
            cardMeta: plan.cardMeta,
            loanMeta: plan.loanMeta,
            manualAssetMeta: plan.manualAssetMeta
        )

        do {
            try converter.convert(input, date: nowProvider()) {
                hideLegacy()
                try self.modelContext.save()
            }
            summary.migrated += 1
        } catch {
            summary.failures += 1
            AppLogger.log(.error, category: "AccountsCore",
                          "Legacy migration: счёт \(plan.legacyUniqueID) — \(error.localizedDescription)")
        }
    }

    // MARK: - Выборки (широкий fetch + Swift-фильтр)

    // Широкий fetch без #Predicate — датасеты крошечные (1–2 юзера), а compound-#Predicate с обходом
    // связей у SwiftData ненадёжен (ловушка §7.2 плана cashflow-add-transaction-redesign). Фильтр в Swift.
    private func fetchActiveCards() -> [Card] {
        ((try? modelContext.fetch(FetchDescriptor<Card>())) ?? []).filter { $0.archivedAt == nil }
    }

    private func fetchActiveCredits() -> [Credit] {
        ((try? modelContext.fetch(FetchDescriptor<Credit>())) ?? []).filter { $0.archivedAt == nil }
    }

    private func fetchActiveInvestments() -> [Investment] {
        ((try? modelContext.fetch(FetchDescriptor<Investment>())) ?? []).filter { $0.archivedAt == nil }
    }

    // MARK: - Группы

    /// Карта «легаси-ключ (accountType|accountID) → имя FinanceGroup» из junction-таблицы
    /// `FinanceAccount` — тот же источник группировки, что использует легаси-тотал/список.
    private func buildGroupNameMap() -> [String: String] {
        let links = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []
        var map: [String: String] = [:]
        for link in links {
            guard let name = link.group?.name, !name.isEmpty else { continue }
            map["\(link.accountTypeRaw)|\(link.accountID)"] = name
        }
        return map
    }

    /// Core-группа двойника: находим/создаём `AccountGroup` по имени легаси-группы (мост по имени).
    /// Ф5c.7.3: сведён на `AccountsCoreAdditionBridge` — единый Ungrouped-гард по `allKnownUngroupedNames`
    /// (раньше здесь был локаль-зависимый `ungroupedName`, пропускавший кросс-локальный Ungrouped).
    private func resolveCoreGroup(name: String?) -> AccountGroup? {
        AccountsCoreAdditionBridge.resolveAccountGroup(matchingName: name, in: modelContext)
    }

    // MARK: - Валюта вклада

    /// Зеркалит `FinanceTotalsService.resolvedInvestmentCurrency` (дублируется, т.к. мигратор не должен
    /// тянуть тяжёлый `FinanceTotalsService` со всеми провайдерами ради одной чистой резолюции валюты).
    private func resolveInvestmentCurrency(_ investment: Investment) -> String {
        let normalized = investment.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !normalized.isEmpty { return normalized }

        if let marketCurrency = investment.marketCurrency?
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !marketCurrency.isEmpty {
            return marketCurrency
        }

        if let marketSymbol = investment.marketSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !marketSymbol.isEmpty {
            for separator in ["/", "-"] where marketSymbol.contains(separator) {
                if let quote = marketSymbol.split(separator: Character(separator)).map(String.init).last,
                   !quote.isEmpty {
                    return quote
                }
            }
        }

        return fallbackCurrency
    }
}
