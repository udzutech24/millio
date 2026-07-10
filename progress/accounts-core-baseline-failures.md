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

## Дополнение по итогам Фазы 4 плана 6b (2026-07-10)

**Новый flaky «GroupsMigratorTests.duplicateLegacyGroupNamesAreLoggedNotSilentlyDropped
order-dependence»** (НЕ регрессия Фазы 4; файл Ф4-диффом не тронут). Тест Фазы 1.5
про дубли имён легаси-групп: при двух `FinanceGroup` с одинаковым `name` только
ПЕРВАЯ переносит поля на `AccountGroup` (best-effort, «Дефект 2» Ф1.5). «Первая»
зависит от порядка `FetchDescriptor<FinanceGroup>` (SwiftData не гарантирует порядок
без явного `sortBy`), поэтому ассерт `core.isFavorite == true` (`GroupsMigratorTests.swift:169`)
недетерминирован. Доказано прямым повтором изолированного сьюта на одном коммите
(feature/legacy-accounts-purge): **run 1 — зелёный, run 2 — красный**, без изменений кода.
Системное лечение (кандидат для Дениса, вне скоупа Ф4): либо пин порядка (`sortBy`
в `GroupsMigrator`), либо сделать ассерт порядко-независимым (проверять, что ХОТЬ ОДНА
из дублей перенесла поля).

Гейт Фазы 4 (AC1) подтверждён чисто через `xcrun xcresulttool`: полный `millioTests` —
1709 passed / 26 failed = 12 задокументированных baseline (часть baseline-тестов в этом
прогоне прошла — они time-sensitive) + 6 flaky-класса LanguageManager + 5 flaky-класса
rate-cache + 2 `FinanceDynamicsCoreContributionTests` (Ф2b; зелёные в изолированном
прогоне — параллельная интерференция) + 1 GroupsMigrator order-flaky выше. **Ноль падений,
вызванных диффом Фазы 4** (снос дохлого UI-кода, логика не тронута).

## UPD 2026-07-10 (вечер): после мержа develop (c7ee0e1, Ф3 unified add-flow)

Net-new красный: `CashflowViewModelTests.testPlannedExpenseAutoAppliesOnDueDate`
(:2415, `card.balance` = 1000 вместо 750) — кластер легаси `Card.balance`
scheduled/auto-apply, в котором на pre-merge ветке (488763a) УЖЕ падало 5 тестов
(включая соседний :2290). Причина — незавершённый перевод scheduled-семантики на
single-world 6b, не сам мерж. Чинить кластером (все 6 вместе) отдельной 6b-задачей.
Итого baseline CashflowViewModelTests после мержа: 6 failed.
