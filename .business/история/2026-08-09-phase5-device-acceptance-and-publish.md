# Рефлексия сессии: Phase 5 device acceptance и публикация

**Дата:** 2026-08-09
**Автор:** Codex
**Ветка / PR:** `agent/accounts-history-source-of-truth`, GitHub PR #1

## 1. Задача

Проверить cache-first исторические курсы и графики на реальном устройстве, закрыть найденные
регрессии, актуализировать план и опубликовать весь накопленный Accounts History worktree.

## 2. Как решалась

- Сопоставлены device OSLog и четыре пользовательских скриншота.
- Подтверждено исчезновение прежних manifest/revision/RUB-fetch ошибок и появление 1W-графика.
- Исправлена миграция grouped legacy accounts: prerequisite-группа сохраняется до вызова
  converter, требующего чистый `ModelContext`.
- Повторно прогнаны focused historical и migration XCTest suites.
- Статус Phase 5 разделён на визуальную приёмку и ещё не выполненный operational hold.

## 3. Решена ли

- [x] Реализация и физическая визуальная проверка целевого сценария завершены.
- [ ] Полный Phase 5 exit остаётся открытым: 30 наблюдений/7 дней, offline transition и rollback drill.

## 4. Эффективно ли

- Историческая арифметика сходится между двумя независимыми UI-потребителями.
- Live-total не подгонялся под historical close: различие `110,156 RUB` сохранено как наблюдаемая
  разница basis.
- Остаточные `previous_close_ineligible` не превращены в фиктивные цены без market-calendar proof.

## 5. Было → Стало

| Область | Было | Стало |
|---|---|---|
| Device chart | Пустой/неполный | 1W график отрисован |
| RUB history | Ошибки source chain | CBR-first cache-first evidence |
| Migration tests | Grouped fixtures не мигрировали | Focused suite зелёный |
| Phase status | Device acceptance open | Device acceptance passed, operational hold open |

## 6. Идеи по улучшению

- Агенты: зафиксировать clean-context prerequisite boundary в
  `improvements/agents/2026-08-09-clean-context-prerequisites.md`.
- Процесс: визуальную приёмку всегда сверять арифметически между экранами.
- Токены/контекст: новых правил нет.
- Бизнес: новых наблюдений нет.

## 7. Артефакты и коммиты

- План и device-validation evidence обновлены.
- iOS commit: `5ae6ff8` (`feat(accounts): unify historical valuation source`).
- Backend commit: `e39e0c1` (`fix(market-data): support long historical charts`).
- Draft PR: `udzutech24/millio#1`; связанный backend draft PR: `udzutech24/millio-back#1`.

## 8. Что дальше

Накопить operational observations, выполнить offline/rollback проверки и только затем начинать
Phase 6 deletion.
