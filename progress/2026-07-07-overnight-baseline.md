# Baseline тестов перед ночным прогоном — 2026-07-07

## Метаданные

- **Дата/время запуска:** 2026-07-07, ~21:55:56 — 21:59:30 (MSK, локальное время машины)
- **Ветка:** develop
- **HEAD, на котором собран и прогнан код:** `93db864044bcd862a20df47747afbcce32a33270`
  (`docs(plans): runbook ночного прогона 2026-07-07 + рефлексии сессий`)
- **Важно:** пока шёл прогон, в этот же working tree параллельно прилетел ещё один docs-коммит
  (`72f68f4 docs(plans): план 6b Путь B — миграция и снос легаси-миров счетов`), не мой. Он docs-only
  (папка `plans/`), кода/тестов не касается, поэтому результаты baseline остаются валидными для 93db864.
  Коммит baseline-файла в этой сессии делается поверх текущего HEAD (`72f68f4`), сам чужой файл в
  коммит не включён.
- **Код не менялся.**

## Отклонение от брифа: симулятор

`iPhone 16 Pro` в установленном рантайме симуляторов отсутствует (только линейка iPhone 17 / iPhone Air /
iPad, OS 26.x). Использован ближайший доступный: **iPhone 17 Pro, OS 26.5**.

## Команда запуска

Первая попытка с `-destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest'` упала с
`xcodebuild: error: Unable to find a device matching the provided destination specifier` (см.
`/private/tmp/.../scratchpad/baseline-tests.log`). Финальный прогон:

```bash
cd "/Users/alekseya/Проекты/3.millio local/millio-dev/millio" && xcodebuild test \
  -scheme millio \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /private/tmp/xcodebuild-deriveddata-v2 \
  -resultBundlePath /private/tmp/.../scratchpad/baseline-results-v2 \
  -only-testing:millioTests
```

Только unit-таргет `millioTests` (UI-тесты `millioUITests` не гонялись — по брифу).

## Итог сборки

**BUILD/TEST: FAILED** (ожидаемо — есть преэкзистентные красные, см. ниже). Компиляция прошла без ошибок,
упали только сами тесты.

## Число тестов и время

- Источник цифр: `xcrun xcresulttool get test-results summary --path baseline-results-v2.xcresult`
- **Passed (root summary):** 1668
- **Failed:** 18
- **Итого уникальных тестов:** 1686
- (На уровне device-конфигурации xcresulttool показывает 1694 passed/18 failed — расхождение с root
  из-за параметризованных тестов: `"4 tests ran with dynamic parameters" / "30 test runs"`, ретраи
  учитываются дважды на device-уровне.)
- **Время выполнения тестов (по xcresult, start→finish):** 3 мин 13 сек (21:56:11 → 21:59:24)
- **Полное время команды (resolve packages + build + test, по mtime лог-файла):** ~3 мин 34 сек
  (21:55:56 → 21:59:30)

## Полный список упавших тестов (suite.testName)

1. `CashflowCategoryHelpContentTests.expenseHelpContainsHistoryRestoreNote()`
2. `CashflowCategoryHelpContentTests.incomeHelpContainsMainGuidance()`
3. `CashflowTransactionEditorViewLayoutTests.expenseSheetConfiguration()`
4. `CashflowTransactionEditorViewLayoutTests.incomeSheetConfiguration()`
5. `CashflowViewModelTests.testFutureTransactionMutationsPublishTransactionsUpdatedWithoutCardsUpdated()`
6. `CashflowViewModelTests.testMonthlyRecurringClampsDayToMonthEnd()`
7. `CashflowViewModelTests.testMonthlyRecurringGeneratesMissingTransactions()`
8. `CashflowViewModelTests.testQuarterlyRecurringGeneratesQuarterlyTransactions()`
9. `CashflowViewModelTests.testRecurringTemplateExpenseDoesNotAffectBalanceImmediately()`
10. `CashflowViewModelTests.testWeeklyRecurringGeneratesMissingDays()`
11. `ConverterViewModelTests.testShareAndLastUpdatedUseSelectedAppLanguage()`
12. `FinanceAccountArchivePolicyTests.exactThresholdTriggerWarning()`
13. `FinanceDynamicsViewModelTests.testGroupBreakdownHidesArchivedOnlyUngroupedByDefault()`
14. `FinanceLifecycleIntegrationTests.deletingMarketBuyRevertsSettlementAndPositionTogether()`
15. `NotificationManagerTests.testScheduleCashflowRemindersForPlannedAndRecurring()`
16. `NotificationManagerTests.testScheduleCashflowRemindersUseResolvedAppLanguage()`
17. `ProfileLocalizationTests.testProfileNestedFlowLocalizationInSimplifiedChinese()`
18. `ProfileMenuStructureTests.testSettingsSectionContainsOnlySettings()`

## Сверка с ожиданием

Ожидалось (по брифу): 4 recurring-теста в `CashflowViewModelTests` + 1 —
`FinanceLifecycleIntegrationTests.deletingMarketBuyRevertsSettlementAndPositionTogether` (итого 5).

**Совпадение: ЧАСТИЧНОЕ.** Ожидаемые 5 присутствуют:
- `CashflowViewModelTests.testMonthlyRecurringClampsDayToMonthEnd()` ✓
- `CashflowViewModelTests.testMonthlyRecurringGeneratesMissingTransactions()` ✓
- `CashflowViewModelTests.testQuarterlyRecurringGeneratesQuarterlyTransactions()` ✓
- `CashflowViewModelTests.testWeeklyRecurringGeneratesMissingDays()` ✓
- `FinanceLifecycleIntegrationTests.deletingMarketBuyRevertsSettlementAndPositionTogether()` ✓

**Расхождение: +13 незапланированных красных**, не входивших в ожидание:

1. `CashflowCategoryHelpContentTests.expenseHelpContainsHistoryRestoreNote()`
2. `CashflowCategoryHelpContentTests.incomeHelpContainsMainGuidance()`
3. `CashflowTransactionEditorViewLayoutTests.expenseSheetConfiguration()`
4. `CashflowTransactionEditorViewLayoutTests.incomeSheetConfiguration()`
5. `CashflowViewModelTests.testFutureTransactionMutationsPublishTransactionsUpdatedWithoutCardsUpdated()`
6. `CashflowViewModelTests.testRecurringTemplateExpenseDoesNotAffectBalanceImmediately()`
7. `ConverterViewModelTests.testShareAndLastUpdatedUseSelectedAppLanguage()`
8. `FinanceAccountArchivePolicyTests.exactThresholdTriggerWarning()`
9. `FinanceDynamicsViewModelTests.testGroupBreakdownHidesArchivedOnlyUngroupedByDefault()`
10. `NotificationManagerTests.testScheduleCashflowRemindersForPlannedAndRecurring()`
11. `NotificationManagerTests.testScheduleCashflowRemindersUseResolvedAppLanguage()`
12. `ProfileLocalizationTests.testProfileNestedFlowLocalizationInSimplifiedChinese()`
13. `ProfileMenuStructureTests.testSettingsSectionContainsOnlySettings()`

Некоторые из новых красных (`CashflowCategoryHelpContentTests`, `ConverterViewModelTests`,
`ProfileLocalizationTests`) по тексту ошибок похожи на **locale/язык-зависимые** сравнения (ожидание
русского текста при факте на `zh-Hans` или наоборот) — вероятно чувствительны к языку/локали
симулятора/системы, а не отражают реальную регрессию кода. Требуется отдельная диагностика (не входит
в объём этого шага — только baseline).

## Артефакты

- Полный лог: `/private/tmp/claude-501/-Users-alekseya---------3-millio-local/4cb61396-2339-4495-afbc-c5f56a96b076/scratchpad/baseline-tests-v2.log`
- Result bundle: `/private/tmp/claude-501/-Users-alekseya---------3-millio-local/4cb61396-2339-4495-afbc-c5f56a96b076/scratchpad/baseline-results-v2.xcresult`
