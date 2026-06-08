Status: OPEN

# FinanceLifecycleIntegrationTests содержит order-dependent падение

## Наблюдение

Во время Phase 4 `CashflowViewModelTests` прошёл зелёным, но дополнительный полный прогон:

```bash
xcodebuild test -scheme millio \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath /tmp/millio-phase4-derived \
  -only-testing:millioTests/FinanceLifecycleIntegrationTests
```

стабильно падал на `deletingMarketBuyRevertsSettlementAndPositionTogether()` с таймаутом `FinanceLifecycleHarness.waitUntil`.

Тот же тест, запущенный изолированно, проходил:

```bash
xcodebuild test -scheme millio \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath /tmp/millio-phase4-derived \
  -only-testing:millioTests/FinanceLifecycleIntegrationTests/deletingMarketBuyRevertsSettlementAndPositionTogether
```

Запуск полного suite с `-parallel-testing-enabled NO` падал так же, значит проблема не только в Xcode parallel clones.

## Риск

Suite выглядит как интеграционный gate, но сейчас он смешивает реальную регрессию с order-dependent состоянием. Это опасно: зелёный изолированный тест может усыпить, а красный полный suite может начать игнорироваться как “просто flaky”.

## Предложение

- Вынести отдельную задачу Test Fix Mode для `FinanceLifecycleIntegrationTests`.
- Начать с минимальной диагностики `deletingMarketBuyRevertsSettlementAndPositionTogether()` после предыдущих 7 тестов: какие linked transactions остаются в store, стартует ли delete task, есть ли `deleteBalanceUpdateErrorMessage`.
- Не увеличивать timeout как первый фикс. Сначала доказать источник: shared `ModelContainer`, EventBus subscribers, фоновые tasks VM, stale `operationGroupID`, или порядок очистки harness.
- Добавить правило в plan gates: если Swift Testing suite падает только в полном прогоне, фиксировать both commands и не считать isolated green достаточным закрытием интеграционного риска.

## Ожидаемый эффект

Интеграционный cashflow/finance gate снова будет полезным сигналом, а не шумом, который приходится объяснять в каждой фазе.

## Ссылки

- Plan: `plans/2026-06-07__finance-balance-contract.md`
- Session history: `../.business/история/2026-06-08-finance-balance-contract-phase-4.md`
