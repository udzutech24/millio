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

        // Снимок, как в приложении: `CashflowViewModel` передаёт `{ self?.state.transactions ?? [] }` —
        // замороженный на время вызова массив, а не живой fetch. Раньше тест звал `context.fetch`
        // заново на каждый вызов провайдера, что маскировало Баг 5: догонка внутри цикла обязана
        // читать базу напрямую (см. фикс в `fetchDueTransactions()`), а не полагаться на провайдер.
        let transactionsSnapshot = try context.fetch(FetchDescriptor<CashflowTransaction>())

        let service = CashflowScheduledService(
            modelContext: context,
            defaults: defaults,
            scopeIdentifier: scope,
            now: { referenceNow },
            transactionsProvider: { transactionsSnapshot },
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

    /// Решение владельца 10.09: кредитная plan-строка, застрявшая ЗА чекпойнтом из-за старого
    /// Бага 5 (чекпойнт когда-то ушёл вперёд, а строку никто не применил), всё равно догоняется —
    /// её нижняя граница окна не проверяется (только `hasAppliedBalanceEffect` и `<= referenceNow`).
    @Test("Кредитный платёж, застрявший за чекпойнтом, применяется один раз — повтор ничего не меняет")
    func stuckLoanPaymentCatchesUpAndStaysIdempotent() async throws {
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
            contract.firstPaymentDate = day(2026, 5, 5)
            contract.scheduleType = .annuity
            contract.frequency = .monthly
        }
        try context.save()

        let suiteName = "tests.loan.stuck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let scope = "millio_user_owner"
        // Чекпойнт УЖЕ ушёл вперёд платёжной строки (05.05) — ровно та ситуация, в которой Баг 5
        // оставлял платёж замороженным навсегда: без обхода нижней границы `date > previousCheckpoint`
        // строка 05.05 никогда не попадёт в окно снова.
        defaults.set(
            day(2026, 5, 10),
            forKey: CashflowScheduledService.dueAutoApplyCheckpointKeyPrefix + scope
        )

        func makeService(now referenceNow: @escaping () -> Date) -> CashflowScheduledService {
            CashflowScheduledService(
                modelContext: context,
                defaults: defaults,
                scopeIdentifier: scope,
                now: referenceNow,
                transactionsProvider: { try! context.fetch(FetchDescriptor<CashflowTransaction>()) },
                onTransactionsMutated: {},
                onResolveExchangeInfo: { _ in CashflowExchangeInfo(rate: nil, rateDate: nil, rateCurrency: nil) },
                onApplyRecurringToCard: { _ in },
                onApplyDuePlannedEffect: { _ in },
                appliedNoticeStore: AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: scope),
                noticeAccountNameResolver: { _ in account.name },
                noticeTitleResolver: { _ in account.name }
            )
        }

        // Следующий период (05.06) строго позже referenceNow первого прогона — попадает в окно
        // только застрявшая строка 05.05, прогресса от обычной догонки здесь нет.
        let firstRun = day(2026, 5, 20)
        let didApplyFirst = await makeService(now: { firstRun }).applyDuePlannedTransactionsIfNeeded(referenceNow: firstRun)

        #expect(didApplyFirst)
        #expect(contract.paymentsMade == 1)

        // Второй прогон — новых due-строк нет (следующий платёж 05.06 ещё не наступил); повторного
        // списания быть не должно.
        let secondRun = day(2026, 5, 25)
        let didApplySecond = await makeService(now: { secondRun }).applyDuePlannedTransactionsIfNeeded(referenceNow: secondRun)

        #expect(!didApplySecond)
        #expect(contract.paymentsMade == 1)
    }

    /// Контрольный кейс: L3 расширяет окно ТОЛЬКО для кредитных plan-строк
    /// (`LoanPlannedPaymentScheduler.isPlannedRow`). Обычная некредитная строка, застрявшая за тем же
    /// чекпойнтом, по-прежнему не подхватывается — нижнюю границу для неё никто не снимал.
    @Test("Некредитная строка, застрявшая за чекпойнтом, не подхватывается")
    func stuckNonLoanTransactionStaysExcluded() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext

        let stuck = CashflowTransaction(
            transactionType: .expense,
            amount: 500,
            currency: "RUB",
            transactionDate: day(2026, 5, 5),
            expenseCategory: .other
        )
        context.insert(stuck)
        try context.save()

        let suiteName = "tests.loan.stuck.nonloan.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let scope = "millio_user_owner"
        defaults.set(
            day(2026, 5, 10),
            forKey: CashflowScheduledService.dueAutoApplyCheckpointKeyPrefix + scope
        )

        var applyCallCount = 0
        let referenceNow = day(2026, 5, 20)
        let service = CashflowScheduledService(
            modelContext: context,
            defaults: defaults,
            scopeIdentifier: scope,
            now: { referenceNow },
            transactionsProvider: { try! context.fetch(FetchDescriptor<CashflowTransaction>()) },
            onTransactionsMutated: {},
            onResolveExchangeInfo: { _ in CashflowExchangeInfo(rate: nil, rateDate: nil, rateCurrency: nil) },
            onApplyRecurringToCard: { _ in },
            onApplyDuePlannedEffect: { _ in applyCallCount += 1 },
            appliedNoticeStore: AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: scope),
            noticeAccountNameResolver: { _ in "" },
            noticeTitleResolver: { _ in "" }
        )

        let didApply = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)

        #expect(!didApply)
        #expect(applyCallCount == 0)
        #expect(!stuck.hasAppliedBalanceEffect)
    }

    /// L2: внутри одного вызова цикл ретраит упавшие некредитные строки, пока проходы дают прогресс
    /// (прогресс здесь даёт кредитная догонка — 3 прохода на 3 пропущенных периода). Обычная строка,
    /// применённая на первом проходе, не должна списываться повторно на втором и третьем.
    @Test("Внутри одного вызова успешно применённая строка не применяется дважды")
    func successfulRowIsNotReappliedWithinSingleCall() async throws {
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
            // Три пропущенных периода — тот же расклад, что и в `threeMissedPeriodsCatchUpInOneCall`,
            // но здесь важно, что цикл внутри вызова реально проходит НЕСКОЛЬКО раз.
            contract.firstPaymentDate = day(2026, 5, 5)
            contract.scheduleType = .annuity
            contract.frequency = .monthly
        }
        // Обычная due-строка внутри того же окна — должна применяться только на первом проходе.
        let ordinary = CashflowTransaction(
            transactionType: .expense,
            amount: 500,
            currency: "RUB",
            transactionDate: day(2026, 5, 10),
            expenseCategory: .other
        )
        context.insert(ordinary)
        try context.save()

        let referenceNow = day(2026, 8, 1)
        let suiteName = "tests.loan.noreapply.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let scope = "millio_user_owner"
        defaults.set(
            day(2026, 4, 1),
            forKey: CashflowScheduledService.dueAutoApplyCheckpointKeyPrefix + scope
        )

        var ordinaryApplyCount = 0
        let service = CashflowScheduledService(
            modelContext: context,
            defaults: defaults,
            scopeIdentifier: scope,
            now: { referenceNow },
            transactionsProvider: { try! context.fetch(FetchDescriptor<CashflowTransaction>()) },
            onTransactionsMutated: {},
            onResolveExchangeInfo: { _ in CashflowExchangeInfo(rate: nil, rateDate: nil, rateCurrency: nil) },
            onApplyRecurringToCard: { _ in },
            onApplyDuePlannedEffect: { transaction in
                if transaction.persistentModelID == ordinary.persistentModelID {
                    ordinaryApplyCount += 1
                }
            },
            appliedNoticeStore: AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: scope),
            noticeAccountNameResolver: { _ in account.name },
            noticeTitleResolver: { _ in account.name }
        )

        let didApply = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)

        #expect(didApply)
        #expect(contract.paymentsMade == 3)
        // Ключевая проверка L2: несмотря на 3 прохода цикла (по одному на каждый пропущенный
        // платёж), обычная строка применилась РОВНО один раз.
        #expect(ordinaryApplyCount == 1)
        #expect(ordinary.hasAppliedBalanceEffect)
    }

    /// Ревью на L1: прямой fetch внутри цикла (замена `transactionsProvider()`) на проходах 2+ видит
    /// не только новую plan-строку кредита (ожидаемо — ради неё и сделан обход), но и ЛЮБУЮ другую
    /// незавершённую строку, которую успела вставить ПАРАЛЛЕЛЬНАЯ MainActor-задача генерации
    /// повторяющихся операций (`scheduleRecurringGeneration` в том же тике `loadTransactions()`,
    /// см. `CashflowViewModel.swift:438-439`): та делает `insert()` сразу, а
    /// `hasAppliedBalanceEffect` выставляет только после `await` конвертации валюты
    /// (`CashflowPersistenceService.swift:567,578`). Если обе MainActor-задачи чередуются между
    /// этими точками, догонка подхватила бы чужую строку и применила бы её ЕЩЁ РАЗ здесь же —
    /// двойное списание. Тест симулирует гонку синхронно (без реального Task-чередования): во время
    /// apply обычной due-строки на первом проходе в контекст вставляется вторая, ранее не входившая
    /// в due-список строка — ровно то же самое, что видел бы прямой fetch следующего прохода, если
    /// бы её успел вставить параллельный генератор.
    @Test("Строка, появившаяся в контексте между проходами цикла, не подхватывается этим же вызовом")
    func rowInsertedMidCallByAnotherTaskIsNotSweptUpWithinSameCall() async throws {
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
            // Три пропущенных периода — нужно НЕСКОЛЬКО проходов цикла, иначе гонка (строка
            // появляется МЕЖДУ проходами) не воспроизводится вообще.
            contract.firstPaymentDate = day(2026, 5, 5)
            contract.scheduleType = .annuity
            contract.frequency = .monthly
        }
        // Обычная due-строка первого прохода — во время её apply симулируем гонку.
        let ordinary = CashflowTransaction(
            transactionType: .expense,
            amount: 500,
            currency: "RUB",
            transactionDate: day(2026, 5, 10),
            expenseCategory: .other
        )
        context.insert(ordinary)
        try context.save()

        let referenceNow = day(2026, 8, 1)
        let suiteName = "tests.loan.race.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let scope = "millio_user_owner"
        defaults.set(
            day(2026, 4, 1),
            forKey: CashflowScheduledService.dueAutoApplyCheckpointKeyPrefix + scope
        )

        // "Чужая" строка — как будто её вставил параллельный генератор повторяющихся операций, но
        // применить ещё не успел (в реальности — не дошёл до `await` конвертации валюты). Дата в
        // окне [previousCheckpoint, referenceNow], как у любой настоящей due-строки.
        var raceRowInserted = false
        var raceRowApplyCount = 0
        let raceRowDate = day(2026, 5, 12)
        var raceRow: CashflowTransaction?

        let service = CashflowScheduledService(
            modelContext: context,
            defaults: defaults,
            scopeIdentifier: scope,
            now: { referenceNow },
            transactionsProvider: { try! context.fetch(FetchDescriptor<CashflowTransaction>()) },
            onTransactionsMutated: {},
            onResolveExchangeInfo: { _ in CashflowExchangeInfo(rate: nil, rateDate: nil, rateCurrency: nil) },
            onApplyRecurringToCard: { _ in },
            onApplyDuePlannedEffect: { transaction in
                if transaction.persistentModelID == ordinary.persistentModelID, !raceRowInserted {
                    raceRowInserted = true
                    let row = CashflowTransaction(
                        transactionType: .expense,
                        amount: 777,
                        currency: "RUB",
                        transactionDate: raceRowDate,
                        expenseCategory: .other
                    )
                    context.insert(row)
                    raceRow = row
                }
                if let raceRow, transaction.persistentModelID == raceRow.persistentModelID {
                    raceRowApplyCount += 1
                }
            },
            appliedNoticeStore: AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: scope),
            noticeAccountNameResolver: { _ in account.name },
            noticeTitleResolver: { _ in account.name }
        )

        let didApply = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)

        #expect(didApply)
        // Кредитная догонка при этом отрабатывает как прежде — фикс её не трогает.
        #expect(contract.paymentsMade == 3)
        // Ключевая проверка: строка, появившаяся МЕЖДУ проходами и не являющаяся кредитной
        // plan-строкой, этим же вызовом не применяется — её увидит только следующий отдельный вызов
        // (когда её реально доведёт до конца свой генератор).
        #expect(raceRowApplyCount == 0)
        #expect(raceRow?.hasAppliedBalanceEffect != true)
    }
}
