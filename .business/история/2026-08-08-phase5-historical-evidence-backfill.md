# Рефлексия сессии: Phase 5 historical evidence backfill

**Дата:** 2026-08-08
**Автор:** Codex
**Ветка / PR:** local dirty worktree, без commit/PR

## 1. Задача

Восстановить графики Dynamics на legacy/core портфеле с cache-first историческими курсами,
ЦБ как основным источником RUB-пар, и довести решение до production-качества.

## 2. Как решалась

- Разобран physical-device log; доказаны пробелы FX/market evidence.
- FX prefetch переведён на точные даты producer skeleton.
- Добавлен append-only historical market close prefetch через существующий market client.
- Неполные results больше не передаются repository как publishable close.
- Починен фактически недостижимый Frankfurter fallback для RUB allowlist.
- Research: `thoughts/research/2026-08-08-phase5-incomplete-series-device-log.md`
- Spec: `specs/2026-08-07-accounts-history-source-of-truth.md`
- Plan: `plans/2026-08-08__accounts-history-source-of-truth.md`

## 3. Решена ли

- [x] Частично: iOS/backend code, unit gates, signed device build и установка готовы.
- [ ] Нужны deployment backend limit, Xcode OSLog на физическом портфеле и offline repeat.

## 4. Эффективно ли

- Drive-by правок нет; использованы существующие cache models и market client.
- Проще без ложных сумм нельзя: current-price/partial-total fallback отвергнут.
- Build-for-testing зелёный; профильные suites зелёные. Backend Jest не запущен: dependencies не установлены.
- Три legacy migration tests в расширенном gate падают до Dynamics (`migrateAll() == 0`) и не связаны с этой дельтой.

## 5. Было → Стало

| Область | Было | Стало |
|---|---|---|
| FX | Другая 90-point сетка | Точные producer dates |
| Market | Только today quote | Cache-first daily close backfill |
| Close | Incomplete publish маскировал reason | Root cause сохраняется |
| RUB fallback | Запрещён allowlist | Frankfurter fallback достижим |

## 6. Идеи по улучшению

- Агенты: семантика diagnostic count зафиксирована в `improvements/agents/2026-08-08-incomplete-count-semantics.md`.
- Токены/контекст: 0 новых наблюдений.
- Процесс: backend/iOS contract надо включать в один acceptance gate.
- Бизнес: 0 новых наблюдений.

## 7. Артефакты и коммиты

- Коммиты: не создавались.
- План актуализирован; Phase 5 — В РАБОТЕ.

## 8. Что для следующей сессии

Развернуть backend limit, запустить Dynamics 1D/All online и offline, снять Xcode OSLog
`Incomplete series`, затем выполнить rollback drill.
