# Research: Finance Account Lifecycle And History

**Date:** 2026-05-30
**Stage:** 1 / Deep Research (read-only)
**Related:** [`plans/2026-05-28__finance-chart-history.md`](../../plans/2026-05-28__finance-chart-history.md)

## Задача исследования

Проверить два пользовательских дефекта: новые карты визуально не добавляются,
а архивированные счета пропадают из истории финансового графика.

## Findings from codebase

### Новая карта не появляется после добавления

`FinanceAccountService.addAccountToGroup()` сохраняет `FinanceAccount` link,
затем вызывает `onLoadGroups()`, но не вызывает `onLoadAccounts()`.

Нижний список фильтрует links через `FinanceGroupService.accountInfoResolver`,
который читает `FinanceViewModel.cardByID`. После создания карты этот кэш ещё
старый, поэтому новый link существует в SwiftData, но скрывается из UI.

### Архивный счёт пропадает из истории

Есть два независимых пути поломки:

1. Current hotfix перевёл `updateChartDataAsync()` на visible accounts. Это
   корректно для текущего header, но неверно для временного ряда: архивный счёт
   должен участвовать в точках до `archivedAt`.
2. `FinanceGroupService.deleteGroup()` архивирует underlying-счета и физически
   удаляет `FinanceAccount` links. После этого historical replay теряет связь.

### Существующее покрытие

- Есть тест сохранения link при удалении отдельного счёта.
- Есть тест historical API для архивного link.
- Есть тест удаления группы со старым неверным ожиданием `links.isEmpty`.
- Нет теста: новая карта видна сразу после `.addAccountToGroup`.
- Нет сквозного теста: chart history сохраняет архивный счёт до `archivedAt`,
  но current header совпадает с visible breakdown после архивации.

## Alternatives

### Вариант A: Обновлять UI вручную в каждом editor
- **Плюсы:** локальная правка.
- **Минусы:** дублирование, легко пропустить новый create-flow.

### Вариант B: Починить lifecycle callbacks в сервисах
- **Плюсы:** единый контракт, KISS, покрывает все create-flow.
- **Минусы:** нужны регрессионные тесты на порядок reload.

### Вариант C: Сразу внедрить snapshot architecture
- **Плюсы:** стратегически правильная история.
- **Минусы:** слишком большой blast radius для hotfix.

## Recommendation

**Выбран:** Вариант B.

1. После add reload accounts cache, затем groups.
2. Для chart series использовать historical scope, для current header и
   breakdown использовать visible scope.
3. При удалении группы сохранять links и отвязывать их от удаляемой группы;
   cleanup может перенести их в системную `Без группы`, скрытую для архивов.
