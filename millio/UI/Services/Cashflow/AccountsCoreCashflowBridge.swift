//
//  AccountsCoreCashflowBridge.swift
//  millio
//
//  Мост Cashflow → новое ядро счетов (event-sourcing, Фаза 1b, план §2.5/§3).
//  Принцип: каждая транзакция пишет РОВНО в один мир по типу целевого счёта — легаси
//  Card/Investment продолжают жить старым путём (CashflowPersistenceService, без изменений),
//  новые Account нового ядра получают ТОЛЬКО AccountEvent, никогда card.balance-мутацию.
//  CashflowTransaction остаётся сущностью ленты/бюджетов — события ядра дополняют её.
//

import Foundation
import SwiftData

/// Единственная точка, где операции Cashflow транслируются в `AccountEvent` нового ядра.
@MainActor
final class AccountsCoreCashflowBridge {

    private let modelContext: ModelContext
    private let accountsCoreService: AccountsCoreService
    private let historicalRateStore: HistoricalRateStore

    init(
        modelContext: ModelContext,
        accountsCoreService: AccountsCoreService,
        historicalRateStore: HistoricalRateStore
    ) {
        self.modelContext = modelContext
        self.accountsCoreService = accountsCoreService
        self.historicalRateStore = historicalRateStore
    }

    // MARK: - Резолвер целевого мира

    /// cardID/toCardID транзакции для нового мира — это `Account.id.uuidString` (см. Account.swift,
    /// AccountsCoreAdditionBridge). Легаси-карты используют СВОЙ отдельный `Card.uniqueID` — тоже
    /// UUID-формат, но другая таблица/пространство идентификаторов, коллизия практически невозможна.
    /// Поэтому корректный резолвер — не проверка формата строки, а реальный fetch по Account.id.
    func resolveNewCoreAccount(id: String?) -> Account? {
        guard let id, let uuid = UUID(uuidString: id) else { return nil }
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == uuid })
        return try? modelContext.fetch(descriptor).first
    }

    func touchesDebitAccount(_ transaction: CashflowTransaction) -> Bool {
        [resolveNewCoreAccount(id: transaction.cardID), resolveNewCoreAccount(id: transaction.toCardID)]
            .compactMap { $0?.productType }
            .contains(where: DebitCardContract.products.contains)
    }

    // MARK: - Публичная точка входа

    /// Синхронизирует событие(я) нового ядра для сохранённой транзакции. Вызывается ПОСЛЕ того,
    /// как легаси-путь (или его отсутствие) уже обработан — здесь мы только пишем в новый мир.
    func sync(for transaction: CashflowTransaction) async throws {
        switch transaction.transactionType {
        case .income, .expense, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            // creditDebtAdjustment, нацеленная на new-core счёт (.loan/.debt) — тот же `adjustment`,
            // что и balanceAdjustment/cardBalanceAdjustment: дельта, знак хранит создатель события
            // (Фаза 2 — реализовано; раньше это была молчаливая no-op-ветка, транзакция «сохранялась»,
            // но баланс кредита/долга не менялся вовсе).
            try await syncSimpleEvent(for: transaction)
        case .transfer:
            try await syncTransfer(for: transaction)
        }
    }

    /// Удаляет событие(я) нового ядра, связанное(ые) с удаляемой транзакцией. Для новых счетов
    /// «удаление без пересчёта» не существует — событие удаляется всегда с пересчётом кэша.
    func deleteEvents(for transaction: CashflowTransaction) throws {
        try accountsCoreService.deleteEvents(bySourceTransactionID: transaction.uniqueID)
    }

    // MARK: - income/expense/adjustment

    private func syncSimpleEvent(for transaction: CashflowTransaction) async throws {
        guard let account = resolveNewCoreAccount(id: transaction.cardID) else {
            // Цель — легаси-карта. Если раньше (до правки) целью был новый счёт — снимаем
            // оставшееся событие (риск №2, ветка новый→старый).
            try accountsCoreService.deleteEvents(bySourceTransactionID: transaction.uniqueID)
            return
        }

        if let product = account.productType, DebitCardContract.products.contains(product) {
            let resolved = try await resolveAmount(transaction: transaction, targetCurrency: account.currency)
            let kind: DebitCardOperationKind
            switch transaction.transactionType {
            case .income:
                kind = .income
            case .expense where transaction.amount < 0:
                guard let original = transaction.operationGroupID, !original.isEmpty else {
                    throw DebitCardOperationCoordinatorError.originalExpenseNotFound
                }
                kind = .refund(originalOperationID: original)
            case .expense:
                kind = .expense
            case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
                kind = .adjustment(reason: transaction.note ?? "")
            case .transfer:
                return
            }
            _ = try DebitCardOperationCoordinator(modelContext: modelContext).commitStagedCashflow(
                transaction, account: account, kind: kind, resolvedAmount: resolved.amount,
                originalAmount: resolved.originalAmount, originalCurrency: resolved.originalCurrency,
                fxRate: resolved.fxRate, fxProvisional: resolved.fxProvisional
            )
            return
        }

        let eventType: AccountEventType
        let categoryID: String?
        switch transaction.transactionType {
        case .income:
            eventType = .income
            categoryID = transaction.incomeCategoryRaw
        case .expense:
            eventType = .expense
            categoryID = transaction.expenseCategoryRaw
        case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            eventType = .adjustment
            categoryID = nil
        default:
            return
        }

        let resolved = try await resolveAmount(transaction: transaction, targetCurrency: account.currency)

        try accountsCoreService.upsertEvent(
            sourceTransactionID: transaction.uniqueID,
            account: account,
            type: eventType,
            amount: resolved.amount,
            date: transaction.transactionDate,
            categoryID: categoryID,
            note: transaction.note,
            originalAmount: resolved.originalAmount,
            originalCurrency: resolved.originalCurrency,
            fxRateUsed: resolved.fxRate,
            fxProvisional: resolved.fxProvisional
        )
    }

    // MARK: - Перевод

    /// Три случая (риск №1): оба новых — двуногий перевод ядра; смешанный (легаси↔новый) —
    /// ОДИНОЧНОЕ income/expense-событие на новом конце, БЕЗ transferID (легаси-нога считается
    /// легаси-кодом как раньше); оба легаси — не наша забота.
    private func syncTransfer(for transaction: CashflowTransaction) async throws {
        let source = resolveNewCoreAccount(id: transaction.cardID)
        let destination = resolveNewCoreAccount(id: transaction.toCardID)

        switch (source, destination) {
        case (nil, nil):
            try accountsCoreService.deleteEvents(bySourceTransactionID: transaction.uniqueID)

        case let (.some(source), .some(destination)):
            if DebitCardContract.products.contains(source.productType ?? .unknownLegacy),
               DebitCardContract.products.contains(destination.productType ?? .unknownLegacy) {
                let sourceAmount = try await convert(transaction.amount, from: transaction.currency, to: source.currency, on: transaction.transactionDate)
                let destinationAmount = try await convert(transaction.amount, from: transaction.currency, to: destination.currency, on: transaction.transactionDate)
                _ = try DebitCardOperationCoordinator(modelContext: modelContext).commitStagedTransfer(
                    transaction, from: source, to: destination,
                    sourceAmount: sourceAmount, destinationAmount: destinationAmount
                )
                return
            }
            // Пересоздаём пару целиком (просто и корректно для правок задним числом — сумма/курс
            // всегда пересчитываются заново; стабильность transferID между правками не нужна).
            try accountsCoreService.deleteEvents(bySourceTransactionID: transaction.uniqueID)
            let amountInSourceCurrency = try await convert(
                transaction.amount, from: transaction.currency, to: source.currency, on: transaction.transactionDate
            )
            var fxRate: Decimal?
            if source.currency != destination.currency {
                let rateResult = await historicalRateStore.getRate(
                    on: transaction.transactionDate, from: source.currency, to: destination.currency
                )
                fxRate = rateResult.rate.map(decimalFromDouble)
            }
            try accountsCoreService.transfer(
                from: source,
                to: destination,
                amountInSourceCurrency: amountInSourceCurrency,
                date: transaction.transactionDate,
                fxRate: fxRate,
                note: transaction.note,
                sourceTransactionID: transaction.uniqueID
            )

        case let (.some(source), nil):
            let resolved = try await resolveAmount(transaction: transaction, targetCurrency: source.currency)
            if DebitCardContract.products.contains(source.productType ?? .unknownLegacy) {
                _ = try DebitCardOperationCoordinator(modelContext: modelContext).commitStagedCashflow(
                    transaction, account: source, kind: .expense, resolvedAmount: resolved.amount,
                    eventNote: bridgeNote(transaction.note), originalAmount: resolved.originalAmount,
                    originalCurrency: resolved.originalCurrency, fxRate: resolved.fxRate,
                    fxProvisional: resolved.fxProvisional
                )
                return
            }
            try accountsCoreService.upsertEvent(
                sourceTransactionID: transaction.uniqueID,
                account: source,
                type: .expense,
                amount: resolved.amount,
                date: transaction.transactionDate,
                note: bridgeNote(transaction.note),
                originalAmount: resolved.originalAmount,
                originalCurrency: resolved.originalCurrency,
                fxRateUsed: resolved.fxRate,
                fxProvisional: resolved.fxProvisional
            )

        case let (nil, .some(destination)):
            let resolved = try await resolveAmount(transaction: transaction, targetCurrency: destination.currency)
            if DebitCardContract.products.contains(destination.productType ?? .unknownLegacy) {
                _ = try DebitCardOperationCoordinator(modelContext: modelContext).commitStagedCashflow(
                    transaction, account: destination, kind: .income, resolvedAmount: resolved.amount,
                    eventNote: bridgeNote(transaction.note), originalAmount: resolved.originalAmount,
                    originalCurrency: resolved.originalCurrency, fxRate: resolved.fxRate,
                    fxProvisional: resolved.fxProvisional
                )
                return
            }
            try accountsCoreService.upsertEvent(
                sourceTransactionID: transaction.uniqueID,
                account: destination,
                type: .income,
                amount: resolved.amount,
                date: transaction.transactionDate,
                note: bridgeNote(transaction.note),
                originalAmount: resolved.originalAmount,
                originalCurrency: resolved.originalCurrency,
                fxRateUsed: resolved.fxRate,
                fxProvisional: resolved.fxProvisional
            )
        }
    }

    private func bridgeNote(_ note: String?) -> String {
        let prefix = "перевод (легаси-мост)"
        guard let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return prefix
        }
        return "\(prefix): \(note)"
    }

    // MARK: - Конвертация/курс

    private struct ResolvedAmount {
        let amount: Decimal
        let originalAmount: Decimal?
        let originalCurrency: String?
        let fxRate: Decimal?
        let fxProvisional: Bool
    }

    /// Сумма транзакции в валюте счёта на дату СОБЫТИЯ (не сегодня — риск №6, правка задним
    /// числом переиспользует эту же функцию с новой датой). Курс недоступен (offline) →
    /// последний известный (`.previous`/`.current`) + `fxProvisional = true` (риск №8).
    private func resolveAmount(
        transaction: CashflowTransaction, targetCurrency: String
    ) async throws -> ResolvedAmount {
        let txCurrency = transaction.currency.uppercased()
        let target = targetCurrency.uppercased()

        guard txCurrency != target else {
            return ResolvedAmount(
                amount: decimalFromDouble(transaction.amount),
                originalAmount: nil, originalCurrency: nil, fxRate: nil, fxProvisional: false
            )
        }

        let result = await historicalRateStore.getRate(on: transaction.transactionDate, from: txCurrency, to: target)
        guard let rate = result.rate else {
            // Курс полностью недоступен (нет ни кэша, ни live) — крайний случай (неизвестная
            // валюта). Сохраняем оригинальную сумму как «сумму счёта» без конвертации, помечаем
            // provisional, чтобы UI/будущая правка могли уточнить курс отдельно.
            return ResolvedAmount(
                amount: decimalFromDouble(transaction.amount),
                originalAmount: decimalFromDouble(transaction.amount),
                originalCurrency: txCurrency,
                fxRate: nil,
                fxProvisional: true
            )
        }

        return ResolvedAmount(
            amount: decimalFromDouble(transaction.amount * rate),
            originalAmount: decimalFromDouble(transaction.amount),
            originalCurrency: txCurrency,
            fxRate: decimalFromDouble(rate),
            fxProvisional: result.resolution != .exact
        )
    }

    private func convert(_ amount: Double, from: String, to: String, on date: Date) async throws -> Decimal {
        guard from.uppercased() != to.uppercased() else { return decimalFromDouble(amount) }
        let result = await historicalRateStore.getRate(on: date, from: from, to: to)
        guard let rate = result.rate else {
            return decimalFromDouble(amount)
        }
        return decimalFromDouble(amount * rate)
    }

    /// Double → Decimal через строковое представление — прямой `Decimal(Double)` протаскивает
    /// артефакты двоичной плавающей точки (напр. 10.999999999999997952 вместо 11), см. конвенцию
    /// в AccountsCoreServiceTests.
    private func decimalFromDouble(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.6f", value)) ?? Decimal(value)
    }
}
