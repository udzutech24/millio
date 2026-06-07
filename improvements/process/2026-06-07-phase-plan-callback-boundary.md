Status: OPEN

# Проверять callback boundary до фикса по плану

**Дата:** 2026-06-07
**Категория:** process

## Наблюдение

Phase 1 плана `finance-balance-contract` говорила «добавить `onLoadAccounts()` в `FinanceAccountService.addAccountToGroup()`», но у `FinanceAccountService` не было dependency callback `onLoadAccounts`. На первом compile-прогоне это дало ошибку `Cannot find 'onLoadAccounts' in scope`.

## Диагноз

План описал правильное намерение, но не проверил границу сервиса: метод `loadAccounts()` живёт в `FinanceViewModel`, а сервис получает только переданные callbacks. Поэтому реализация требовала не одной строки, а явного добавления dependency в init и прокидывания из VM.

## Правило на будущее

Если план предлагает «добавить вызов callback/dependency» внутри выделенного сервиса, перед стартом фазы обязательно проверить:

- есть ли callback в сервисе;
- кто его прокидывает;
- есть ли тест на порядок callbacks, если порядок важен для stale cache/UI.

## Ожидаемый эффект

Меньше compile-level сюрпризов в маленьких фазах и более точные фазовые планы.
