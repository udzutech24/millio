# Research: Daily Snapshot Architecture
**Date:** 2026-06-21
**Task:** Переработка системы исторических снапшотов (AccountBalanceHistoryStore + DashboardBalanceHistoryStore → единый SwiftData-слой с frozen FX)

---

## Источники

- Архитектурный аудит (этот же чат, 2026-06-21) — обнаружена проблема C-1/H-1
- Оценка плана (Александр, 2026-06-21) — вскрыт конфликт трёх хранилищ
- Синтез Алексея (2026-06-21) — принцип closed day = immutable + FX-замороженность

---

## Что обнаружено

### Три параллельных хранилища снапшотов

| Хранилище | Тип | Дней | Назначение | Backup |
|-----------|-----|------|-----------|--------|
| `AccountBalanceHistoryStore` | JSON (Application Support) | 365 | По счетам | Нет |
| `DashboardBalanceHistoryStore` | UserDefaults | 35 | Общий портфель | Нет |
| Live `Card.balance` | SwiftData | текущий | Актуальный баланс | Да |

Все три дают разные ответы на вопрос «каков баланс был вчера». При restore из CloudKit JSON и UserDefaults стираются — история исчезает.

### Нет заморозки курсов

Текущая реализация хранит только `amount` в валюте счёта (предположительно). При изменении курса через API исторические точки графика пересчитываются в новой оценке. Это нарушает принцип: «вчера», показанное сегодня, отличается от «вчера», показанного завтра.

### Закрытые дни не защищены

`AccountBalanceSnapshotService.snapshotIfNeeded()` вызывается при каждом открытии дашборда. Если транзакция была удалена — следующий вызов пересчитает и перепишет «вчера». Нет флага «это уже история».

### `cleanup(keepingIDs:)` — деструктивная операция

`AccountBalanceHistoryStore.cleanup(keepingIDs:)` удаляет историю по orphan ID. Если счёт архивирован — его история могла быть удалена этой функцией. Это противоречит принципу «archive ≠ delete».

---

## Принцип решения (выведен из анализа)

```
Closed day snapshot = frozen accounting record

- accountBalance: хранится в исходной валюте счёта
- fxRateToBase: курс на дату закрытия дня, зафиксирован навсегда
- balanceInBaseCurrency: = accountBalance × fxRateToBase, не пересчитывается
- isClosed: true → неизменяем для любых действий пользователя

Исключение: pendingFx (курс недоступен при закрытии) — можно дозаполнить
            позже, но только если isClosed не был выставлен с валидным курсом.
```

**DailySnapshotClosingService** — единая точка закрытия дней:
- При открытии приложения находит последний `isClosed = true` snapshot
- Закрывает все дни от последнего+1 до вчера (включительно)
- Для каждого дня: тянет FX, агрегирует балансы, пишет snapshot
- При недоступности FX: `fxStatus = .pendingFx`, заполняет позже при восстановлении связи
- `closed` snapshot никогда не перезаписывается обычной логикой

---

## Конфликт с account-ledger-mutation-service.md

Phase 4 того плана (`AccountBalanceHistoryStore.invalidate(from:)`) конфликтует:
- он предлагает инвалидировать закрытые дни при backdated edit
- новый контракт запрещает это — closed day immutable
- **Phase 4 superseded** новым планом
- Phases 1–3, 5 того плана остаются валидными и должны идти ПОСЛЕ snapshot-архитектуры

---

## Выводы

Выбрать: единый `DailySnapshotClosingService` + `AccountDailySnapshot` + `PortfolioDailySnapshot` в SwiftData с FX-замороженностью.

**Порядок:** snapshot-архитектура → потом atомарность транзакций (account-ledger-mutation-service Phase 1–3).
