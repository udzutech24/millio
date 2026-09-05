import Foundation
import SwiftData

/// Ручной ремонт счёта, испорченного старой версией `LegacyAccountConversion` (до 5ae6ff8,
/// 09.08.2026): кредитка была записана как `.debitCard` без `creditLimit`, и раз `productTypeRaw`
/// уже заполнен — `AccountProductIdentityMigrator.classify` такие счета не чинит (внутренних
/// противоречий нет, чинить «не считает нужным»). Автоматической эвристики здесь НЕТ и не будет —
/// решение владельца после стресс-теста: только явное действие пользователя «Это кредитная карта».
///
/// НЕ используем `AccountProductTransitionCoordinator` — тот полиси-классификатор специально
/// блокирует любой переход в/из `.creditCard` (`AccountProductTransitionPolicy.creditReplayEngine`):
/// кредитка живёт на отдельном реплей-движке (`CreditCardFinancialContract`), который generic
/// event-replay транзишн не понимает. Здесь — узкий, отдельный путь письма именно под этот случай.
enum DebitToCreditCardRepair {
    enum RepairError: Error, Equatable {
        case invalidLimit
        case notDebitCard
        case alreadyCreditCard
    }

    /// Число для листа-предпросмотра — ничего не пишет. Долг = ТЕКУЩИЙ сырой баланс счёта: пока
    /// `creditLimit` не задан, `AccountTotalsContribution.signedValue` отдаёт его как есть (баг),
    /// поэтому именно он и есть непосредственно наблюдаемый долг «в минус наоборот».
    struct Preview: Equatable {
        let creditLimit: Decimal
        let debt: Decimal
        /// Доступный лимит ПОСЛЕ ремонта = `creditLimit − debt` (CreditCardFinancialContract).
        let availableAfter: Decimal
        /// Вклад в «Итого» ДО ремонта (сейчас, ошибочно положительный).
        let contributionBefore: Decimal
        /// Вклад в «Итого» ПОСЛЕ ремонта (должен быть равен `−debt`).
        let contributionAfter: Decimal
    }

    static func preview(balanceToday: Decimal, creditLimit: Decimal) -> Preview? {
        guard creditLimit > 0 else { return nil }
        let debt = balanceToday
        let availableAfter = CreditCardFinancialContract.rawAvailableBalance(debt: debt, creditLimit: creditLimit)
        return Preview(
            creditLimit: creditLimit,
            debt: debt,
            availableAfter: availableAfter,
            contributionBefore: balanceToday,
            contributionAfter: CreditCardFinancialContract.netPosition(rawAvailableBalance: availableAfter, creditLimit: creditLimit)
        )
    }

    /// Пишет ремонт: продукт → `.creditCard` (kind остаётся `.debitCard` — кредитка не отдельный
    /// `AccountKind`, см. `ProductDefinitionCatalog.legacyCompatibleKinds`), лимит в `CardMeta`,
    /// и ОДНО компенсирующее `.adjustment`-событие поверх существующей ленты — через
    /// `AccountsCoreService.adjustBalance` (append-only, считает дельту САМ от факта на дату,
    /// ничего не удаляет и не переписывает). Дельта считается ПОСЛЕ применения лимита, от уже
    /// зафиксированного `debt`, а не наивным «−debt второй раз» (см. докстринг `Preview`) — иначе
    /// был бы перелёт на удвоенную сумму долга, как явно предостерегал стресс-тест.
    @discardableResult
    @MainActor
    static func apply(
        account: Account,
        creditLimit: Decimal,
        balanceToday: Decimal,
        service: AccountsCoreService,
        context: ModelContext,
        date: Date = Date()
    ) throws -> AccountEvent {
        guard creditLimit > 0 else { throw RepairError.invalidLimit }
        guard account.productType != .creditCard else { throw RepairError.alreadyCreditCard }
        guard account.productType == .debitCard, account.kind == .debitCard else { throw RepairError.notDebitCard }

        var meta = account.cardMeta ?? CardMeta()
        meta.creditLimit = creditLimit
        try ProductDefinitionCatalog.validateStoredIdentity(
            .creditCard, kindRaw: account.kindRaw, metadata: .init(card: meta), migrationReason: nil
        )

        let debt = balanceToday
        let targetRawBalance = CreditCardFinancialContract.rawAvailableBalance(debt: debt, creditLimit: creditLimit)

        // Идентичность и мета — до записи компенсирующего события: `adjustBalance` читает
        // `account.productType`/`.kind` для проверки допустимости `.adjustment` (уже разрешён и
        // для .debitCard, и для .creditCard — смена типа здесь ничего не блокирует), а баланс
        // сейчас пересчитан для УЖЕ откорректированной идентичности.
        account.productType = .creditCard
        account.cardMeta = meta
        HistoricalValuationRevisionTracker.bump([.accountSet, .financial], on: account)

        return try service.adjustBalance(account: account, to: targetRawBalance, on: date)
    }
}
