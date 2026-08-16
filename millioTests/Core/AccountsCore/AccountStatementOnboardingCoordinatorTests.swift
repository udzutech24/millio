import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Account statement onboarding atomic coordinator")
@MainActor
struct AccountStatementOnboardingCoordinatorTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        return value
    }

    private func date(_ day: Int, month: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private func makeStack(
        saveOperation: @escaping AccountsCoreSaveBoundary.SaveOperation = { try $0.save() }
    ) throws -> (ModelContainer, ModelContext, AccountStatementOnboardingCoordinator) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        return (
            container,
            container.mainContext,
            AccountStatementOnboardingCoordinator(
                modelContext: container.mainContext,
                calendar: calendar,
                saveOperation: saveOperation
            )
        )
    }

    private func operation(
        fingerprint: String,
        accountID: UUID,
        amount: Decimal = -100,
        currency: String = "RUB",
        day: Int = 10
    ) -> CashflowApprovedStatementOperation {
        .init(
            fingerprint: fingerprint,
            date: date(day),
            amount: amount,
            currency: currency,
            type: amount > 0 ? .income : .expense,
            categoryRaw: amount > 0 ? IncomeCategory.salary.rawValue : ExpenseCategory.bills.rawValue,
            accountID: accountID.uuidString,
            note: "Reviewed row"
        )
    }

    private func command(
        accountID: UUID = UUID(),
        onboardingID: String = "onboarding-1",
        balance: Decimal = 1_000,
        operations: ((UUID) -> [CashflowApprovedStatementOperation])? = nil,
        periodTo: Date? = nil
    ) -> AccountStatementOnboardingCommand {
        let rows = operations?(accountID) ?? [
            operation(fingerprint: "expense-1", accountID: accountID),
            operation(fingerprint: "income-1", accountID: accountID, amount: 250, day: 11)
        ]
        return .init(
            create: .init(
                accountID: accountID,
                productType: .debitCard,
                name: "Statement account",
                currency: "RUB",
                openingBalance: balance,
                date: date(31),
                calendar: calendar
            ),
            operations: rows,
            balanceConfirmation: .manual(amount: balance, currency: "RUB", asOf: date(31)),
            statementPeriodFrom: date(1),
            statementPeriodTo: periodTo ?? date(31),
            onboardingID: onboardingID
        )
    }

    @Test("Account, anchor and reviewed rows commit once without changing account balance")
    func successGraph() throws {
        let (_, context, coordinator) = try makeStack()
        let input = command()

        let result = try coordinator.apply(input)

        #expect(result.accountID == input.create.accountID)
        #expect(result.insertedFingerprints == ["expense-1", "income-1"])
        #expect(result.skippedFingerprints.isEmpty)
        #expect(result.wasAlreadyApplied == false)
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        let opening = try #require(context.fetch(FetchDescriptor<AccountEvent>()).first)
        let rows = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(account.id == input.create.accountID)
        #expect(opening.type == .openingBalance)
        #expect(opening.amount == 1_000)
        #expect(opening.sourceTransactionID == "statement-onboarding:onboarding-1")
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.cardID == account.id.uuidString })
        #expect(rows.allSatisfy { $0.affectsCardBalance == false && $0.shouldAffectCashflowTotals })
        #expect(Set(rows.map(\.uniqueID)) == [
            "bank_statement_v1:expense-1", "bank_statement_v1:income-1"
        ])
    }

    @Test("Identical retry converges to the original graph")
    func idempotentRetry() throws {
        let (_, context, coordinator) = try makeStack()
        let input = command(accountID: UUID(), onboardingID: "stable")
        _ = try coordinator.apply(input)
        let retry = try coordinator.apply(input)

        #expect(retry.wasAlreadyApplied)
        #expect(retry.insertedFingerprints.isEmpty)
        #expect(retry.skippedFingerprints == ["expense-1", "income-1"])
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AccountEvent>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<CashflowTransaction>()) == 2)
    }

    @Test("Two queued coordinators with one stable command converge through the MainActor writer")
    func twoCoordinatorTasksConverge() async throws {
        let (container, context, firstCoordinator) = try makeStack()
        let secondCoordinator = AccountStatementOnboardingCoordinator(
            modelContext: context,
            calendar: calendar
        )
        let input = command(accountID: UUID(), onboardingID: "queued-race")

        let first = Task { @MainActor in try firstCoordinator.apply(input) }
        let second = Task { @MainActor in try secondCoordinator.apply(input) }
        let firstResult = try await first.value
        let secondResult = try await second.value
        let results = [firstResult, secondResult]

        #expect(results.filter(\.wasAlreadyApplied).count == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<AccountEvent>()) == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<CashflowTransaction>()) == 2)
    }

    @Test("Same onboarding key with a different payload fails closed")
    func conflictingRetry() throws {
        let (_, context, coordinator) = try makeStack()
        let accountID = UUID()
        _ = try coordinator.apply(command(accountID: accountID, onboardingID: "stable"))

        #expect(throws: AccountStatementOnboardingError.idempotencyConflict) {
            try coordinator.apply(command(accountID: accountID, onboardingID: "stable", balance: 2_000))
        }
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<CashflowTransaction>()) == 2)
    }

    @Test("Every injected coordinator stage leaves no partial graph", arguments: AccountStatementOnboardingStage.allCases)
    func stageFailureIsAtomic(stage: AccountStatementOnboardingStage) throws {
        let (_, context, coordinator) = try makeStack()
        #expect(throws: AccountStatementOnboardingError.injectedFailure(stage)) {
            try coordinator.apply(command()) { visited in
                if visited == stage { throw AccountStatementOnboardingError.injectedFailure(stage) }
            }
        }
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AccountEvent>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CashflowTransaction>()) == 0)
    }

    @Test("Durable save failure rolls back account, anchor and rows")
    func saveFailureIsAtomic() throws {
        struct SaveFailure: Error {}
        let (_, context, coordinator) = try makeStack { _ in throw SaveFailure() }
        do {
            _ = try coordinator.apply(command())
            Issue.record("Expected persistence failure")
        } catch let AccountsCorePersistenceError.saveFailed(operation, underlying) {
            #expect(operation == .createProduct)
            #expect(underlying is SaveFailure)
        }
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AccountEvent>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CashflowTransaction>()) == 0)
    }

    @Test("Fingerprint attributed to another account is a conflict and no account is created")
    func attributionConflict() throws {
        let (_, context, coordinator) = try makeStack()
        let existing = CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "RUB",
            transactionDate: date(10),
            cardID: UUID().uuidString,
            expenseCategory: .bills,
            importSourceRaw: CashflowStatementStagingService.importSource,
            importReferenceKey: "expense-1",
            affectsCardBalance: false,
            affectsCashflowTotals: true
        )
        context.insert(existing)
        try context.save()

        #expect(throws: AccountStatementOnboardingError.attributionConflict("expense-1")) {
            try coordinator.apply(command())
        }
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CashflowTransaction>()) == 1)
    }

    @Test("Closed month is revalidated inside the atomic transaction")
    func closedMonthRace() throws {
        let (_, context, coordinator) = try makeStack()
        context.insert(CashflowMonthClosureEvent(monthStart: date(1), kind: .close, occurredAt: date(31)))
        try context.save()

        #expect(throws: AccountStatementOnboardingError.closedMonth) {
            try coordinator.apply(command())
        }
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CashflowTransaction>()) == 0)
    }

    @Test("Duplicate request fingerprints fail before persistence")
    func duplicateWithinRequest() throws {
        let (_, context, coordinator) = try makeStack()
        let input = command(operations: { accountID in
            [
                operation(fingerprint: "same", accountID: accountID),
                operation(fingerprint: "same", accountID: accountID, day: 11)
            ]
        })
        #expect(throws: AccountStatementOnboardingError.duplicateFingerprint) {
            try coordinator.apply(input)
        }
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
    }

    @Test("Mixed currency and multi-month scope fail closed")
    func financialScopeValidation() throws {
        let (_, context, coordinator) = try makeStack()
        let mixed = command(operations: { accountID in
            [operation(fingerprint: "usd", accountID: accountID, currency: "USD")]
        })
        #expect(throws: AccountStatementOnboardingError.currencyMismatch) {
            try coordinator.apply(mixed)
        }
        #expect(throws: AccountStatementOnboardingError.invalidStatementPeriod) {
            try coordinator.apply(command(periodTo: date(1, month: 8)))
        }
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
    }

    @Test("Zero approved rows may still create the explicitly confirmed balance snapshot")
    func zeroApprovedRows() throws {
        let (_, context, coordinator) = try makeStack()
        let result = try coordinator.apply(command(operations: { _ in [] }))
        #expect(result.insertedFingerprints.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AccountEvent>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<CashflowTransaction>()) == 0)
    }
}
