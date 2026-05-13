# Plan: Синхронизация Millio ↔ Google Sheets

**Slug:** `google-sheets-sync`  
**Дата создания:** 2026-05-12  
**Status:** НЕ НАЧАТ  
**Research:** [`thoughts/research/2026-05-11-google-sheets-sync.md`](../thoughts/research/2026-05-11-google-sheets-sync.md)  
**Spec:** не создан (создать перед Phase 1)

---

## Контекст

Дать пользователю расширенный вид данных в Google Таблицах и возможность вводить транзакции прямо там. Рекомендуемая архитектура: **iOS → NestJS backend (уже есть) → Sheets API v4**. Backend хранит OAuth токены, слушает Drive webhooks, проксирует все Sheets-операции.

Детали архитектуры и обоснование — в research-файле выше.

---

## ⚠️ Critical Path — сделать до старта разработки

- [ ] **Запустить верификацию OAuth consent screen** в Google Cloud Console  
  Scope `spreadsheets` — sensitive. Срок верификации Google: **2–4 недели**. Без этого app нельзя публично использовать Sheets API.  
  → [Google Cloud Console → APIs & Services → OAuth consent screen](https://console.cloud.google.com/apis/credentials/consent)

---

## Phase 0 — Proof of Concept: app пишет в Sheet [ ]

**Цель:** убедиться в feasibility, показать живой результат до написания Spec.  
**Scope:** iOS-only, без backend, ручная OAuth, polling.  
**Файлы:** новый `SheetsProbeService.swift`, временный UI в Debug/Settings

- [ ] Настроить Google Cloud project, включить Sheets API v4
- [ ] Добавить `GoogleSignIn-iOS` + `GoogleAPIClientForREST` через SPM
- [ ] `SheetsProbeService`: OAuth sign-in → создать тестовый spreadsheet → append 3 транзакции
- [ ] Убедиться, что квоты, токен в Keychain и batch append работают
- [ ] Задокументировать: что сработало, что нет, реальная latency

**Acceptance:** транзакции из app появляются в Google Sheet за < 5 сек.

---

## Phase 1 — MVP: App → Sheets (односторонний sync) [ ]

**Цель:** пользователь подключает Google аккаунт в настройках → вся история выгружается в Sheet → новые транзакции дописываются автоматически.  
**Стек:** iOS + NestJS backend.

### 1.1 Backend: OAuth + Sheets proxy [ ]

**Репо:** `САЙТ бэк/`  
**Файлы:** `sheets/sheets.module.ts`, `sheets/sheets.service.ts`, `sheets/sheets.controller.ts`, `auth/google-oauth.service.ts`

- [ ] Google OAuth 2.0 flow server-side: `/sheets/auth` → redirect → callback → сохранить refresh token в DB (userId → token)
- [ ] `SheetsService.createSpreadsheet(userId)` — создать spreadsheet с листами (Transactions, Accounts, Budgets, Investments, Dashboard)
- [ ] `SheetsService.appendTransactions(userId, rows[])` — batch append в Transactions sheet
- [ ] `SheetsService.fullSync(userId)` — выгрузить всю историю (postman-tested)
- [ ] Endpoint `POST /sheets/sync` — принимает массив транзакций от iOS, пишет в Sheet

### 1.2 iOS: SheetsSync service [ ]

**Файлы:** `millio/Core/Sheets/SheetsSyncService.swift`, `millio/UI/Profile/SheetsConnectionView.swift`

- [ ] `SheetsSyncService`: подключение (`connectAccount()`), отключение, статус
- [ ] При подключении — вызвать `/sheets/sync` с полной историей транзакций
- [ ] Hook в `CashflowViewModel` при создании транзакции → incremental sync (fire-and-forget, non-blocking)
- [ ] `SheetsConnectionView` в ProfileView: кнопка «Подключить Google Таблицы», статус, ссылка на spreadsheet

### 1.3 Структура Sheet [ ]

Лист **Transactions:**
```
date | amount | type | category | card | note | currency | recurrence | millio_id | updated_at | source
```
Лист **Accounts:** name, balance, type, bank, currency, group, millio_id  
Лист **Budgets:** category, period, limit, spent, remaining, %, millio_id  
Лист **Investments:** name, symbol, quantity, avg_price, last_price, total_cost, current_value, p&l, millio_id  
Лист **Dashboard:** pivot-таблица расходов по категориям, график баланса (формулы Sheets, не код)

**Acceptance Phase 1:**
- Пользователь нажимает «Подключить» → OAuth → spreadsheet создан и заполнен
- Новая транзакция в app → появляется в Sheet за < 30 сек
- Dashboard-лист показывает сводку за текущий месяц

---

## Phase 2 — Sheets → App: ввод новых транзакций [ ]

**Цель:** пользователь вводит новую строку в Transactions sheet → она появляется в app.  
**Механизм:** Apps Script installable trigger (`onEdit`) → POST на NestJS webhook → APNs → iOS.

### 2.1 Apps Script [ ]

- [ ] Написать Apps Script, устанавливаемый через NestJS при создании spreadsheet
- [ ] `onEdit` trigger → если добавлена новая строка в Transactions → `UrlFetchApp.fetch(webhookUrl, payload)`
- [ ] Payload: строка с `millio_id`, amount, date, category, card

### 2.2 Backend: webhook + validation [ ]

**Файлы:** `sheets/sheets.webhook.controller.ts`

- [ ] `POST /sheets/webhook` — принять payload от Apps Script
- [ ] Валидация: amount числовое, date парсится, category из known list
- [ ] Дедупликация по `millio_id` (если строка уже есть — skip)
- [ ] Push-уведомление в iOS через APNs: «Новая транзакция из Таблицы»

### 2.3 iOS: приём транзакций из Sheet [ ]

**Файлы:** `millio/Core/Sheets/SheetsSyncService.swift` (расширение)

- [ ] Background push → `SheetsSyncService.handleIncomingTransaction(payload)`
- [ ] Создать `CashflowTransaction` через существующий репозиторий
- [ ] Показать in-app уведомление: «Добавлена транзакция из Google Таблиц»

**Acceptance Phase 2:**
- Новая строка в Sheet → транзакция в app за < 60 сек
- Дублированные строки не создаются
- Некорректные данные (нечисловая сумма) — строка помечается красным в Sheet, транзакция не создаётся

---

## Phase 3 — Полный двунаправленный sync [ ]

**Цель:** редактирование существующих записей в Sheet отражается в app и наоборот. Drive webhook вместо polling.

- [ ] Drive API watch channel на spreadsheet (NestJS listens, renewal cron каждые 23 часа)
- [ ] Conflict resolution: last-write-wins по `updated_at` для бюджетов и счетов
- [ ] Edit транзакций из Sheet с подтверждением в app (в силу append-only природы — осторожно)
- [ ] Sync бюджетных лимитов из Sheet → app
- [ ] Spec для Phase 3 пишется отдельно после завершения Phase 2

---

## Технические решения

| Вопрос | Решение |
|--------|---------|
| OAuth токены | Хранятся server-side в NestJS (не в iOS app) |
| iOS SDK | `GoogleSignIn-iOS` + `GoogleAPIClientForREST` (SPM) |
| Conflict resolution | Транзакции append-only; бюджеты/счета — last-write-wins с `updated_at` |
| Rate limiting | Batch API + очередь на backend; не более 50 write/мин |
| Drive watch channel | Renewal cron каждые 23 часа в NestJS |
| Финансовые данные в Google | Явное opt-in согласие пользователя, documented в privacy policy |

---

## Журнал

| Дата | Событие |
|------|---------|
| 2026-05-12 | Research завершён, план создан |
