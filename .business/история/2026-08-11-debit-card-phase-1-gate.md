# Рефлексия: debit-card vertical gate

**Дата:** 2026-08-11
**Автор:** Codex
**Ветка / PR:** без commit/PR

## 1. Задача

Последовательно реализовать Phase 1–9 продуктовой вертикали debit card, не переходя дальше при неполном gate.

## 2. Как решалась

Добавлены pure debit contract, Decimal currency policy, atomic coordinator, Cashflow routing, typed detail presentation, localization и compatibility proof. `CardCatalog.fetchAll` сделан чистым. Широкий Cashflow gate остановил работу на Phase 4.

## 3. Решена ли

- [x] Phase 1, 1Q, 2 и 3 закрыты исполнимым evidence.
- [ ] Phase 4: focused debit suites green, но broader Cashflow regression gate red (83/89).
- [ ] Phase 5–9 не засчитаны из-за строгого порядка.

## 4. Эффективно ли

Частично. Критический debit-path покрыт и зелён (20/20), но UI/compatibility работа была начата до полного Phase 4 gate. Она не засчитана. Продолжение остановлено на воспроизводимом красном gate.

## 5. Было → Стало

| Область | Было | Стало |
|---|---|---|
| `CardCatalog.fetchAll` | read удалял duplicate rows | pure deterministic read model |
| Debit writes | split bridge/save, generic writers | coordinator-owned atomic graph, stable operation ID |
| Phase status | Phase 1 pending | Phase 1–3 complete; Phase 4 blocked |

## 6. Evidence

- Focused: 20/20, `Test-millio-2026.08.11_20-12-16-+0300.xcresult`.
- Broader Cashflow: 83/89, six failed tests, `Test-millio-2026.08.11_20-13-29-+0300.xcresult`.
- `git diff --check`: passed.

## 7. Артефакты и коммиты

Коммитов нет. Plan/status: `phase_4_blocked_regression_gate`. Schema не менялась; legacy Card не удалялся.

## 8. Что дальше

Локализовать общую причину падений recurring generation / historical snapshot в `CashflowViewModelTests`, не меняя контракты тестов. После 89/89 повторить Phase 4 audit; только затем возобновить Phase 5.
