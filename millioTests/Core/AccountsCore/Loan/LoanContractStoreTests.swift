import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф2 кредита: контракт `LoanContractStore` и резолвера условий.
///
/// Ключевой риск спеки (№1) — два источника условий (`LoanContract` и легаси `LoanMeta`).
/// Резолвер обязан быть единственной точкой, где мета вообще читается.
@Suite(.serialized)
@MainActor
struct LoanContractStoreTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    @Test("Пустой стор: договора нет, чтение по любому ID не падает")
    func emptyStore() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let store = LoanContractStore(context: container.mainContext)
        #expect(try store.contract(for: UUID()) == nil)
    }

    @Test("upsert идемпотентен: два вызова на один accountID дают одну строку")
    func upsertIsIdempotent() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let store = LoanContractStore(context: context)
        let accountID = UUID()

        try store.upsert(accountID: accountID) { $0.principal = 1_200_000 }
        try store.upsert(accountID: accountID) { $0.annualRatePercent = 18.9; $0.termPeriods = 60 }
        try context.save()

        let rows = try context.fetch(FetchDescriptor<LoanContract>())
        #expect(rows.count == 1)
        #expect(rows.first?.principal == 1_200_000)
        #expect(rows.first?.annualRatePercent == 18.9)
    }

    @Test("Дубли по одному счёту схлопываются при следующем upsert")
    func duplicatesCollapseOnUpsert() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let accountID = UUID()
        // Restore/merge может внести вторую строку на тот же счёт: `@Attribute(.unique)` в проекте
        // недоступен (CloudKit), поэтому дубли — штатный, а не невозможный случай.
        context.insert(LoanContract(accountID: accountID, principal: 100, updatedAt: Date(timeIntervalSince1970: 1)))
        context.insert(LoanContract(accountID: accountID, principal: 200, updatedAt: Date(timeIntervalSince1970: 2)))
        try context.save()

        let store = LoanContractStore(context: context)
        try store.upsert(accountID: accountID) { $0.termPeriods = 60 }
        try context.save()

        let rows = try context.fetch(FetchDescriptor<LoanContract>())
        #expect(rows.count == 1)
        // Победитель — самая свежая строка, а не произвольная.
        #expect(rows.first?.principal == 200)
    }

    @Test("Договор отдаёт условия ядра без потерь")
    func contractProducesTerms() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let store = LoanContractStore(context: context)
        let accountID = UUID()
        let firstPayment = calendar.date(from: DateComponents(year: 2025, month: 2, day: 10))!

        let contract = try store.upsert(accountID: accountID) {
            $0.principal = 1_200_000
            $0.annualRatePercent = 18.9
            $0.termPeriods = 20
            $0.firstPaymentDate = firstPayment
            $0.frequency = .quarterly
            $0.scheduleType = .differentiated
            $0.paymentOverride = 50_000
        }

        let terms = contract.terms
        #expect(terms.principal == 1_200_000)
        #expect(terms.frequency == .quarterly)
        #expect(terms.scheduleType == .differentiated)
        #expect(terms.termPeriods == 20)
        #expect(terms.firstPaymentDate == firstPayment)
        #expect(terms.paymentOverride == 50_000)
    }

    // MARK: - Резолвер

    @Test("Резолвер: договор побеждает легаси LoanMeta")
    func resolverPrefersContract() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 10))!

        let account = try service.createAccount(
            name: "Кредит", kind: .loan, currency: "RUB", openingBalance: 1_200_000,
            loanMeta: LoanMeta(
                principal: 900_000, rate: 12, monthlyPayment: 20_000, paymentDay: 10,
                termEnd: nil, scheduleType: .annuity, insurance: nil
            ),
            date: opening
        )
        let contract = try LoanContractStore(context: context).upsert(accountID: account.id) {
            $0.principal = 1_200_000
            $0.annualRatePercent = 18.9
            $0.termPeriods = 60
            $0.firstPaymentDate = calendar.date(from: DateComponents(year: 2025, month: 2, day: 10))!
        }

        let terms = try #require(LoanTermsResolver.terms(for: account, contract: contract, calendar: calendar))
        #expect(terms.principal == 1_200_000)
        #expect(terms.annualRatePercent == 18.9)
        #expect(terms.paymentOverride == nil)
    }

    @Test("Резолвер: без договора условия сидятся из легаси LoanMeta")
    func resolverSeedsFromLegacyMeta() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 10))!
        let termEnd = calendar.date(from: DateComponents(year: 2029, month: 12, day: 10))!

        let account = try service.createAccount(
            name: "Кредит", kind: .loan, currency: "RUB", openingBalance: 1_200_000,
            loanMeta: LoanMeta(
                principal: 1_200_000, rate: 18.9, monthlyPayment: nil, paymentDay: 10,
                termEnd: termEnd, scheduleType: .annuity, insurance: nil
            ),
            date: opening
        )

        let terms = try #require(LoanTermsResolver.terms(for: account, contract: nil, calendar: calendar))
        #expect(terms.principal == 1_200_000)
        #expect(terms.frequency == .monthly)
        #expect(terms.firstPaymentDate == calendar.date(from: DateComponents(year: 2025, month: 2, day: 10)))
        #expect(terms.termPeriods == 59)
        #expect(terms.paymentOverride == nil)
    }

    @Test("Резолвер: нет ни договора, ни меты — условий нет, а не нули")
    func resolverReturnsNilWithoutAnySource() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let account = try service.createAccount(name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 100)
        #expect(LoanTermsResolver.terms(for: account, contract: nil, calendar: calendar) == nil)
    }

    @Test("Сид из меты без срока и без платежа невозможен — nil, а не выдуманный график")
    func legacySeedWithoutTermAndPaymentIsNil() {
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 10))!
        let meta = LoanMeta(
            principal: 500_000, rate: 10, monthlyPayment: nil, paymentDay: nil,
            termEnd: nil, scheduleType: .annuity, insurance: nil
        )
        #expect(LoanTerms(legacy: meta, openingDate: opening, calendar: calendar) == nil)
    }

    @Test("Сид из меты с ручным платежом: срок открытый, платёж переносится как override")
    func legacySeedWithManualPayment() throws {
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 10))!
        let meta = LoanMeta(
            principal: 500_000, rate: 10, monthlyPayment: 15_000, paymentDay: 5,
            termEnd: nil, scheduleType: .annuity, insurance: nil
        )
        let terms = try #require(LoanTerms(legacy: meta, openingDate: opening, calendar: calendar))
        #expect(terms.termPeriods == 0)
        #expect(terms.paymentOverride == 15_000)
        #expect(terms.firstPaymentDate == calendar.date(from: DateComponents(year: 2025, month: 2, day: 5)))
        // Срок в договоре не задан, но график всё равно строится — под ручной платёж.
        let schedule = LoanScheduleEngine.schedule(terms: terms, calendar: calendar)
        #expect(schedule.amortizes)
        #expect(schedule.rows.last?.balanceAfter == .zero)
    }
}
