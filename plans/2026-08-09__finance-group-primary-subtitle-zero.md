# План: ложный `≈ 0 ₽` у валютных групп

**Статус:** РЕАЛИЗОВАНО
**Режим:** S (`millio-bulletproof`)

## Доказанный дефект

На первом открытии `FinanceViewModel.init` вызывает `loadGroups()` и `loadAccounts()`. `loadGroups()`
запускает только расчёт общего баланса, а строки групп через `.task` записывают только
`state.groupTotals`. Словарь `state.groupTotalsPrimaryCurrency` остаётся без ключей до внешнего
события или refresh. `FinanceGroupRow.primaryCurrencySubtitleText` маскирует отсутствие ключа через
`?? 0`, поэтому ненулевая USD-группа отображается как `≈ 0 ₽`.

## Acceptance criteria

- После первоначальной загрузки для каждой видимой группы атомарно рассчитаны native- и primary-тоталы.
- Ненулевая USD-группа при primary currency RUB не показывает `≈ 0 ₽`, если конвертация успешна.
- Отсутствующее/неуспешное значение не выдаётся за доказанный ноль.
- Общий баланс, секционные подытоги и subtitle используют согласованный lifecycle.
- Регрессия покрыта unit/integration-тестом холодного initial load.

## Фаза 1 — минимальный root fix

- [x] Добавить integration-тест на initial load валютной группы.
- [x] Подключить первоначальную загрузку к существующему атомарному
      `refreshGroupTotalsAndAmounts()` вместо отдельного неполного row-only пути.
- [x] Убрать ложный `nil → 0` контракт subtitle (рендерить только готовое значение либо явное
      недоступное состояние — выбрать минимальный вариант по текущему UI-паттерну).
- [x] Проверить гонки generation/watermark и отсутствие двойного сетевого refresh.
- [x] Запустить минимальный набор accounts sections тестов и compile gate в чистом worktree.
- [x] Self-audit acceptance criteria и актуализация этого плана.

## Не делать

- Не чинить Firebase warning, backend region и historical-series warnings: они не связаны с дефектом.
- Не добавлять второй конвертер и не считать курс внутри SwiftUI row.
- Не переписывать totals architecture: существующий атомарный pipeline уже является нужной точкой.

## Журнал

- 2026-08-09: дефект доказан статической трассировкой lifecycle; реализация не начата из-за guard phrase.
- 2026-08-09: фаза 1 реализована. Cold-start запускает существующий атомарный totals pipeline;
  subtitle скрыт до появления primary-значения вместо `nil ?? 0`.
- 2026-08-09: `FinanceAccountsSectionsIntegrationTests` — 3/3 passed по `xcresult` в чистом временном
  worktree. Текущий пользовательский worktree не собирается из-за пяти несвязанных `Double ↔ Decimal`
  ошибок в незакоммиченном `AccountDetailSheets.swift`; чужие правки не изменялись.
