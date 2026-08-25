import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Deposit atomic operation coordinator")
@MainActor
struct DepositOperationCoordinatorTests {
    private struct InjectedFailure: Error {}

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let depositID: UUID
        let sourceID: UUID
        let destinationID: UUID
        let opening: Date
        let maturity: Date
        let calendar: Calendar
    }

    private func fixture(
        allowsTopUp: Bool = true,
        allowsEarlyClose: Bool = true,
        penalty: Decimal? = 0.5
    ) throws -> Fixture {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let maturity = calendar.date(byAdding: .month, value: 3, to: opening)!
        let factory = AccountProductFactory(modelContext: context)
        let depositID = try factory.create(CreateProductCommand(
            productType: .deposit, name: "Deposit", currency: "RUB", openingBalance: 100_000,
            metadata: .init(deposit: DepositMeta(
                rate: 12, capitalization: .monthly, termEnd: maturity, payoutDay: nil,
                allowsTopUp: allowsTopUp, allowsEarlyClose: allowsEarlyClose,
                earlyClosePenalty: penalty, remindEnd: false, autoRollover: false
            )),
            date: opening, calendar: calendar
        ))
        let sourceID = try factory.create(CreateProductCommand(
            productType: .bankAccount, name: "Source", currency: "RUB", openingBalance: 50_000,
            date: opening
        ))
        let destinationID = try factory.create(CreateProductCommand(
            productType: .bankAccount, name: "Destination", currency: "RUB", openingBalance: 0,
            date: opening
        ))
        return Fixture(
            container: container, context: context, depositID: depositID,
            sourceID: sourceID, destinationID: destinationID,
            opening: opening, maturity: maturity, calendar: calendar
        )
    }

    private func account(_ id: UUID, in context: ModelContext) throws -> Account {
        try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == id })
    }

    private func events(_ id: UUID, in context: ModelContext) throws -> [AccountEvent] {
        try context.fetch(FetchDescriptor<AccountEvent>()).filter { $0.account?.id == id }
    }

    private func verificationContext(_ fixture: Fixture) -> ModelContext {
        ModelContext(fixture.container)
    }

    @Test("Top-up transfers funds once and rebuilds future estimates")
    func topUpIsAtomicAndIdempotent() throws {
        let value = try fixture()
        let coordinator = DepositOperationCoordinator(modelContext: value.context)
        let date = value.calendar.date(byAdding: .day, value: 10, to: value.opening)!
        let command = DepositTopUpCommand(
            operationID: "deposit-topup-1", sourceAccountID: value.sourceID,
            amount: 10_000, date: date
        )

        let first = try coordinator.topUp(depositID: value.depositID, command: command, calendar: value.calendar)
        let second = try coordinator.topUp(depositID: value.depositID, command: command, calendar: value.calendar)

        #expect(!first.wasAlreadyPersisted)
        #expect(second.wasAlreadyPersisted)
        let context = verificationContext(value)
        let depositEvents = try events(value.depositID, in: context)
        let sourceEvents = try events(value.sourceID, in: context)
        #expect(depositEvents.filter { $0.sourceTransactionID == "deposit-topup-1" }.count == 1)
        #expect(sourceEvents.filter { $0.sourceTransactionID == "deposit-topup-1" }.count == 1)
        #expect(AccountBalanceEngine.balanceAt(events: sourceEvents, kind: .bankAccount, on: date) == 40_000)
        #expect(depositEvents.filter { $0.type == .interest && $0.date > date }.count == 3)
        #expect(depositEvents.filter { $0.type == .interest && $0.date > date }.map(\.amount).contains(1_100))
    }

    @Test("Top-up validates magnitude, capability, currency and source funds")
    func topUpValidation() throws {
        let value = try fixture(allowsTopUp: false)
        let coordinator = DepositOperationCoordinator(modelContext: value.context)
        #expect(throws: DepositOperationError.invalidAmount) {
            try coordinator.topUp(depositID: value.depositID, command: .init(
                operationID: "zero", sourceAccountID: value.sourceID, amount: 0,
                date: value.opening
            ))
        }
        #expect(throws: DepositOperationError.topUpNotAllowed) {
            try coordinator.topUp(depositID: value.depositID, command: .init(
                operationID: "blocked", sourceAccountID: value.sourceID, amount: 1,
                date: value.opening
            ))
        }

        let allowed = try fixture()
        let allowedCoordinator = DepositOperationCoordinator(modelContext: allowed.context)
        #expect(throws: DepositOperationError.insufficientFunds) {
            try allowedCoordinator.topUp(depositID: allowed.depositID, command: .init(
                operationID: "large", sourceAccountID: allowed.sourceID, amount: 50_001,
                date: allowed.opening
            ))
        }
        let source = try account(allowed.sourceID, in: allowed.context)
        source.currency = "USD"
        try allowed.context.save()
        #expect(throws: DepositOperationError.currencyMismatch) {
            try allowedCoordinator.topUp(depositID: allowed.depositID, command: .init(
                operationID: "fx", sourceAccountID: allowed.sourceID, amount: 1,
                date: allowed.opening
            ))
        }
    }

    @Test("Partial withdrawal stays explicitly unsupported")
    func withdrawalIsNotGuessed() throws {
        let value = try fixture()
        #expect(throws: DepositOperationError.withdrawalUnsupported) {
            try DepositOperationCoordinator(modelContext: value.context).withdraw(
                depositID: value.depositID,
                command: .init(operationID: "withdraw", destinationAccountID: value.destinationID)
            )
        }
    }

    @Test("Confirmed interest replaces one estimate and retry stays idempotent")
    func confirmationReplacesEstimate() throws {
        let value = try fixture()
        let payout = value.calendar.date(byAdding: .month, value: 1, to: value.opening)!
        let coordinator = DepositOperationCoordinator(modelContext: value.context)
        let command = DepositInterestConfirmationCommand(
            operationID: "bank-interest-1", amount: 950, date: payout
        )

        let first = try coordinator.confirmInterest(
            depositID: value.depositID, command: command, calendar: value.calendar
        )
        let second = try coordinator.confirmInterest(
            depositID: value.depositID, command: command, calendar: value.calendar
        )

        #expect(!first.wasAlreadyPersisted)
        #expect(second.wasAlreadyPersisted)
        let context = verificationContext(value)
        let interest = try events(value.depositID, in: context).filter { $0.type == .interest }
        #expect(interest.filter { value.calendar.isDate($0.date, inSameDayAs: payout) }.count == 1)
        #expect(interest.first { $0.sourceTransactionID == "bank-interest-1" }?.amount == 950)
        let month2 = value.calendar.date(byAdding: .month, value: 2, to: value.opening)!
        #expect(interest.first { value.calendar.isDate($0.date, inSameDayAs: month2) }?.amount == Decimal(string: "1009.50"))
    }

    @Test("Balance correction appends one delta, preserves confirmed interest and rebuilds forecasts")
    func balanceAdjustmentIsAtomicAndIdempotent() throws {
        let value = try fixture()
        let coordinator = DepositOperationCoordinator(modelContext: value.context)
        let firstPayout = value.calendar.date(byAdding: .month, value: 1, to: value.opening)!
        _ = try coordinator.confirmInterest(
            depositID: value.depositID,
            command: .init(operationID: "confirmed-interest", amount: 900, date: firstPayout),
            calendar: value.calendar
        )
        let correctionDate = value.calendar.date(byAdding: .day, value: 1, to: firstPayout)!
        let command = DepositBalanceAdjustmentCommand(
            operationID: "balance-correction-1", newBalance: 120_000, date: correctionDate,
            note: "bank balance correction"
        )

        let first = try coordinator.adjustBalance(
            depositID: value.depositID, command: command, calendar: value.calendar
        )
        let second = try coordinator.adjustBalance(
            depositID: value.depositID, command: command, calendar: value.calendar
        )

        #expect(first.didChange)
        #expect(!first.wasAlreadyPersisted)
        #expect(second.wasAlreadyPersisted)
        let context = verificationContext(value)
        let depositEvents = try events(value.depositID, in: context)
        let adjustment = try #require(depositEvents.first { $0.sourceTransactionID == "balance-correction-1" })
        #expect(adjustment.type == .adjustment)
        #expect(adjustment.amount == 19_100)
        #expect(adjustment.note == "bank balance correction")
        #expect(depositEvents.first { $0.sourceTransactionID == "confirmed-interest" }?.amount == 900)
        #expect(AccountBalanceEngine.balanceAt(events: depositEvents, kind: .deposit, on: correctionDate) == 120_000)
        #expect(depositEvents.filter { $0.type == .interest && $0.date > correctionDate }.map(\.amount).contains(1_200))
    }

    @Test("Balance correction no-op writes no empty event and rejects invalid balances")
    func balanceAdjustmentNoOpAndValidation() throws {
        let value = try fixture()
        let coordinator = DepositOperationCoordinator(modelContext: value.context)
        let date = value.calendar.date(byAdding: .day, value: 10, to: value.opening)!
        let before = try events(value.depositID, in: verificationContext(value)).count

        let noOp = try coordinator.adjustBalance(
            depositID: value.depositID,
            command: .init(operationID: "same-balance", newBalance: 100_000, date: date),
            calendar: value.calendar
        )

        #expect(!noOp.didChange)
        let context = verificationContext(value)
        #expect(try events(value.depositID, in: context).count == before)
        #expect(try events(value.depositID, in: context).allSatisfy { $0.sourceTransactionID != "same-balance" })

        let zeroBalance = try coordinator.adjustBalance(
            depositID: value.depositID,
            command: .init(operationID: "zero-balance", newBalance: 0, date: date),
            calendar: value.calendar
        )
        #expect(zeroBalance.didChange)
        let adjustedEvents = try events(value.depositID, in: verificationContext(value))
        #expect(adjustedEvents.first { $0.sourceTransactionID == "zero-balance" }?.amount == -100_000)
        #expect(throws: DepositOperationError.invalidBalance) {
            try coordinator.adjustBalance(
                depositID: value.depositID,
                command: .init(operationID: "negative", newBalance: -1, date: date),
                calendar: value.calendar
            )
        }
    }

    @Test("Balance correction rolls back event and future forecast at every mutation stage", arguments: [
        DepositOperationStage.primaryEvent, .futureCleanup, .schedule, .save
    ])
    func balanceAdjustmentRollback(stage: DepositOperationStage) throws {
        let value = try fixture()
        let date = value.calendar.date(byAdding: .day, value: 10, to: value.opening)!
        let before = verificationContext(value)
        let baseline = try events(value.depositID, in: before).map {
            ($0.id, $0.typeRaw, $0.amount, $0.date, $0.sourceTransactionID)
        }

        #expect(throws: InjectedFailure.self) {
            try DepositOperationCoordinator(modelContext: value.context).adjustBalance(
                depositID: value.depositID,
                command: .init(operationID: "failed-correction", newBalance: 120_000, date: date),
                calendar: value.calendar,
                stageHook: { visited in
                    if visited == stage { throw InjectedFailure() }
                }
            )
        }

        let after = try events(value.depositID, in: verificationContext(value)).map {
            ($0.id, $0.typeRaw, $0.amount, $0.date, $0.sourceTransactionID)
        }
        #expect(Set(after.map(String.init(describing:))) == Set(baseline.map(String.init(describing:))))
    }

    @Test("Terms edit preserves confirmed past and replaces only future schedule")
    func termsEditPreservesPast() throws {
        let value = try fixture()
        let coordinator = DepositOperationCoordinator(modelContext: value.context)
        let payout = value.calendar.date(byAdding: .month, value: 1, to: value.opening)!
        _ = try coordinator.confirmInterest(
            depositID: value.depositID,
            command: .init(operationID: "confirmed", amount: 900, date: payout),
            calendar: value.calendar
        )
        let newTerm = value.calendar.date(byAdding: .month, value: 4, to: value.opening)!
        let newMeta = DepositMeta(
            rate: 24, capitalization: .monthly, termEnd: newTerm, payoutDay: nil,
            allowsTopUp: true, allowsEarlyClose: true, earlyClosePenalty: 0.5,
            remindEnd: false, autoRollover: false
        )

        _ = try coordinator.editTerms(
            depositID: value.depositID,
            command: .init(meta: newMeta, effectiveDate: payout, calendar: value.calendar)
        )
        _ = try coordinator.editTerms(
            depositID: value.depositID,
            command: .init(meta: newMeta, effectiveDate: payout, calendar: value.calendar)
        )

        let context = verificationContext(value)
        let deposit = try account(value.depositID, in: context)
        let interest = try events(value.depositID, in: context).filter { $0.type == .interest }
        #expect(deposit.depositMeta == newMeta)
        #expect(interest.first { $0.sourceTransactionID == "confirmed" }?.amount == 900)
        #expect(interest.filter { $0.date > payout }.count == 3)
        #expect(interest.filter { $0.date > payout }.map(\.amount).contains(2_018))
    }

    @Test("Terms edit rolls back metadata and schedule at every mutation stage", arguments: [
        DepositOperationStage.futureCleanup, .metadata, .schedule, .save
    ])
    func termsEditRollback(stage: DepositOperationStage) throws {
        let value = try fixture()
        let baselineContext = ModelContext(value.container)
        let baselineMeta = try #require(try account(value.depositID, in: baselineContext).depositMeta)
        let baselineEvents = try events(value.depositID, in: baselineContext).map {
            ($0.typeRaw, $0.amount, $0.date, $0.sourceTransactionID)
        }
        let effective = value.calendar.date(byAdding: .day, value: 10, to: value.opening)!
        let newMeta = DepositMeta(
            rate: 20, capitalization: .monthly, termEnd: value.maturity, payoutDay: nil,
            allowsTopUp: true, allowsEarlyClose: true, earlyClosePenalty: 0.5,
            remindEnd: false, autoRollover: false
        )

        #expect(throws: InjectedFailure.self) {
            try DepositOperationCoordinator(modelContext: value.context).editTerms(
                depositID: value.depositID,
                command: .init(meta: newMeta, effectiveDate: effective, calendar: value.calendar),
                stageHook: { visited in
                    if visited == stage { throw InjectedFailure() }
                }
            )
        }

        let context = verificationContext(value)
        #expect(try account(value.depositID, in: context).depositMeta == baselineMeta)
        let afterEvents = try events(value.depositID, in: context).map {
            ($0.typeRaw, $0.amount, $0.date, $0.sourceTransactionID)
        }
        let fingerprint: ((String, Decimal?, Date, String?)) -> String = { item in
            let amount = item.1.map { "\($0)" } ?? "nil"
            return "\(item.0)|\(amount)|\(item.2.timeIntervalSince1970)|\(item.3 ?? "nil")"
        }
        #expect(afterEvents.count == baselineEvents.count)
        #expect(Set(afterEvents.map(fingerprint)) == Set(baselineEvents.map(fingerprint)))
    }

    @Test("Early close applies penalty to confirmed interest and commits one graph")
    func earlyCloseIsAtomicAndIdempotent() throws {
        let value = try fixture()
        let payout = value.calendar.date(byAdding: .month, value: 1, to: value.opening)!
        let coordinator = DepositOperationCoordinator(modelContext: value.context)
        _ = try coordinator.confirmInterest(
            depositID: value.depositID,
            command: .init(operationID: "confirmed", amount: 1_000, date: payout),
            calendar: value.calendar
        )
        let closeDate = value.calendar.date(byAdding: .day, value: 1, to: payout)!
        let command = DepositTransferCommand(
            operationID: "early-close-1", destinationAccountID: value.destinationID,
            date: closeDate
        )

        let first = try coordinator.earlyClose(depositID: value.depositID, command: command)
        let second = try coordinator.earlyClose(depositID: value.depositID, command: command)

        #expect(!first.wasAlreadyPersisted)
        #expect(second.wasAlreadyPersisted)
        let context = verificationContext(value)
        let deposit = try account(value.depositID, in: context)
        let depositEvents = try events(value.depositID, in: context)
        let destinationEvents = try events(value.destinationID, in: context)
        #expect(deposit.archivedAt == closeDate)
        #expect(depositEvents.first { $0.note == "early_close_penalty" }?.amount == 500)
        #expect(destinationEvents.first { $0.sourceTransactionID == "early-close-1" }?.amount == 100_500)
    }

    @Test("Every early-close stage failure leaves no partial graph", arguments: [
        DepositOperationStage.validation, .load, .futureCleanup, .penalty,
        .transferOut, .transferIn, .archive, .save
    ])
    func earlyCloseStageRollback(stage: DepositOperationStage) throws {
        let value = try fixture()
        let coordinator = DepositOperationCoordinator(modelContext: value.context)
        let payout = value.calendar.date(byAdding: .month, value: 1, to: value.opening)!
        _ = try coordinator.confirmInterest(
            depositID: value.depositID,
            command: .init(operationID: "confirmed", amount: 1_000, date: payout),
            calendar: value.calendar
        )
        let before = ModelContext(value.container)
        let baselineEventCount = try before.fetchCount(FetchDescriptor<AccountEvent>())
        let closeDate = value.calendar.date(byAdding: .day, value: 1, to: payout)!

        #expect(throws: InjectedFailure.self) {
            try coordinator.earlyClose(
                depositID: value.depositID,
                command: .init(
                    operationID: "failed-close", destinationAccountID: value.destinationID,
                    date: closeDate
                ),
                stageHook: { visited in
                    if visited == stage { throw InjectedFailure() }
                }
            )
        }

        let context = verificationContext(value)
        #expect(try context.fetchCount(FetchDescriptor<AccountEvent>()) == baselineEventCount)
        #expect(try account(value.depositID, in: context).archivedAt == nil)
        #expect(try events(value.destinationID, in: context).filter { $0.sourceTransactionID == "failed-close" }.isEmpty)
    }

    @Test("Save failure cannot be resurrected by a later unrelated save")
    func failedSaveDoesNotLeak() throws {
        let value = try fixture()
        let coordinator = DepositOperationCoordinator(
            modelContext: value.context,
            saveOperation: { _ in throw InjectedFailure() }
        )
        #expect(throws: AccountsCorePersistenceError.self) {
            try coordinator.topUp(
                depositID: value.depositID,
                command: .init(
                    operationID: "failed-topup", sourceAccountID: value.sourceID,
                    amount: 1_000, date: value.opening
                ),
                calendar: value.calendar
            )
        }
        let unrelated = AccountGroup(name: "Unrelated")
        value.context.insert(unrelated)
        try value.context.save()

        let context = verificationContext(value)
        #expect(try context.fetchCount(FetchDescriptor<AccountGroup>()) == 1)
        #expect(try context.fetch(FetchDescriptor<AccountEvent>()).filter { $0.sourceTransactionID == "failed-topup" }.isEmpty)
    }

    @Test("Maturity is explicit and transfers confirmed balance only")
    func maturityCommand() throws {
        let value = try fixture()
        let coordinator = DepositOperationCoordinator(modelContext: value.context)
        #expect(throws: DepositOperationError.notMatured) {
            try coordinator.mature(
                depositID: value.depositID,
                command: .init(
                    operationID: "too-early", destinationAccountID: value.destinationID,
                    date: value.opening
                )
            )
        }
        _ = try coordinator.mature(
            depositID: value.depositID,
            command: .init(
                operationID: "maturity", destinationAccountID: value.destinationID,
                date: value.maturity
            )
        )

        let context = verificationContext(value)
        #expect(try account(value.depositID, in: context).archivedAt == value.maturity)
        #expect(try events(value.destinationID, in: context).first { $0.sourceTransactionID == "maturity" }?.amount == 100_000)
    }

    @Test("Rollover is explicit, idempotent and creates a new future schedule")
    func rolloverCommand() throws {
        let value = try fixture()
        let coordinator = DepositOperationCoordinator(modelContext: value.context)
        let newTerm = value.calendar.date(byAdding: .month, value: 3, to: value.maturity)!
        let newMeta = DepositMeta(
            rate: 10, capitalization: .monthly, termEnd: newTerm, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: true, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        let command = DepositRolloverCommand(
            operationID: "rollover-1", meta: newMeta,
            date: value.maturity, calendar: value.calendar
        )

        let first = try coordinator.rollover(depositID: value.depositID, command: command)
        let second = try coordinator.rollover(depositID: value.depositID, command: command)

        #expect(!first.wasAlreadyPersisted)
        #expect(second.wasAlreadyPersisted)
        let context = verificationContext(value)
        #expect(try account(value.depositID, in: context).depositMeta == newMeta)
        let depositEvents = try events(value.depositID, in: context)
        #expect(depositEvents.filter { $0.sourceTransactionID == "rollover-1" }.count == 1)
        #expect(depositEvents.filter { $0.type == .interest && $0.date > value.maturity }.count == 3)
    }

    /// Путь записи объединённой формы правки вклада (`DepositTermsEditSheet`): условия — через
    /// `editTerms`, сумма — через ТОТ ЖЕ `adjustBalance`, что и отдельный лист коррекции баланса.
    /// Интеграционный, а не инвариантный: проверяется именно последовательность вызовов из
    /// `AccountDetailView`, потому что порядок (условия → сумма) влияет на пересборку графика.
    @Test("Terms edit followed by balance adjustment persists both without losing history")
    func termsEditAndBalanceAdjustmentShareTheWriters() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Вклад должен быть ЖИВЫМ на момент правки: `validateTerms` требует termEnd в будущем.
        let now = Date()
        let opening = calendar.date(byAdding: .day, value: -30, to: now)!
        let termEnd = calendar.date(byAdding: .day, value: 335, to: now)!
        let depositID = try AccountProductFactory(modelContext: context).create(CreateProductCommand(
            productType: .deposit, name: "Deposit", currency: "RUB", openingBalance: 100_000,
            metadata: .init(deposit: DepositMeta(
                rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
                allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
                remindEnd: false, autoRollover: false
            )),
            date: opening, calendar: calendar
        ))

        let coordinator = DepositOperationCoordinator(modelContext: context)
        let editedMeta = DepositMeta(
            rate: 15, capitalization: .customDays(30), termEnd: termEnd, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false, isTaxable: true
        )
        _ = try coordinator.editTerms(
            depositID: depositID,
            command: DepositTermsEditCommand(meta: editedMeta, effectiveDate: now, calendar: calendar)
        )
        _ = try coordinator.adjustBalance(
            depositID: depositID,
            command: DepositBalanceAdjustmentCommand(
                operationID: "deposit-balance-adjustment:terms-edit",
                newBalance: 120_000, date: now
            ),
            calendar: calendar
        )

        let verification = ModelContext(container)
        let deposit = try account(depositID, in: verification)
        #expect(deposit.depositMeta == editedMeta)
        #expect(deposit.depositMeta?.isTaxable == true)

        let all = try events(depositID, in: verification)
        // Открытие не переписано — правка условий и коррекция суммы не трогают прошлое.
        #expect(all.filter { $0.type == .openingBalance }.count == 1)
        #expect(all.first { $0.type == .openingBalance }?.amount == 100_000)
        // Сумма записана дельтой через adjustBalance, а не подменой открытия.
        let adjustments = all.filter { $0.type == .adjustment }
        #expect(adjustments.count == 1)
        #expect(adjustments.first?.amount == 20_000)
        let confirmed = all.filter {
            !DepositDetailPresentation.isGeneratedForecastEvent($0, accountID: depositID)
        }
        #expect(AccountBalanceEngine.balanceAt(events: confirmed, kind: .deposit, on: now) == 120_000)
        // График будущего пересобран уже по НОВОЙ периодичности: шаг 30 дней от даты открытия.
        let future = all.filter { $0.type == .interest && $0.date > now }.map(\.date).sorted()
        #expect(!future.isEmpty)
        for date in future {
            let days = calendar.dateComponents([.day], from: opening, to: date).day ?? 0
            #expect(days % 30 == 0)
        }
    }
}
