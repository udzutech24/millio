import Foundation
import SwiftData
import Testing
@testable import millio

/// БАГ 5 (release-2.0-blockers): `CashflowScheduledService.applyDuePlannedTransactionsIfNeeded`
/// собирает due-строки ОДИН раз до цикла и безусловно двигает чекпойнт на `referenceNow` в конце.
/// Плановый платёж кредита пересоздаёт РОВНО одну новую строку на следующий период
/// (`LoanPlannedPaymentScheduler.sync`) — она физически появляется в базе только ПОСЛЕ apply текущей
/// и в уже собранный список попасть не может. При 2+ пропущенных периодах вторая и последующие
/// missed-строки навсегда остаются за пределами окна [чекпойнт, сейчас] — долг замирает после
/// первого догоняющего платежа. Регрессия для millio/UI/Services/Cashflow/CashflowScheduledService.swift.
@Suite(.serialized)
@MainActor
struct LoanMissedPaymentsCatchUpTests {

    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Три пропущенных периода догоняются ОДНИМ вызовом авто-применения")
    func threeMissedPeriodsCatchUpInOneCall() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext

        let account = try AccountsCoreService(modelContext: context).createAccount(
            name: "Автокредит",
            kind: .loan,
            currency: "RUB",
            openingBalance: 1_200_000,
            date: day(2026, 3, 15)
        )
        let contract = try LoanContractStore(context: context).upsert(accountID: account.id) { contract in
            contract.principal = 1_200_000
            contract.annualRatePercent = 12
            contract.termPeriods = 60
            // Три периода раньше referenceNow (2026-08-01): 05.05, 05.06, 05.07 — все ≤ referenceNow.
            // Четвёртый (05.08) строго позже referenceNow и в окно попадать не должен.
            contract.firstPaymentDate = day(2026, 5, 5)
            contract.scheduleType = .annuity
            contract.frequency = .monthly
        }
        try context.save()

        let referenceNow = day(2026, 8, 1)
        let suiteName = "tests.loan.missed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let scope = "millio_user_owner"
        defaults.set(
            day(2026, 4, 1),
            forKey: CashflowScheduledService.dueAutoApplyCheckpointKeyPrefix + scope
        )

        let service = CashflowScheduledService(
            modelContext: context,
            defaults: defaults,
            scopeIdentifier: scope,
            now: { referenceNow },
            transactionsProvider: { try! context.fetch(FetchDescriptor<CashflowTransaction>()) },
            onTransactionsMutated: {},
            onResolveExchangeInfo: { _ in CashflowExchangeInfo(rate: nil, rateDate: nil, rateCurrency: nil) },
            onApplyRecurringToCard: { _ in },
            onApplyDuePlannedEffect: { _ in },
            appliedNoticeStore: AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: scope),
            noticeAccountNameResolver: { _ in account.name },
            noticeTitleResolver: { _ in account.name }
        )

        let didApply = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)

        #expect(didApply)
        // До фикса: один проход применяет только первый пропущенный платёж — вторая и третья
        // missed-строки создаются уже ПОСЛЕ того, как due-список собран, и остаются за окном
        // навсегда (чекпойнт безусловно уходит на referenceNow). На старом коде здесь было бы
        // paymentsMade == 1.
        #expect(contract.paymentsMade == 3)
    }
}
