import Foundation
import SwiftData
import Testing
@testable import millio

/// Phase 1 locks the existing deposit contract before its writers/readers are redesigned.
/// Expectations marked as compatibility debt deliberately describe unsafe current behavior;
/// later phases must replace them together with the matching spec decision.
@Suite("Deposit product vertical characterization", .serialized)
@MainActor
struct DepositProductVerticalCharacterizationTests {

    private enum InjectedFailure: Error { case save }

    private func makeContext() throws -> (ModelContainer, ModelContext, AccountsCoreService) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        return (container, context, AccountsCoreService(modelContext: context))
    }

    private func calendar(_ identifier: String) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: identifier)!
        return value
    }

    private func depositMeta(
        capitalization: AccountDepositCapitalization = .monthly,
        termEnd: Date?,
        payoutDay: Int? = nil,
        allowsTopUp: Bool = false,
        allowsEarlyClose: Bool = false,
        remindEnd: Bool = false,
        autoRollover: Bool = false
    ) -> DepositMeta {
        DepositMeta(
            rate: 12,
            capitalization: capitalization,
            termEnd: termEnd,
            payoutDay: payoutDay,
            allowsTopUp: allowsTopUp,
            allowsEarlyClose: allowsEarlyClose,
            earlyClosePenalty: nil,
            remindEnd: remindEnd,
            autoRollover: autoRollover
        )
    }

    @Test("ACT/365: leap interval uses 366 numerator days and a fixed 365 denominator")
    func leapIntervalUsesExplicitAct365() {
        let utc = calendar("UTC")
        let opening = utc.date(from: DateComponents(year: 2023, month: 7, day: 1))!
        let termEnd = utc.date(from: DateComponents(year: 2024, month: 7, day: 1))!
        var meta = depositMeta(capitalization: .none, termEnd: termEnd)
        meta.rate = 10

        let schedule = DepositInterestScheduler.buildInitialSchedule(
            accountID: UUID(), meta: meta, openingBalance: 100_000,
            openingDate: opening, calendar: utc
        )

        #expect(schedule.count == 1)
        #expect(schedule.first?.amount == Decimal(string: "10027.40")!)
    }

    @Test("Month-end recurrence clamps each period from the original January day")
    func januaryMonthEndScheduleIsStable() {
        let utc = calendar("UTC")
        let expectedDays: [Int: [Int]] = [
            28: [28, 28, 28, 28],
            29: [28, 29, 29, 29],
            30: [28, 30, 30, 30],
            31: [28, 31, 30, 31],
        ]

        for (openingDay, days) in expectedDays {
            let opening = utc.date(from: DateComponents(year: 2025, month: 1, day: openingDay))!
            let termEnd = utc.date(byAdding: .month, value: 4, to: opening)!
            let schedule = DepositInterestScheduler.buildInitialSchedule(
                accountID: UUID(), meta: depositMeta(termEnd: termEnd), openingBalance: 100_000,
                openingDate: opening, calendar: utc
            )
            #expect(schedule.map { utc.component(.day, from: $0.date) } == days)
            #expect(schedule.map(\.amount) == [1_000, 1_010, Decimal(string: "1020.10")!, Decimal(string: "1030.30")!])
        }
    }

    @Test("Local-midnight schedules retain the same local calendar dates across DST zones")
    func scheduleCalendarDatesAreStableAcrossTimeZones() {
        for timeZoneID in ["UTC", "Europe/Istanbul", "America/Los_Angeles"] {
            let local = calendar(timeZoneID)
            let opening = local.date(from: DateComponents(year: 2025, month: 2, day: 28))!
            let termEnd = local.date(byAdding: .month, value: 3, to: opening)!
            let schedule = DepositInterestScheduler.buildInitialSchedule(
                accountID: UUID(), meta: depositMeta(termEnd: termEnd), openingBalance: 100_000,
                openingDate: opening, calendar: local
            )

            #expect(schedule.map { local.dateComponents([.year, .month, .day], from: $0.date) } == [
                DateComponents(year: 2025, month: 3, day: 28),
                DateComponents(year: 2025, month: 4, day: 28),
                DateComponents(year: 2025, month: 5, day: 28),
            ])
        }
    }

    @Test("Compatibility debt: dayKey depends on the process time zone at event creation")
    func dayKeyUsesCurrentProcessTimeZone() {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        let instant = Date(timeIntervalSince1970: 1_750_000_000)

        NSTimeZone.default = TimeZone(identifier: "Asia/Tokyo")!
        let tokyo = AccountEvent(account: nil, date: instant, type: .interest, amount: 1)
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        let losAngeles = AccountEvent(account: nil, date: instant, type: .interest, amount: 1)

        #expect(tokyo.dayKey == "2025-06-16")
        #expect(losAngeles.dayKey == "2025-06-15")
        #expect(tokyo.dayKey != losAngeles.dayKey)
    }

    @Test("Bug characterization: generated forecast becomes accrued balance after its date")
    func generatedForecastCrossesIntoAccruedBalanceWithoutConfirmation() throws {
        let (container, context, service) = try makeContext()
        _ = container
        let utc = calendar("UTC")
        let opening = utc.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let payout = utc.date(byAdding: .month, value: 1, to: opening)!
        let account = try service.createAccount(
            name: "Forecast", kind: .deposit, currency: "RUB", openingBalance: 100_000, date: opening
        )
        account.depositMeta = depositMeta(termEnd: payout)
        try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: utc, context: context
        )

        let before = utc.date(byAdding: .second, value: -1, to: payout)!
        #expect(AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .deposit, on: before) == 100_000)
        #expect(AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .deposit, on: payout) == 101_000)
        #expect((account.events ?? []).first { $0.type == .interest }?.sourceTransactionID?.hasPrefix("deposit-interest:") == true)
    }

    @Test("Bug characterization: generic deposit expense accepts a negative magnitude")
    func negativeExpenseIncreasesDepositBalance() throws {
        let (container, _, service) = try makeContext()
        _ = container
        let account = try service.createAccount(
            name: "Deposit", kind: .deposit, currency: "RUB", openingBalance: 100
        )

        _ = try service.recordEvent(account: account, type: .expense, amount: -10)

        #expect(AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .deposit, on: Date()) == 110)
    }

    @Test("Bug characterization: oversized transfer can make a deposit negative")
    func oversizedTransferIsPersisted() throws {
        let (container, _, service) = try makeContext()
        _ = container
        let deposit = try service.createAccount(
            name: "Deposit", kind: .deposit, currency: "RUB", openingBalance: 100
        )
        let destination = try service.createAccount(
            name: "Cash", kind: .cash, currency: "RUB", openingBalance: 0
        )

        _ = try service.transfer(from: deposit, to: destination, amountInSourceCurrency: 150)

        #expect(AccountBalanceEngine.balanceAt(events: deposit.events ?? [], kind: .deposit, on: Date()) == -50)
        #expect(AccountBalanceEngine.balanceAt(events: destination.events ?? [], kind: .cash, on: Date()) == 150)
    }

    @Test("Compatibility debt: lifecycle flags do not alter the generated schedule")
    func lifecycleFlagsAreSchedulerInert() {
        let utc = calendar("UTC")
        let opening = utc.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = utc.date(byAdding: .month, value: 3, to: opening)!
        let accountID = UUID()
        let baseline = DepositInterestScheduler.buildInitialSchedule(
            accountID: accountID, meta: depositMeta(termEnd: termEnd), openingBalance: 100_000,
            openingDate: opening, calendar: utc
        )
        let enabled = DepositInterestScheduler.buildInitialSchedule(
            accountID: accountID,
            meta: depositMeta(
                termEnd: termEnd, payoutDay: 15, allowsTopUp: true, allowsEarlyClose: true,
                remindEnd: true, autoRollover: true
            ),
            openingBalance: 100_000, openingDate: opening, calendar: utc
        )

        #expect(enabled == baseline)
    }

    @Test("Compatibility debt: early close exposes no injectable save-failure stages")
    func earlyCloseBypassesInjectedSaveBoundary() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        var injectedSaveCalls = 0
        let service = AccountsCoreService(modelContext: context) { _ in
            injectedSaveCalls += 1
            throw InjectedFailure.save
        }
        let deposit = try service.createAccount(
            name: "Deposit", kind: .deposit, currency: "RUB", openingBalance: 100
        )
        deposit.depositMeta = depositMeta(termEnd: nil, allowsEarlyClose: true)
        let destination = try service.createAccount(
            name: "Cash", kind: .cash, currency: "RUB", openingBalance: 0
        )

        try service.earlyCloseDeposit(deposit, transferTo: destination)

        #expect(injectedSaveCalls == 0)
        #expect(deposit.archivedAt != nil)
        #expect(AccountBalanceEngine.balanceAt(events: destination.events ?? [], kind: .cash, on: Date()) == 100)
    }

    @Test("Corrupt required DepositMeta removes only the meta while preserving the account")
    func corruptDepositMetaRestoresAsNil() throws {
        let registryState = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(registryState) }
        FinanceFeatureRegistration.register()
        CardFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()

        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Deposit", kind: .deposit, currency: "RUB")
        account.depositMeta = depositMeta(termEnd: nil)
        context.insert(account)
        try context.save()

        var json = try JSONSerialization.jsonObject(with: DataRepository.exportAllData(from: context)) as! [String: Any]
        var models = json["models"] as! [[String: Any]]
        for index in models.indices where models[index]["_type"] as? String == "Account" {
            var meta = models[index]["depositMeta"] as! [String: Any]
            meta["rate"] = "not-a-decimal"
            models[index]["depositMeta"] = meta
        }
        json["models"] = models
        let corrupted = try JSONSerialization.data(withJSONObject: json)

        let repository = DataRepository(modelContext: context, modelContainer: container)
        try repository.clearAllData()
        try repository.importAllData(corrupted)

        let restored = try #require(context.fetch(FetchDescriptor<Account>()).first)
        #expect(restored.kind == .deposit)
        #expect(restored.depositMeta == nil)
    }
}
