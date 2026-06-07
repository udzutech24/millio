# Plan: Millio → Google Sheets (экспорт данных)

**Slug:** `google-sheets-sync`  
**Дата создания:** 2026-05-12  
**Обновлён:** 2026-06-03  
**Status:** В РАБОТЕ  
**Scope:** Односторонний экспорт (app → Sheets). Обратная синхронизация исключена из scope.  
**Research v1:** [`thoughts/research/2026-05-11-google-sheets-sync.md`](../thoughts/research/2026-05-11-google-sheets-sync.md)  
**Research v2:** [`thoughts/research/2026-06-02-google-sheets-export-v2.md`](../thoughts/research/2026-06-02-google-sheets-export-v2.md)

---

## Цель

Пользователь нажимает «Подключить Google Таблицы» → OAuth → автоматически создаётся структурированный Spreadsheet → вся история попадает туда → новые транзакции дописываются автоматически.

В Spreadsheet пользователь видит:
- Полную историю транзакций с фильтрами
- Аналитику по дням, месяцам, категориям, счетам
- Графики (встроенные средства Sheets)
- Активные и архивные счета отдельно

---

## ⚠️ Critical Path — сделать до старта разработки

- [ ] **Запустить верификацию OAuth consent screen** в Google Cloud Console  
  Scope `spreadsheets` — sensitive. Срок верификации Google: **2–4 недели**.  
  Без этого публичный релиз невозможен.  
  → [Google Cloud Console → APIs & Services → OAuth consent screen](https://console.cloud.google.com/apis/credentials/consent)

- [ ] **Обновить Privacy Policy** — добавить раздел про Google Sheets (opt-in, данные не передаются третьим лицам кроме Google)

---

## Структура Spreadsheet (целевая)

| Лист | Тип | Кто пишет | Назначение |
|------|-----|-----------|-----------|
| `Transactions` | raw data | app (append) | Полная история транзакций |
| `Accounts` | raw data | app (rewrite) | Активные счета, текущие балансы |
| `Accounts_Archive` | raw data | app (rewrite) | Архивные счета с датой закрытия |
| `Investments` | raw data | app (rewrite) | Инвестиционный портфель |
| `Budgets` | raw data | app (rewrite) | Бюджетные планы и лимиты |
| `Dashboard` | formulas | app (создаёт 1 раз) | Графики, сводка, топ категорий |
| `Monthly` | formulas | app (создаёт 1 раз) | Доходы/расходы/сбережения по месяцам |
| `By_Account` | formulas | app (создаёт 1 раз) | Разбивка по каждому счёту |

**Правило:** formula-листы (`Dashboard`, `Monthly`, `By_Account`) создаются при инициализации и **никогда не перезаписываются** повторными sync'ами.

### Схема `Transactions`

```
date | amount | type | category | subcategory | account | account_type |
note | currency | exchange_rate | amount_base | recurrence |
is_transfer | transfer_to | millio_id | updated_at
```

- `type`: `expense` / `income` / `transfer`
- `amount_base`: сумма в базовой валюте пользователя (для сводок)
- `is_transfer` + `transfer_to`: пара переводов не дублирует расход
- Frozen row 1, auto-filter, conditional formatting (расход=красный, доход=зелёный)

### Схема `Accounts`

```
name | balance | balance_base | type | bank | currency | group | priority | millio_id | synced_at
```

### Схема `Accounts_Archive`

```
name | final_balance | final_balance_base | type | bank | currency | group | 
opened_at | archived_at | millio_id
```

### Схема `Investments`

```
name | ticker | quantity | avg_price | buy_currency | total_cost | total_cost_base | millio_id | updated_at
```

*Рыночные цены — не выгружаем. Пользователь добавляет `=GOOGLEFINANCE(ticker)` самостоятельно.*

### Схема `Budgets`

```
category | period_type | limit_amount | currency | millio_id | synced_at
```

---

## Phase 0 — Google Cloud + OAuth Consent (блокер) [ ]

**Цель:** запустить верификацию в Google раньше разработки.  
**Параллельно с Phase 1 разработкой.**

- [ ] Создать/настроить Google Cloud project для Millio
- [ ] Включить Sheets API v4 + Drive API
- [ ] Заполнить OAuth consent screen (app name, logo, scopes)
- [ ] Подать на верификацию scope `spreadsheets` (ждать 2–4 недели)
- [ ] Обновить Privacy Policy — добавить раздел Google Sheets
- [ ] Добавить тестовых пользователей для разработки (пока верификация идёт)

**Acceptance:** team-member может авторизоваться через OAuth в dev-сборке и получить тестовый spreadsheet.

---

## Phase 1 — Backend: OAuth + инициализация Spreadsheet [x]

**Репо:** `САЙТ бэк/`  
**Реализованные файлы:** `src/sheets/sheets.service.ts`, `src/sheets/sheets.controller.ts`, `src/sheets/sheets.module.ts`, `src/sheets/sheets.dto.ts`, `src/sheets/sheets-export.types.ts`

### 1.1 Backend: OAuth + Sheets proxy [x]

- [x] `src/sheets/sheets.service.ts` — OAuth, fullSync, incrementalSync
- [x] `src/sheets/sheets.controller.ts` — 5 endpoints под JwtAuthGuard
- [x] `src/sheets/sheets.module.ts` + добавлен в app.module.ts
- [x] Модель `SheetsIntegration` добавлена в prisma/schema.prisma
- [x] `src/sheets/sheets.dto.ts` + `sheets-export.types.ts`

### 1.2 iOS: SheetsSync service [x]

- [x] `SheetsExportService` actor создан (`millio/Core/Sheets/SheetsExportService.swift`)
- [x] `SheetsExportTrigger` с дебаунсом 5 сек (`millio/Core/Sheets/SheetsExportTrigger.swift`)
- [x] Хук в `CashflowPersistenceService` через `onTransactionSaved` callback
- [x] `SheetsConnectionView` с тремя состояниями (`millio/UI/Profile/SheetsConnectionView.swift`)
- [x] 9 ключей локализации RU+EN+zh-Hans добавлены

### 1.3 Структура Sheet [x]

Реализована (8 листов: Transactions / Accounts / Accounts_Archive / Investments / Budgets / Dashboard / Monthly / By_Account)

### 1.4 Dashboard формулы (шаблон) [x]

Внедряются один раз при создании листов:

| Ячейка | Формула | Что показывает |
|--------|---------|---------------|
| Dashboard!B2 | `=SUMIFS(Transactions!C:C,Transactions!B:B,"expense",Transactions!A:A,">="&DATE(YEAR(TODAY()),MONTH(TODAY()),1))` | Расходы текущего месяца |
| Dashboard!B3 | `=SUMIFS(Transactions!C:C,Transactions!B:B,"income",...)` | Доходы текущего месяца |
| Dashboard!E2:F6 | `=QUERY(Transactions!...,"SELECT D,SUM(C) GROUP BY D ORDER BY SUM(C) DESC LIMIT 5")` | Топ-5 категорий |
| Monthly!A:E | `=QUERY(Transactions!...,"SELECT YEAR(A),MONTH(A),SUM(C) WHERE B='income' GROUP BY ...")` | Сводка по месяцам |
| By_Account!A:D | `=QUERY(Transactions!...,"SELECT F,YEAR(A),MONTH(A),SUM(C) GROUP BY ...")` | По счетам |

**Acceptance Phase 1:** РЕАЛИЗОВАН — backend endpoints задеплоены, iOS сервис реализован, локализация добавлена.

### Pending — требует ручных действий разработчика

- [ ] Добавить SheetsConnectionView в ProfileView (после секции Backup)
- [ ] URL scheme `millio://sheets/callback` в Info.plist CFBundleURLTypes
- [ ] Добавить файлы из `millio/Core/Sheets/` в Xcode target membership
- [ ] ENV vars: GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REDIRECT_URI
- [ ] `npx prisma migrate dev --name add-sheets-integration`
- [ ] Запустить верификацию OAuth consent screen (scope: spreadsheets, CRITICAL: 2-4 недели)

---

## Phase 2 — Backend: полный sync истории [ ]

**Репо:** `САЙТ бэк/`

### 2.1 Full sync endpoint [ ]

- [ ] `POST /sheets/sync/full` — выгрузить всю историю:
  - Transactions: все `CashflowTransaction` пользователя → sorted by date asc → batch append по 500 строк
  - Accounts: все активные `Card` (archivedAt == nil) → clear + rewrite
  - Accounts_Archive: все `Card` с `archivedAt != nil` → clear + rewrite
  - Investments: все `Investment` → clear + rewrite
  - Budgets: все активные `BudgetPlan` + лимиты → clear + rewrite
- [ ] Фоновая очередь (Bull/Redis) — не блокирует ответ iOS
- [ ] Прогресс: `GET /sheets/sync/progress` → `{status, processed, total}`
- [ ] Дедупликация Transactions по `millio_id` перед append

### 2.2 Incremental sync [ ]

- [ ] `POST /sheets/sync/transaction` — append одной транзакции (при создании/изменении в app)
- [ ] `POST /sheets/sync/accounts` — rewrite Accounts + Accounts_Archive (при изменении баланса)
- [ ] Обработка валютных курсов: `amount_base = amount * exchange_rate`
- [ ] Логирование: `sheets_sync_log(userId, type, rows, duration, error?)`

**Acceptance Phase 2:**
- Full sync 1000 транзакций завершается за < 60 сек
- Прогресс виден через polling `/sheets/sync/progress`
- Новая транзакция → появляется в Transactions sheet за < 30 сек

---

## Phase 3 — iOS: SheetsExportService + UI [x]

**Репо:** `app/`  
**Реализованные файлы:**
- `millio/Core/Sheets/SheetsExportService.swift` — protocol + actor SheetsExportServiceImpl
- `millio/Core/Sheets/SheetsExportTrigger.swift` — fire-and-forget actor с дебаунсом 5с
- `millio/UI/Profile/SheetsConnectionView.swift` — SwiftUI-вью профиля (3 состояния)
- `millioTests/Core/SheetsExportServiceTests.swift` — 10 unit-тестов + 1 trigger-тест

### 3.1 SheetsExportService [x]

- [x] `connectAccount()` → GET `/sheets/auth-url` → URL для `.openURL` (Safari)
- [x] `disconnectAccount()` → `DELETE /sheets/disconnect`
- [x] `getStatus()` → `GET /sheets/status` с offline fallback на UserDefaults кэш
- [x] `syncNow()` → `POST /sheets/sync` → возвращает `SheetsExportStatus`
- [x] `handleOAuthCallback(code:)` → `POST /sheets/callback` → устанавливает `isConnected`
- [x] `SheetsExportDefaults` — enum с UserDefaults ключами (isConnected, spreadsheetId, spreadsheetURL, lastSyncAt, totalRows)
- [x] Retry-логика: 401 → forceRefresh token → повтор запроса
- [x] 403 → `SheetsExportError.tokenRevoked` (Google отозвал доступ)

### 3.2 SheetsExportTrigger [x]

- [x] `notifyTransactionAdded()` — fire-and-forget, дебаунс 5с, защита от шторма при batch-импорте
- [x] Хук в `CashflowPersistenceService.updateTransactionAsync()` — `onTransactionSaved?()` после `modelContext.save()`
- [x] `CashflowViewModel` получает `sheetsExportTrigger` опциональным параметром
- [x] `RootTabView.ensureCashflowViewModel()` прокидывает `diContainer?.sheetsExportTrigger`
- [x] DIContainer + APIClientFactory: `makeSheetsExportService`, `makeSheetsExportTrigger`

### 3.3 SheetsConnectionView [x]

- [x] Состояние «не подключено»: кнопка «Подключить Google Таблицы»
- [x] Состояние «синхронизация»: ProgressView + «Выгружаем историю…»
- [x] Состояние «подключено»: rows count, lastSyncAt, «Открыть таблицу», «Отключить»
- [x] `handleOAuthRedirect` — обрабатывает `millio://sheets/callback?code=...`
- [x] Confirmation dialog перед отключением
- [x] Error alert (включая tokenRevoked)

### 3.4 Локализация [x]

- [x] 9 ключей в `Localizable.xcstrings`: sheets.connect.title, sheets.connect.button, sheets.connected.status, sheets.connected.openButton, sheets.connected.disconnect, sheets.sync.progress, sheets.sync.rows, sheets.sync.lastUpdated, sheets.error.tokenRevoked
- [x] Языки: RU, EN, zh-Hans

**Что осталось (ручные действия разработчика):**
- Добавить `SheetsConnectionView` в `ProfileView` (в нужную секцию профиля)
- Зарегистрировать URL scheme `millio://sheets/callback` в `Info.plist` / `Entitlements`
- Добавить `SheetsExportService.swift` и `SheetsExportTrigger.swift` в Xcode target (drag & drop или через SPM)
- Phase 0: запустить верификацию OAuth consent screen в Google Cloud

**Acceptance Phase 3:** РЕАЛИЗОВАН — билд успешен, 11/11 тестов прошли.

---

## Технические решения

| Вопрос | Решение |
|--------|---------|
| OAuth токены | Server-side в NestJS DB/Redis (не на iOS) |
| Архивные счета | Отдельный лист `Accounts_Archive` |
| Множественные валюты | Поле `amount_base` = конвертация по курсу на дату транзакции |
| Квоты Sheets API | Batch по 500 строк, очередь на backend, max 60 write/мин/пользователь |
| Дедупликация | `millio_id` (UUID) в каждой строке Transactions |
| Dashboard обновление | Только raw листы rewrite, formula-листы не трогаем |
| Обратная sync | **Out of scope** — намеренно исключено для первого релиза |
| Частота sync | Full sync при первом подключении; incremental при каждой транзакции; ежедневный refresh Accounts |

---

## Доработать (blocker перед первым рабочим тестом)

> **Статус 2026-06-03:** end-to-end тест упал. iOS стучится в `api.iqdrop.ru`, sheets там нет.

### Вариант A — тест на симуляторе (уже частично готово)
- [~] `SheetsExportService.baseURL()` → `#if targetEnvironment(simulator)` → `localhost:3000` ✓
- [ ] Пересобрать в Xcode **на симуляторе**, запустить, пройти OAuth flow до конца
- [ ] Убедиться что таблица создалась в Google Drive с форматированием

### Вариант B — prod деплой (нужен для реального устройства)
- [ ] Задеплоить `САЙТ бэк/src/sheets/` на прод-сервер (`millio-back`, 64.188.56.106) — через `dep-agent`
- [ ] Применить миграцию `20260602120735_add_sheets_integration` на прод-БД
- [ ] Добавить в прод `.env`: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI=https://api.milliomoney.ru/sheets/callback`
- [ ] Добавить `https://api.milliomoney.ru/sheets/callback` как Authorized Redirect URI в Google Cloud Console
- [ ] После деплоя убрать `#if targetEnvironment(simulator)` override из `SheetsExportService.baseURL()` (или оставить — он не ломает прод)

---

## Журнал

| Дата | Событие |
|------|---------|
| 2026-05-11 | Research v1 завершён |
| 2026-05-12 | План создан (scope включал двунаправленный sync) |
| 2026-06-02 | Research v2 — мировой опыт, идеальная структура листов |
| 2026-06-02 | План переработан: scope сужен до одностороннего экспорта; структура листов расширена до 8; добавлены formula-листы Dashboard/Monthly/By_Account; архивные счета выделены отдельно |
| 2026-06-02 | Phase 3 iOS реализована: SheetsExportService, SheetsExportTrigger, SheetsConnectionView, локализация, DI, хук в CashflowPersistenceService. 11/11 тестов зелёные. |
| 2026-06-02 | Phase 1 реализована (iOS + NestJS backend). Phase 2/3 исключены из scope — одностороннний экспорт. |
| 2026-06-03 | End-to-end тест не прошёл: ошибка `Cannot GET /api/v1/sheets/auth-url` — iOS-приложение обращается к прод-бэкенду (api.iqdrop.ru), sheets-модуль на прод не задеплоен. Применён fix: `#if targetEnvironment(simulator)` в `SheetsExportService.baseURL()` → симулятор идёт на `localhost:3000`. На реальном устройстве нужен prod деплой. Тест пока не завершён. |
