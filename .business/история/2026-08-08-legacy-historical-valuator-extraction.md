# Рефлексия сессии: Legacy historical valuator extraction

**Дата:** 2026-08-08
**Автор:** Codex subagent
**Ветка / PR:** shared worktree, без коммита

## 1. Задача

Выделить production `LegacyHistoricalValuator` из `FinanceDynamicsViewModel`, подключить
его как structured external coverage, а Cashflow/dashboard перевести на прямой
`HistoricalPortfolioSeriesProducer` без временных view model.

## 2. Как решалась

- Перенесены replay Card/Credit/Investment, transaction indexing, baseline и conversion caches.
- Compatibility balance сохранил старую числовую семантику; structured contributions
  используют unified resolver и fail closed при недоказанном FX.
- Для verified migration mapping разделены predecessor/successor по strict day boundary:
  до boundary вытесняется core successor, на/после — legacy predecessor non-participating.
- Dynamics, Cashflow и dashboard producer получили external coverage; временные
  `FinanceDynamicsViewModel` из Cashflow/dashboard убраны.
- Добавлены parity, structured coverage, missing-FX и migration-boundary тесты.
- Research/spec/plan: `thoughts/research/2026-08-07-accounts-history-source-of-truth-audit.md`,
  `specs/2026-08-07-accounts-history-source-of-truth.md`,
  `plans/2026-08-08__accounts-history-source-of-truth.md`.

## 3. Решена ли

- [x] Частично: реализация STATIC READY; runtime gate/xcodebuild оставлены родительской
  задаче по явному ограничению.

## 4. Эффективно ли

- Drive-by правок нет; изменены только границы historical valuation и их тесты.
- Проще было бы перенести старый bare total, но это нарушило бы fail-closed contract.
- Gates: `swiftc -frontend -parse`, `git diff --check`, repository search прошли; build/tests не
  запускались по условию.
- Acceptance criteria подзадачи покрыты статически, runtime ещё не доказан.

## 5. Было → Стало

| Область | Было | Стало |
|---|---|---|
| Legacy replay | Скрыт в UI view model | Standalone production service |
| Structured legacy | Requested IDs всегда incomplete | Explicit contributions с unified FX policy |
| Migration boundary | Numeric cutoff без logical-count contract | Per-date predecessor/successor exclusion |
| Cashflow/dashboard | Временный Dynamics VM | Прямой series producer |

## 6. Идеи по улучшению

- Агенты: своевременный review выявил опасный native-as-display fallback и
  duplicate logical counts; отдельная improvement-запись не нужна.
- Токены/контекст: старый replay большой; точечные `rg`/`sed` дали избежать
  чтения всего UI. Отдельная запись не нужна.
- Процесс: external coverage изначально не умел выразить non-participation/replacement;
  seam был усилен до handoff. Отдельная запись не нужна.
- Бизнес: 0 наблюдений.

## 7. Артефакты и коммиты

- Коммиты: нет.
- Обновлённый `.business`: эта рефлексия.
- План остаётся `in_progress`; его финальный статус обновляет родительская задача.

## 8. Что для следующей сессии

Родительская задача должна запустить shared `xcodebuild` gate и проверить runtime exactly-once.
