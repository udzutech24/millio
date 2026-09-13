import Foundation
import SwiftData

/// Жизненный цикл плановой операции кредита в Cashflow: создать, обновить сумму и дату, снять.
///
/// Инвариант (спека §1): у активного кредита с договором в Cashflow всегда ровно ОДНА непринятая
/// плановая операция — ближайший платёж по графику. Второго способа внести платёж нет: применение
/// этой операции проходит через `LoanPaymentRecorder`, иначе расход списался бы, а долг остался.
///
/// Почему разовая операция, а не recurring-шаблон: у шаблона `shouldAffectCashflowTotals == false`
/// (он маркер настройки, а не расход), поэтому кредит снова выпал бы из бюджета — ровно та беда,
/// ради которой фаза и делается. Плюс сумма платежа каждый период разная и график кончается: живой
/// шаблон с фиксированной суммой продолжал бы «платить» после закрытия кредита. Периодичность
/// договора выражает `recurrenceRule(for:)` — витрины Ф3.4 показывают ею шаг плана.
enum LoanPlannedPaymentScheduler {

    /// Тот же namespace, что у фактических проводок платежа: обе стороны — «платёж по кредиту»,
    /// и различает их префикс ключа, а не источник.
    static var importSource: String { LoanPaymentCashflowProjector.importSource }

    /// Префикс ключа непринятой плановой операции. Фактические проводки (`LoanPaymentCashflowProjector`)
    /// живут под ключом-UUID платежа, поэтому по префиксу план и факт не путаются.
    static let plannedKeyPrefix = "plan:"

    // MARK: - Ключи

    /// Ключ уникален по номеру платежа: после применения `paymentsMade` растёт, и следующая
    /// плановая операция получает свой ключ — дедуп проектора не принимает её за уже проведённую.
    static func plannedReferenceKey(accountID: UUID, paymentIndex: Int) -> String {
        "\(plannedKeyPrefix)\(accountID.uuidString):\(paymentIndex)"
    }

    static func accountID(fromPlannedKey key: String) -> UUID? {
        guard key.hasPrefix(plannedKeyPrefix) else { return nil }
        let body = key.dropFirst(plannedKeyPrefix.count)
        guard let separator = body.firstIndex(of: ":") else { return nil }
        return UUID(uuidString: String(body[body.startIndex..<separator]))
    }

    /// Строка принадлежит плану кредита (в отличие от фактической проводки платежа — у той ключ
    /// без префикса). Признак «уже применена» здесь не проверяется: он свой у каждого вызывающего
    /// (окно авто-применения фильтрует по `hasAppliedBalanceEffect`, `applyPlannedPayment` — отбивает).
    static func isPlannedRow(_ transaction: CashflowTransaction) -> Bool {
        transaction.importSourceRaw == importSource
            && (transaction.importReferenceKey?.hasPrefix(plannedKeyPrefix) ?? false)
    }

    // MARK: - Периодичность

    /// Периодичность договора в терминах плановых операций Cashflow. Отображение полное: под
    /// `every2Months` в модель Cashflow заведено собственное правило (решение владельца 07.09) —
    /// подгонять двухмесячный кредит под квартал значило бы врать про дату каждого второго платежа.
    static func recurrenceRule(for frequency: LoanPaymentFrequency) -> CashflowRecurrenceRule {
        switch frequency {
        case .monthly: return .monthly
        case .every2Months: return .every2Months
        case .quarterly: return .quarterly
        case .semiannual: return .semiannual
        case .annual: return .yearly
        }
    }

    // MARK: - Синхронизация

    /// Приводит план счёта к текущему состоянию договора и ленты: создаёт, обновляет сумму/дату или
    /// снимает операцию. Идемпотентно — два вызова подряд дают одну строку.
    ///
    /// Контекст НЕ сохраняется: вызывающий закрывает свою транзакцию сам (тот же контракт, что у
    /// `LoanPaymentCashflowProjector`).
    ///
    /// Счёт и договор резолвятся здесь по `accountID`, а не приходят параметрами: тогда «счёт удалён»
    /// и «договора больше нет» — не отдельная ветка у каждого вызывающего, а один и тот же путь
    /// снятия плана, и сирот не остаётся по построению.
    @discardableResult
    static func sync(
        accountID: UUID,
        context: ModelContext,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> CashflowTransaction? {
        guard let account = try account(id: accountID, context: context),
              account.kind == .loan,
              account.deletedAt == nil,
              account.archivedAt == nil,
              let contract = try LoanContractStore(context: context).contract(for: accountID),
              let next = try nextPayment(account: account, contract: contract, calendar: calendar)
        else {
            try remove(accountID: accountID, context: context)
            return nil
        }

        let rows = try openPlannedRows(accountID: accountID, context: context)
        for duplicate in rows.dropFirst() { context.delete(duplicate) }

        let target = rows.first ?? {
            let created = CashflowTransaction(
                transactionType: .expense,
                amount: 0,
                currency: account.currency,
                transactionDate: next.date,
                // Категории «кредит» в каталоге нет — та же `.other`, что у фактической проводки
                // платежа: иначе план и факт разошлись бы по категориям в отчётах.
                expenseCategory: .other,
                importSourceRaw: importSource,
                importReferenceKey: plannedReferenceKey(accountID: accountID, paymentIndex: 0),
                // С какого счёта уйдут деньги, кредит не знает — иначе применение задвоило бы
                // движение по счёту-источнику.
                affectsCardBalance: false
            )
            context.insert(created)
            return created
        }()

        target.amount = NSDecimalNumber(decimal: next.payment).doubleValue
        target.currency = account.currency
        target.transactionDate = next.date
        target.note = account.name.isEmpty ? nil : account.name
        target.importReferenceKey = plannedReferenceKey(
            accountID: accountID,
            paymentIndex: contract.paymentsMade + 1
        )
        target.updatedAt = Date()
        return target
    }

    /// Снимает непринятую плановую операцию счёта. Применённые строки — уже факт расхода, их
    /// удаление стёрло бы историю платежей.
    static func remove(accountID: UUID, context: ModelContext) throws {
        for row in try openPlannedRows(accountID: accountID, context: context) { context.delete(row) }
    }

    /// Ближайшая непринятая плановая операция счёта — то, что деталка показывает строкой
    /// «запланирован в Cashflow» и что применяет кнопка «Внести платёж».
    static func openPlannedRow(accountID: UUID, context: ModelContext) throws -> CashflowTransaction? {
        try openPlannedRows(accountID: accountID, context: context).first
    }

    // MARK: - Применение

    /// «Внести платёж» с экрана: применяет ближайшую плановую операцию сейчас.
    ///
    /// Плана нет (сбой синхронизации, восстановление бэкапа старого формата) — сначала
    /// восстанавливаем его, и только потом применяем: заводить в обход плана «просто платёж»
    /// значило бы вернуть второй путь записи, ради устранения которого фаза и делалась.
    @MainActor
    static func applyNextPlannedPayment(
        accountID: UUID,
        context: ModelContext,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws {
        var row = try openPlannedRow(accountID: accountID, context: context)
        if row == nil {
            row = try sync(accountID: accountID, context: context, calendar: calendar)
            try context.save()
        }
        guard let row else { throw LoanPlannedPaymentError.nothingToPay }
        try applyPlannedPayment(row, context: context, calendar: calendar)
        try context.save()
    }

    /// Применение плановой операции: тело — в ленту счёта, проценты — в договор, план сдвигается на
    /// следующий платёж. Единственный путь, которым плановая операция кредита превращается в деньги.
    ///
    /// Сама строка Cashflow повторно НЕ создаётся: она уже существует (это и есть план) и просто
    /// становится фактом — поэтому её ключ передаётся в recorder, и дедуп проектора гасит вставку.
    @MainActor
    static func applyPlannedPayment(
        _ transaction: CashflowTransaction,
        context: ModelContext,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws {
        // Применённая строка — уже факт расхода: второй проход по ней списал бы платёж дважды.
        guard isPlannedRow(transaction),
              !transaction.hasAppliedBalanceEffect,
              let key = transaction.importReferenceKey,
              let accountID = accountID(fromPlannedKey: key) else {
            throw LoanPlannedPaymentError.notAPlannedPayment
        }
        guard let account = try account(id: accountID, context: context), account.kind == .loan else {
            throw LoanPlannedPaymentError.accountUnavailable
        }
        guard let contract = try LoanContractStore(context: context).contract(for: accountID),
              let next = try nextPayment(account: account, contract: contract, calendar: calendar) else {
            throw LoanPlannedPaymentError.nothingToPay
        }

        // Закрытый месяц отбивает платёж ЦЕЛИКОМ и до любых правок: строка Cashflow уже лежит в
        // базе, поэтому дедуп проектора внутри recorder до проверки политики не дошёл бы.
        try CashflowMonthMutationPolicy(modelContext: context).validate(
            .scheduledApply,
            date: transaction.transactionDate
        )

        // Флаг ставится ДО записи: recorder пересинхронизирует план, и открытой эта строка уже
        // считаться не должна — иначе следующий платёж переписал бы её вместо создания новой.
        transaction.hasAppliedBalanceEffect = true
        transaction.amount = NSDecimalNumber(decimal: next.principal + next.interest).doubleValue

        do {
            // Событие ленты датируется не позже реального момента оплаты: `transactionDate` у
            // досрочного платежа лежит в будущем, а `AccountBalanceEngine.balanceAt(on: Date())`
            // (витрина, кламп досрочки) отбрасывает события с будущей датой — без `min` долг на
            // экране не уменьшался бы сразу после списания. Для просроченных/автоприменённых
            // платежей `transactionDate` уже в прошлом, `min` — no-op.
            try LoanPaymentRecorder(modelContext: context).recordScheduledPayment(
                account: account,
                principalPart: next.principal,
                interestPart: next.interest,
                date: min(transaction.transactionDate, Date()),
                cashflowReferenceKey: key
            )
        } catch {
            transaction.hasAppliedBalanceEffect = false
            throw error
        }
    }

    // MARK: - Private

    /// Ближайший платёж по факту: остаток берётся из ленты, «что впереди» считает ядро
    /// (`remainingTerms` + `schedule`) — тем же методом живут деталка, график и лист досрочки.
    private static func nextPayment(
        account: Account,
        contract: LoanContract,
        calendar: Calendar
    ) throws -> LoanScheduleRow? {
        // Отсечка — `distantFuture`, а не «сегодня»: плановый платёж записывается СВОЕЙ датой, и
        // она бывает в будущем. С отсечкой по «сегодня» долг выглядел бы непогашенным, и план
        // после платежа остался бы стоять на том же периоде.
        let balance = AccountBalanceEngine.balanceAt(
            events: account.events ?? [],
            kind: .loan,
            on: .distantFuture
        )
        let outstanding = LoanOutstanding.fromLedger(balance: balance)
        guard outstanding > 0 else { return nil }

        let ahead = LoanScheduleEngine.schedule(
            terms: LoanScheduleEngine.remainingTerms(
                terms: contract.terms,
                outstanding: outstanding,
                paymentsMade: contract.paymentsMade,
                calendar: calendar
            ),
            calendar: calendar
        )
        return ahead.rows.first
    }

    /// Непринятые плановые строки счёта. Фильтр в памяти, а не предикатом: `#Predicate` по
    /// опциональной строке с `hasPrefix` SwiftData не поддерживает (тот же приём, что в проекторе).
    private static func openPlannedRows(
        accountID: UUID,
        context: ModelContext
    ) throws -> [CashflowTransaction] {
        let prefix = "\(plannedKeyPrefix)\(accountID.uuidString):"
        return try context.fetch(FetchDescriptor<CashflowTransaction>())
            .filter { transaction in
                transaction.importSourceRaw == importSource
                    && !transaction.hasAppliedBalanceEffect
                    && (transaction.importReferenceKey?.hasPrefix(prefix) ?? false)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private static func account(id: UUID, context: ModelContext) throws -> Account? {
        try context.fetch(
            FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == id })
        ).first
    }
}

enum LoanPlannedPaymentError: LocalizedError {
    case notAPlannedPayment
    case accountUnavailable
    case nothingToPay

    var errorDescription: String? {
        switch self {
        case .notAPlannedPayment, .accountUnavailable:
            L("accounts_core.loan.detail.error.not_a_loan")
        case .nothingToPay:
            L("accounts_core.loan.detail.error.payment_below_interest")
        }
    }
}
