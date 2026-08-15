# Рефлексия сессии: Historical chart source audit

**Дата:** 2026-08-08
**Автор:** Codex
**Ветка / PR:** не создавались

## 1. Задача

Проверить, что источник исторических данных для графиков единый, и усилить
итоговый implementation plan.

## 2. Как решалась

- Проверены line modes, header/card, breakdown, currency distribution и Cashflow assets snapshot.
- Доказано, что текущий producer един только для unscoped aggregated line.
- В plan добавлен `HistoricalPortfolioSeriesQuery/Result` и обязательный lineage всех
  исторических chart projections от одного result bundle.

## 3. Решена ли

- [x] Полностью для plan-stage. Production code не менялся.

## 4. Эффективно ли

- Drive-by изменений нет.
- Новая abstraction обслуживает конкретную дыру: scope и point identity раньше терялись
  между независимыми ViewModel-calculations.
- `status.json` parse и `git diff --check` прошли; tests/build не нужны без изменения кода.

## 5. Было → Стало

| Область | Было | Стало |
|---|---|---|
| Dynamics source | SSOT только для unscoped aggregate | Один scoped series bundle для всех modes/projections |
| Breakdown/distribution | Независимые replay/FX paths | Проекции point contribution manifest |
| Cashflow snapshot | Temporary Dynamics ViewModel | Прямой вызов series producer |

## 6. Идеи по улучшению

- Агенты: 0 наблюдений.
- Токены/контекст: широкий `rg` дал шум; повторная проверка была сужена до
  конкретных producers/consumers; отдельный improvement не нужен.
- Процесс: название «single source» должно проверяться по всем presentation modes, а не только
  по happy-path aggregate; закреплено в exit gate plan.
- Бизнес: 0 наблюдений.

## 7. Артефакты и коммиты

- Коммиты: не создавались.
- Обновлены plan, status и эта рефлексия.

## 8. Что для следующей сессии

В Phase 0 сначала расширить AC-B5 в spec, затем зафиксировать red characterization всех
текущих chart data paths. Production code в Phase 0 не менять.
