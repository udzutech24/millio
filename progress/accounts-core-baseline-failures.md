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
