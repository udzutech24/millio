//
//  AccountBalancePerformanceTests.swift
//  millioTests
//
//  Ф0 плана 2026-09-05__scroll-navigation-performance: воспроизводимая базовая линия стоимости
//  реплея ленты событий счёта. Instruments на устройстве владельца недоступен — эта линия
//  заменяет его и служит замером «до/после» для кэша баланса (Ф1).
//
//  XCTest (а не Swift Testing) осознанно: `measure {}` живёт только в XCTest.
//

import XCTest
import SwiftData
@testable import millio

/// Замер горячего пути «строка списка счетов»: `FinanceViewModel.newCoreBalanceToday`.
/// Фикстура приближена к реальности владельца: 62 счёта, 30–200 событий на счёт, 3 валюты,
/// разные kind (включая вклад с `DepositConfirmedBalanceResolver`) и события редоминации.
@MainActor
final class AccountBalancePerformanceTests: XCTestCase {

    /// Столько счетов у владельца на устройстве (вместе с двойниками) — худший реальный случай.
    private static let accountCount = 62

    /// Столько групп на экране «Счета» у владельца — каждая гоняет свой `isGroupEmpty`.
    private static let groupCount = 6

    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: FinanceViewModel!
    private var accounts: [Account] = []
    private var groups: [AccountGroup] = []

    /// Счёт с медианным числом событий — для сценария «одна строка».
    private var medianAccount: Account { accounts[accounts.count / 2] }

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Побочный конвертер цели накопления не должен лезть в фон во время замера.
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "finance_savings_goal_enabled")
        defaults.set(0, forKey: "finance_savings_goal_amount")

        container = try AppMigrationPlan.makeInMemoryContainer()
        context = container.mainContext
        let fixture = try Self.makeFixture(context: context)
        accounts = fixture.accounts
        groups = fixture.groups
        viewModel = FinanceViewModel(
            modelContext: context,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
    }

    override func tearDownWithError() throws {
        viewModel = nil
        accounts = []
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Собственный замер

    /// `measure {}` пишет метрики только в xcresult, а новый `xcresulttool` их наружу не отдаёт —
    /// поэтому цифры для отчёта считаем и печатаем сами, детерминированно и без зависимости от Xcode.
    /// Маркер `PERF|` — то, по чему грепается лог прогона.
    private func report(_ label: String, iterations: Int = 20, block: () -> Void) {
        block() // прогрев: первый проход тянет ленивые связи SwiftData и искажает среднее
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let elapsed = ContinuousClock().measure(block).components
            samples.append(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count)
        let line = String(format: "PERF| %@ | mean %.3f ms | stddev %.3f ms | n=%d",
                          label, mean * 1000, variance.squareRoot() * 1000, iterations)
        // Активность видна в xcresult (`xcresulttool`), в отличие от `print` из раннера в симуляторе.
        XCTContext.runActivity(named: line) { _ in }
        NSLog("%@", line)
    }

    // MARK: - Сценарии замера

    /// (а) Один вызов на один счёт. Замер идёт пачкой по 100 итераций: одиночный реплей
    /// укладывается в микросекунды и тонет в шуме таймера — делить результат на 100.
    func testPerformance_singleAccountBalance_x100() {
        let account = medianAccount
        report("single account × 100") {
            MainActor.assumeIsolated {
                for _ in 0..<100 { _ = viewModel.newCoreBalanceToday(account) }
            }
        }
        measure {
            MainActor.assumeIsolated {
                for _ in 0..<100 {
                    _ = viewModel.newCoreBalanceToday(account)
                }
            }
        }
    }

    /// (б) «Проход списка» — по одному вызову на каждый из 62 счетов. Эмуляция ОДНОГО прохода
    /// body экрана «Счета» (в реальности проходов на скролл несколько, и `sortedAccounts`
    /// добавляет сверху ещё один такой же круг через `displayCurrencyBalances`).
    func testPerformance_fullListPass_62accounts() {
        let all = accounts
        report("list pass × 62 accounts") {
            MainActor.assumeIsolated {
                for account in all { _ = viewModel.newCoreBalanceToday(account) }
            }
        }
        measure {
            MainActor.assumeIsolated {
                for account in all {
                    _ = viewModel.newCoreBalanceToday(account)
                }
            }
        }
    }

    /// (в) Проход body всего экрана «Счета» — то, что реально стоит владельцу кадров.
    /// Повторяет `FinancesView`: `isGroupEmpty` по каждой группе (`orderedAccounts` +
    /// легаси-хвост), затем `ungroupedAccounts()` (живой FetchDescriptor), затем баланс
    /// на каждую отрисованную строку. Один вызов = один проход, скролл делает их много.
    func testPerformance_screenBodyPass() {
        let allGroups = groups
        report("screen body pass") {
            MainActor.assumeIsolated {
                var rendered: [Account] = []
                for group in allGroups {
                    let inGroup = viewModel.orderedAccounts(for: group)
                    let legacy = viewModel.legacyAccountsMatchingGroupName(group.name)
                    guard !(inGroup.isEmpty && legacy.isEmpty) else { continue }
                    rendered.append(contentsOf: inGroup)
                }
                rendered.append(contentsOf: viewModel.ungroupedAccounts())
                for account in rendered {
                    _ = viewModel.newCoreBalanceToday(account)
                }
            }
        }
    }

    // MARK: - Фикстура

    /// Детерминированный генератор: цифры замера должны воспроизводиться между прогонами.
    private struct SeededRandom {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next(upTo bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    static func makeFixture(context: ModelContext) throws -> (accounts: [Account], groups: [AccountGroup]) {
        let service = AccountsCoreService(modelContext: context)
        let currencies = ["RUB", "USD", "EUR"]
        let kinds: [AccountKind] = [.bankAccount, .debitCard, .cash, .deposit, .debt]
        let baseDate = Date(timeIntervalSince1970: 1_600_000_000)
        var random = SeededRandom(seed: 20_260_905)
        var result: [Account] = []

        let groups: [AccountGroup] = (0..<groupCount).map { index in
            let group = AccountGroup(name: "Группа \(index)", order: index)
            context.insert(group)
            return group
        }

        for index in 0..<accountCount {
            let kind = kinds[index % kinds.count]
            // Каждый 5-й счёт — без группы: секция «Без группы» на экране владельца непустая,
            // а именно она рендерится через живой `ungroupedAccounts()`.
            let group = index % 5 == 0 ? nil : groups[index % groupCount]
            let account = try service.createAccount(
                name: "Счёт \(index)",
                kind: kind,
                currency: currencies[index % currencies.count],
                openingBalance: Decimal(10_000 + index * 137),
                group: group,
                depositMeta: kind == .deposit ? DepositMeta(
                    rate: 12,
                    capitalization: .monthly,
                    termEnd: baseDate.addingTimeInterval(86_400 * 365),
                    payoutDay: nil,
                    allowsTopUp: true,
                    allowsEarlyClose: true,
                    earlyClosePenalty: nil,
                    remindEnd: false,
                    autoRollover: false,
                    isTaxable: nil
                ) : nil,
                date: baseDate
            )

            // 30–200 событий: разброс как в реальном сторе (свежие счета vs многолетние).
            let eventCount = 30 + random.next(upTo: 171)
            for step in 0..<eventCount {
                let date = baseDate.addingTimeInterval(TimeInterval(86_400 * (step + 1)))
                // Каждое 40-е событие — редоминация: включает кумулятивный проход
                // `applyRedenomination` по всей ленте, а не только аллокацию массива.
                let event: AccountEvent = if step % 40 == 39 {
                    AccountEvent(
                        account: account,
                        date: date,
                        createdAt: date,
                        type: .redenomination,
                        redenomRate: Decimal(1) / Decimal(1000)
                    )
                } else {
                    AccountEvent(
                        account: account,
                        date: date,
                        createdAt: date,
                        type: step % 3 == 0 ? .income : .expense,
                        amount: Decimal(100 + random.next(upTo: 5_000))
                    )
                }
                context.insert(event)
            }
            result.append(account)
        }
        try context.save()
        return (result, groups)
    }
}
