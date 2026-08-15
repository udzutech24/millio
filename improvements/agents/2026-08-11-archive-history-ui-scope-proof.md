# Не заявлять об UI-истории по тестам нижнего уровня

**Date:** 2026-08-11
**Category:** agents
**Status:** DONE
**Priority:** HIGH
**Author:** Codex

## Что произошло

Агент подтвердил, что архивные core-счета остаются в графике, опираясь на `AccountsTotalsService`-тесты. Физический UI доказал обратное: `FinanceDynamicsViewModel` отбрасывал архивные счета до вызова движка.

## Почему это проблема

Пользователь получил ложную уверенность в готовности. Нижний инвариант не доказывает, что UI-consumer передаёт полный scope.

## Корень

Не было end-to-end VM-теста для архивного счёта нового ядра. Существовали отдельно lower-level core-тест и VM-тест для legacy-архива.

## Предложение

- [x] Закрыть пробел regression-тестом `coreArchivedAccountRemainsInHistoricalChartPoints`.
- [x] Для будущих UI-утверждений требовать тест consumer-слоя с конкретным типом данных, а не инференс из service-теста.

## Как проверим что внедрение сработало

Тест создаёт два core-счёта, архивирует один внутри месячного периода и проверяет оба конца реальной `FinanceDynamicsViewModel.state.chartData`.

## Ссылки

- Сессия: `../.business/история/2026-08-11-archived-core-dynamics-history.md`
- План: `plans/2026-08-08__accounts-history-source-of-truth.md`
