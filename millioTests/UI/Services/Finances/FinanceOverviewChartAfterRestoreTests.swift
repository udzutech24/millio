//
//  FinanceOverviewChartAfterRestoreTests.swift
//  millioTests
//
//  R8 — «пустой график активов/обязательств при непустом списке и тотале».
//
//  Симптом с устройства владельца (после restore бэкапа на 1673 модели): шапка «Счета» показывает
//  100 909 281 ₽, список групп заполнен, а блок графика — «Пока нет активов или обязательств».
//
//  Причина класса: на одном экране жили ТРИ источника core-счетов.
//    · список  — живое отношение `AccountGroup.accounts` (`orderedAccounts(for:)`),
//    · тотал   — живой fetch внутри `AccountsTotalsService`,
//    · график  — снапшот `FinanceViewModel.state.accounts` (`coreAccountsSnapshot(matching:)`).
//  Снапшот обновляется только по событиям (`restoreCompleted`, core-мутации). Любой пропуск
//  сигнала (или загрузка снапшота ДО того, как импорт довёз счета) оставлял график пустым
//  навсегда, пока список и тотал показывали реальные данные.
//
//  Тесты ниже фиксируют инвариант «график читает тот же источник, что список» на реальной
//  фикстуре бэкапа владельца.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct FinanceOverviewChartAfterRestoreTests {

    /// Реплика цикла `FinanceOverviewCardView.buildLedgerPresentation` по core-счетам:
    /// именно те методы ViewModel, которые зовёт View.
    private static func chartCoreItems(_ viewModel: FinanceViewModel) async -> [FinanceOverviewLedgerSourceItem] {
        var items: [FinanceOverviewLedgerSourceItem] = []
        let accounts = viewModel.state.groups.flatMap { viewModel.orderedAccounts(for: $0) }
            + viewModel.ungroupedAccounts()
        for account in accounts {
            let signed = NSDecimalNumber(decimal: await viewModel.accountsTotalsService.total(
                for: [account], on: Date(), in: viewModel.state.displayCurrency
            )).doubleValue
            guard let normalized = FinanceOverviewLedgerStyle.normalizeAmount(signed, defaultSide: .debit) else { continue }
            items.append(
                FinanceOverviewLedgerSourceItem(
                    groupID: account.group?.id.uuidString ?? "ungrouped",
                    groupName: account.group?.name ?? "ungrouped",
                    groupColorHex: nil,
                    accountID: account.id.uuidString,
                    accountName: account.name,
                    accountIcon: account.kind.fallbackIconName,
                    customIconName: nil,
                    customIconColor: nil,
                    amount: normalized.amount,
                    side: normalized.side
                )
            )
        }
        return items
    }

    // MARK: - R8: устаревший снапшот не должен опустошать график

    @Test("R8: при устаревшем state.accounts график по бэкапу владельца не пуст (источник — тот же, что у списка)")
    func testChartSurvivesStaleAccountsSnapshot() async throws {
        let environment = try Self.makeEnvironment()
        let context = environment.container.mainContext
        let rates = Self.makeRateService()

        let manager = BackupManager(
            cloudStore: Self.offlineCloudStore(),
            dataRepository: environment.repository
        )
        let receipt = try await manager.restoreFromFile(try Self.ownerBackupFixture(), passphrase: nil)
        #expect(receipt.isVerified)

        let viewModel = FinanceViewModel(modelContext: context, currencyService: rates)
        viewModel.handle(.loadGroups)

        // Моделируем ровно то состояние, что было на устройстве: группы в снапшоте есть (список
        // рисуется), а срез счетов не доехал — сигнал обновления не дошёл или снапшот снят,
        // пока импорт ещё не довёз `Account` (группы импортируются раньше счетов).
        viewModel.state.accounts = []

        let listAccounts = viewModel.state.groups.flatMap { viewModel.orderedAccounts(for: $0) }
        #expect(listAccounts.isEmpty == false, "Список групп обязан быть непустым — иначе тест не про тот баг")

        let items = await Self.chartCoreItems(viewModel)
        #expect(items.isEmpty == false, "График пуст при непустом списке — тот самый симптом R8")
        #expect(items.count <= listAccounts.count)
    }

    // MARK: - R8: инвариант «тотал > 0 ⇒ график не пуст»

    @Test("R8-инвариант: тотал шапки > 0 ⇒ график активов/обязательств не пуст")
    func testNonZeroTotalImpliesNonEmptyChart() async throws {
        let environment = try Self.makeEnvironment()
        let context = environment.container.mainContext
        let rates = Self.makeRateService()

        let manager = BackupManager(
            cloudStore: Self.offlineCloudStore(),
            dataRepository: environment.repository
        )
        _ = try await manager.restoreFromFile(try Self.ownerBackupFixture(), passphrase: nil)

        let viewModel = FinanceViewModel(modelContext: context, currencyService: rates)
        viewModel.handle(.loadGroups)
        // Снапшот намеренно устаревший — тотал и график обязаны остаться согласованными.
        viewModel.state.accounts = []

        let total = await viewModel.accountsTotalsService.totalAt(
            Date(), in: viewModel.state.displayCurrency
        )
        #expect(total > 0, "Фикстура владельца обязана давать ненулевой тотал")

        let presentation = FinanceOverviewLedgerBuilder.makePresentation(items: await Self.chartCoreItems(viewModel))
        #expect(presentation.hasData, "Тотал \(total) > 0, а график показывает пустое состояние")
    }

    // MARK: - Environment

    private struct Environment {
        let container: ModelContainer
        let repository: DataRepository
    }

    private static func makeRateService() -> MockCurrencyRateService {
        let rates = MockCurrencyRateService()
        for code in ["USD", "EUR", "CNY", "GBP", "KZT", "AED", "TRY", "HKD", "JPY", "CHF"] {
            rates.setRate(from: code, to: "RUB", rate: 90)
        }
        return rates
    }

    private static func makeEnvironment() throws -> Environment {
        CurrencyFeatureRegistration.register()
        CardFeatureRegistration.register()
        CashbackFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
        UserSubscriptionsFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()

        let container = try ModelContainer(
            for: AppSchema.create(),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return Environment(
            container: container,
            repository: DataRepository(modelContext: container.mainContext, modelContainer: container)
        )
    }

    private static func offlineCloudStore() -> MockCloudBackupStore {
        let store = MockCloudBackupStore()
        store.isAvailableResult = false
        return store
    }

    private static func ownerBackupFixture() throws -> Data {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("millioTests/Fixtures/owner-backup-1673-models.milliobackup")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try Data(contentsOf: candidate)
            }
            directory.deleteLastPathComponent()
        }
        throw AppError.backupCorrupted
    }
}
