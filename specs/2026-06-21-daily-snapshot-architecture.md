# Spec: Daily Snapshot Architecture
**Date:** 2026-06-21
**Author:** Алексей (требования) + архитектурный аудит
**Research:** millio/thoughts/research/2026-06-21-daily-snapshot-architecture.md

---

## Problem

Millio имеет три параллельных хранилища снапшотов:
- `AccountBalanceHistoryStore` — JSON в Application Support (365 дней, по счетам)
- `DashboardBalanceHistoryStore` — UserDefaults (35 дней, общий портфель)
- Live `Card.balance` в SwiftData

Все три вне backup registry. При restore из CloudKit история графиков исчезает.

Дополнительно:
- Снапшоты не хранят FX-курс на дату. При изменении курса исторические точки пересчитываются в новой оценке — «вчера» выглядит иначе завтра.
- Закрытые дни не защищены: удаление транзакции или архивация счёта может переписать прошлое.
- `AccountBalanceHistoryStore.cleanup(keepingIDs:)` удаляет историю архивированных счетов.

---

## Goal

Единый immutable-слой исторических снапшотов в SwiftData:
- Closed day = frozen accounting record: баланс + FX-курс + пересчёт в базовую валюту, зафиксированные навсегда
- Закрытый день не меняется при любых действиях пользователя (delete tx, archive account, change FX rate)
- История переживает backup/restore и переустановку приложения
- Пропущенные дни (приложение не открывалось) добираются при следующем запуске

---

## Scope

### In Scope

- SwiftData-модели `AccountDailySnapshot` и `PortfolioDailySnapshot` с полями FX
- `DailySnapshotClosingService`: закрывает прошедшие дни при открытии приложения
- Migration: однократный import из JSON + UserDefaults → SwiftData при первом запуске после обновления
- Новый chart read path: `< today` из SwiftData, `today` из live `Card.balance`
- Удаление/защита деструктивных механизмов (`cleanup(keepingIDs:)`)
- Регистрация моделей в backup schema

### Out of Scope

- Атомарность транзакций / rollback (→ `account-ledger-mutation-service.md` Phases 1–3, реализуется после)
- Fail-fast enum `CashflowTransactionType.unknown` (→ там же Phase 3)
- UI для ручного rebuild исторических снапшотов (admin/debug фича, отдельно)
- Multi-currency portfolio chart (следующий этап)
- Изменение UX экрана истории

---

## Data Models

```swift
@Model
final class AccountDailySnapshot {
    var accountID: String        // Card.id или аналог
    var dateKey: String          // "2026-06-20" (ISO 8601, device timezone)
    var accountBalance: Double   // баланс в валюте счёта
    var accountCurrency: String  // "RUB", "USD", ...
    var baseCurrency: String     // базовая валюта портфеля пользователя
    var fxRateToBase: Double     // 1 accountCurrency = fxRateToBase baseCurrency
    var balanceInBaseCurrency: Double  // = accountBalance * fxRateToBase
    var rateProvider: String     // "cbr", "ecb", "manual", "fallback"
    var rateTimestamp: Date      // когда зафиксирован курс
    var snapshotState: String    // "open" | "pendingFx" | "closed" | "fallbackClosed"
    var timezoneIdentifier: String  // "Europe/Moscow" — device timezone при закрытии
    var closedAt: Date?          // момент финального закрытия дня
    var createdAt: Date
    var updatedAt: Date
}

@Model
final class PortfolioDailySnapshot {
    var dateKey: String
    var totalBalanceInBaseCurrency: Double
    var baseCurrency: String
    var snapshotState: String    // "open" | "pendingFx" | "closed" | "fallbackClosed"
    var timezoneIdentifier: String
    var closedAt: Date?
    var createdAt: Date
}
```

**SnapshotState contract:**
| State | Смысл | Можно изменить? |
|-------|-------|----------------|
| `open` | Текущий день (= today) | Да |
| `pendingFx` | День закрыт, FX ещё не получен | Только FX-поля |
| `closed` | Полностью закрыт, FX зафиксирован | Нет |
| `fallbackClosed` | Закрыт с fallback-курсом (последний известный) | Нет |

Невозможное состояние `isClosed=true + fxStatus=pendingFx` исключено самим дизайном: замена двух полей одним `snapshotState`.

**Idempotency key:**
- Account: `(accountID, dateKey, baseCurrency)` — уникален, сервис выполняет fetch-before-insert
- Portfolio: `(dateKey, baseCurrency)` — аналогично

**Timezone contract:** `dateKey` фиксируется в device timezone (`Calendar.current.identifier`) при закрытии дня. Timezone сохраняется в `timezoneIdentifier`. При смене timezone пользователем старые `dateKey` не пересчитываются — принятый компромисс.

---

## Acceptance Criteria

### FX-замороженность

- [ ] `fxRateToBase` и `balanceInBaseCurrency` в снапшоте с `snapshotState = "closed"` или `"fallbackClosed"` не изменяются при изменении текущего курса
- [ ] График за вчера показывает одинаковое значение независимо от текущего курса
- [ ] Тест: создать snapshot с курсом 90, изменить курс в приложении на 100, график за закрытый день остаётся в 90

### Immutability

- [ ] Удаление транзакции не изменяет snapshots с `snapshotState = "closed"` или `"fallbackClosed"`
- [ ] Архивация счёта не изменяет его закрытые snapshots
- [ ] `cleanup(keepingIDs:)` запрещён для `AccountDailySnapshot` в любой ситуации — не только после миграции. Архивный счёт остаётся участником исторических данных навсегда
- [ ] Тест: создать snapshot, удалить транзакцию за тот же день → snapshot неизменён

### Catch-up при открытии приложения

- [ ] Если вчера нет закрытого snapshot → создаётся при открытии
- [ ] Если приложение не открывалось 3 дня → все 3 дня закрываются последовательно
- [ ] При недоступности FX → snapshot сохраняется с `snapshotState = "pendingFx"` (баланс зафиксирован, FX ещё не известен)
- [ ] При следующем запуске с доступным FX → `pendingFx` снапшоты дозаполняются FX-полями и переводятся в `"closed"`
- [ ] `pendingFx` защищает `accountBalance` от изменения: можно обновить только `fxRateToBase`, `balanceInBaseCurrency`, `snapshotState`, `rateProvider`, `rateTimestamp`, `closedAt`
- [ ] Тест: simulate 3 missed days → 3 snapshots создаются, каждый с корректным dateKey

### Миграция

- [ ] Существующая JSON-история (`account_balance_history_v1.json`) переносится в SwiftData
- [ ] Существующая UserDefaults-история (`dashboard.balance.history.v1`) переносится в PortfolioDailySnapshot
- [ ] Импортированные дни `< today` помечаются `snapshotState = "fallbackClosed"` (FX неизвестен на дату)
- [ ] После успешного `context.save()` — verify раздельно:
  - account: `inserted AccountDailySnapshot == JSON source count` (exact match, не `>=`)
  - portfolio: `inserted PortfolioDailySnapshot == UserDefaults source count` (exact match)
  - если любой не совпал → save не вызывается, флаг не выставляется, JSON не переименовывается
- [ ] JSON **не удаляется**, а переименовывается в `account_balance_history_v1.migrated` — удалить только при explicit cleanup в следующей версии
- [ ] UserDefaults-ключ очищается (пространство, а не история — история уже в SwiftData)
- [ ] Если save() упал — JSON остаётся нетронутым, флаг миграции не выставляется
- [ ] Если миграция уже выполнена (флаг выставлен) → skip без изменений
- [ ] Тест: запустить мигратор дважды → только один набор снапшотов

### Chart read path

- [ ] Дни `< today` → из `AccountDailySnapshot` / `PortfolioDailySnapshot` (SwiftData query)
- [ ] `today` → из live `Card.balance` (текущее состояние)
- [ ] Дни без данных (gap) → точка не рисуется, не интерполируется
- [ ] Тест: удалить snapshot за конкретную дату → график показывает gap на этот день

### Backup / Restore

- [ ] `AccountDailySnapshot` и `PortfolioDailySnapshot` включены в backup schema
- [ ] После restore из CloudKit история графиков доступна
- [ ] Тест: backup → удалить приложение → restore → история графика совпадает с оригинальной

---

## Constraints

- SwiftData: нет row-level protection, `snapshotState = "closed"` защищается только на уровне сервиса — guard обязателен в каждом write-методе
- FX: источник курсов — существующий FX-провайдер приложения (определить при реализации Phase 3); исторические FX API не используются
- Timezone: `dateKey` фиксируется в `Calendar.current` и хранится `timezoneIdentifier` — при смене timezone старые dateKey не пересчитываются
- Idempotency: перед insert сервис обязан делать fetch `(accountID, dateKey, baseCurrency)` — SwiftData не предоставляет DB-unique гарантии
- Source of truth для Balance: `end-of-day balance = предыдущий closed snapshot + ledger delta за этот день`; `Card.balance` как источник запрещён (может быть изменён мутациями за today)
- Обратная совместимость: JSON переименовывается (`*.migrated`), не удаляется — убрать только в следующей версии после verify
- MainActor: все SwiftData write-операции остаются на MainActor (как сейчас в проекте)
- iOS Background: фоновый запуск не гарантирован — закрытие дней происходит при app launch / dashboard open; фоновая задача — опция, не основной механизм

---

## Non-Goals

- Не вводить server-side курсы или исторические FX API (только то, что уже есть в приложении)
- Не делать UI для просмотра снапшотов вручную
- Не реализовывать точные исторические курсы для дней с `pendingFx` через внешний API (только fallback)
- Не менять модель `Card` или `FinanceGroup`
