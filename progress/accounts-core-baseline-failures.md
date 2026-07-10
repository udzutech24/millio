# Baseline: известные падающие тесты на develop-базе (2026-07-04, iPhone 17 Pro)

Зафиксировано ДО старта Фазы 0 ветки feature/accounts-core. Эти падения унаследованы
от develop и НЕ являются регрессиями rebuild'а. Гейт каждой фазы: «падают только эти или меньше».

1. ProfileMenuStructureTests/testSettingsSectionContainsOnlySettings
2. FinanceAccountArchivePolicyTests/exactThresholdTriggerWarning
3. ProfileLocalizationTests/testProfileNestedFlowLocalizationInSimplifiedChinese
4. DataIntegrityCleanerMigrationTests/idempotency
5. DataIntegrityCleanerMigrationTests/archivesZeroQuantityPositions
6. NotificationManagerTests/testScheduleCashflowRemindersForPlannedAndRecurring
7. NotificationManagerTests/testScheduleCashflowRemindersUseResolvedAppLanguage
8. FinanceDynamicsViewModelTests/testGroupBreakdownHidesArchivedOnlyUngroupedByDefault
9. CashflowViewModelTests/testFutureTransactionMutationsPublishTransactionsUpdatedWithoutCardsUpdated
10. FinanceLifecycleIntegrationTests/deletingMarketBuyRevertsSettlementAndPositionTogether
11. CashflowViewModelTests/testMonthlyRecurringGeneratesMissingTransactions
12. CashflowViewModelTests/testMonthlyRecurringClampsDayToMonthEnd
13. CashflowViewModelTests/testWeeklyRecurringGeneratesMissingDays
14. CashflowViewModelTests/testQuarterlyRecurringGeneratesQuarterlyTransactions
15. CashflowViewModelTests/testRecurringTemplateExpenseDoesNotAffectBalanceImmediately
16. CashflowViewModelTests/testPlannedExpenseAutoAppliesOnDueDate

Характер: recurring/scheduled (time-sensitive), нотификации, l10n zh-Hans, integrity-cleaner,
archive-policy. Большинство, вероятно, чинятся на feature/dynamics-chart-fix (148/148 там).
Отдельная задача — после rebuild'а.

Также починено для компиляции тест-таргета: DataIntegrityCleanerMigrationTests — добавлен
обязательный аргумент scopeIdentifier: "test" (сигнатура изменилась в 729eec5, тесты в develop не обновили).

## Дополнение по итогам фаз 0–6a (2026-07-04, вечер)

**Flaky-класс «LanguageManager.shared race»** (НЕ регрессии; каждый проверен зелёным
в изолированном прогоне): под параллельной нагрузкой полного millioTests любой тест,
читающий `L()` без пина языка, может словить чужой язык. Замеченные жертвы:
- ConverterViewModelTests/testShareAndLastUpdatedUseSelectedAppLanguage (мутирует язык без лока, строки ~467-480)
- CashflowCategoryHelpContentTests/*
- CashflowTransactionEditorViewLayoutTests/*
- FinanceOverviewLedgerStyleTests/* (починен пином языка, b41d02a)
- FinanceDynamicsViewModelTests/testDeleteGroupPreservesArchivedLinkForHistoricalCalculation
Системное лечение (отдельная задача): все прямые мутации LanguageManager.shared в
тестах → через AppLanguageTestSupport.withLanguage.

**Финальный прогон 2026-07-04 (после 6a):** 1576 passed / 20 failed, из них 14 —
baseline выше (2 baseline-теста прошли), 6 — flaky-класс выше. Отдельно разобран CashflowViewModelTests/
testIncomeBudgetSummaryUsesIncomePlanConfiguration (порядок categorySnapshots):
бисект доказал, что это НЕ регрессия rebuild'а — падение воспроизводится на
пре-Phase-0 базе; причина — сортировка tie-break через localizedCaseInsensitiveCompare
зависела от системной локали симулятора (zh-Hans → пиньинь-коллация). Починено
пином локали en_US_POSIX (коммит 6cbe610).

## Дополнение по итогам Фазы 3 плана 6b (2026-07-10)

**Новый flaky-класс «UserDefaults.standard rate cache leak»** (НЕ регрессия Фазы 3;
проверено: воспроизводится в полной изоляции класса, на файлах, которые Фаза 3 не трогала).
`CurrencyRateService.init` синхронно прогревается из `UserDefaults.standard` (диск,
переживает перезапуск процесса теста на одном и том же симуляторе) — `MockRateRepository`
теста этот прогрев не перехватывает, поэтому если на конкретном симуляторе в
`UserDefaults.standard` уже лежат реальные курсы с прошлого запуска приложения/тестов
(ключи `rate_repo_rates_<source>` / `rate_repo_fetched_at_<source>`, `CurrencyRateService.swift:85,276-277`),
тест получает СТАРЫЕ диск-данные вместо мокнутых. Замеченные жертвы (2026-07-10, одна и та же
физическая симуляция iPhone 17 Pro Clone, воспроизведено в изолированном прогоне только этого класса):
- CurrencyRateServiceTests/testCrossRateViaUSD
- CurrencyRateServiceTests/testConvertAmount
- CurrencyRateServiceTests/testFreshLaunchNetworkDownUsesStaleCached
- CurrencyRateServiceTests/testUSDRateAlwaysOne
- FinanceViewModelTests/testCalculateTotalAmountDoesNotForceRefreshRates

Системное лечение (не в скоупе Фазы 3, кандидат для Дениса): тесты `CurrencyRateService`
должны инжектировать изолированный `UserDefaults(suiteName:)` вместо `.standard`, либо
очищать `rate_repo_rates_*`/`rate_repo_fetched_at_*` ключи в setup. Гейт Фазы 3 (AC2)
подтверждён чисто: 22 failed в full-run = 16 задокументированных baseline + 1 flaky-класс
LanguageManager (`FinanceDynamicsViewModelTests.testDeleteGroupPreservesArchivedLinkForHistoricalCalculation`) +
5 нового flaky-класса выше — ноль падений, вызванных диффом Фазы 3.
