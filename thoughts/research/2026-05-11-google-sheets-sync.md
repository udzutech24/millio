# Research: Синхронизация Millio ↔ Google Sheets

**Дата:** 2026-05-11  
**Статус:** Stage 1 — Research Complete  
**Следующий шаг:** Spec (если принято решение делать)

---

## 1. Постановка задачи

Хотим дать пользователю возможность:
1. Видеть все данные Millio в Google Таблице (транзакции, счета, бюджеты, инвестиции)
2. Вводить/редактировать данные прямо в таблице — и они появляются в приложении
3. Иметь «расширенный вид» — больше полей, pivot-таблицы, графики средствами Sheets

---

## 2. Что есть в приложении сейчас

### Модели данных (SwiftData, 16 @Model типов)

| Модель | Ключевые поля | Роль |
|--------|--------------|------|
| `CashflowTransaction` | amount, type, date, cardID, categoryRaw, recurrenceRuleRaw, balanceAdjustment | **Ядро домена** — расходы/доходы/переводы |
| `Card` | name, balance, type, bank, currency, priority | Счета и карты |
| `FinanceGroup` | name, colorHex, displayCurrency, order | Группы счетов |
| `Investment` | name, amount, category, marketSymbol, marketQuantity, lastKnownUnitPrice | Инвестиции |
| `Credit` | name, amount, interestRate, monthlyPayment, remainingAmount | Кредиты |
| `BudgetPlan` | budgetID, categoryKind, periodType, totalLimitAmount | Бюджеты |
| `BudgetCategoryLimit` | budgetID, categoryRawValue, limitAmount | Лимиты по категориям |
| `Cashback` | cardID, amount, date, category | Кешбэк |
| `CashflowCustomCategory` | categoryID, kindRaw, name, icon | Пользовательские категории |
| `HistoricalRate` | baseCurrency, quoteCurrency, rate, rateDate | Курсы валют |

### Что уже есть из экспорта
- `exportAllDataAsync()` → структурированный **JSON** (не CSV)
- Share Sheet для `.milliobackup` файла (бинарный: magic bytes + JSON payload + AES-GCM + LZFSE)
- OCR-импорт акций через Vision framework
- **CSV экспорта нет. Google Sheets интеграции нет.**

### Backup JSON — потенциальная основа sync
Backup v2.3 содержит массив объектов типа `{type: "CashflowTransaction", fields: {...}}`. Это готовый структурированный формат, который можно адаптировать для Sheets.

---

## 3. Google Sheets API — технические возможности

### API v4 capabilities
- Полный CRUD: read, write, append, batch update
- Batch API: несколько операций = 1 HTTP-запрос (критично для квот)
- Named ranges, conditional formatting — можно строить rich-таблицы программно

### Квоты (актуальные, 2026)
| Тип | Лимит |
|-----|-------|
| Read запросы | 60 / мин / пользователь |
| Write запросы | 60 / мин / пользователь |
| На проект | 300 / мин |
| Payload | 2 МБ |

> ⚠️ Google в 2026 вводит платную модель за превышение квот — нужен cost model при масштабировании.

### OAuth 2.0 на iOS
- Обязателен Authorization Code Flow + PKCE
- Рекомендован **`GoogleSignIn-iOS` SDK** (управляет токенами автоматически)
- Access token + refresh token — в Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **Важно:** scope `spreadsheets` — sensitive. Нужна верификация Google OAuth consent screen (срок до 4 недель)

### Push из Sheets → App (как узнать об изменении)
Три механизма:

| Механизм | Как работает | Ограничение |
|----------|-------------|------------|
| **Apps Script `onEdit` trigger** | Пользователь меняет ячейку → trigger → POST на webhook | Не срабатывает при программных правках через API |
| **Drive API watch channel** | HTTP POST на ваш HTTPS URL при любом изменении файла | Канал истекает через 1–24 часа, нужен renewal |
| **Polling** | App сам читает Sheet по расписанию | Задержка, расход квоты и батареи |

---

## 4. Архитектурные варианты

### Вариант A: Direct iOS ↔ Sheets (без backend)
```
iOS SwiftData ←→ Google Sheets API v4
         ↑
    polling / Apps Script webhook
```
**Pros:** нет серверных затрат, MVP за 1–2 недели  
**Cons:** нет push-уведомлений при изменении Sheets; OAuth токен хранится в app; polling = задержка

### Вариант B: iOS → NestJS Backend → Sheets (рекомендуется)
```
iOS SwiftData → NestJS (уже есть!) → Google Sheets API
                    ↑
         Drive webhook listener → APNs → iOS
```
У Millio **уже есть NestJS backend** (`САЙТ бэк/`). Это сильный аргумент в пользу B.

**Pros:**
- OAuth refresh token server-side (безопаснее, не в приложении)
- Drive webhook → NestJS → APNs/CloudKit → iOS (near-realtime push)
- Rate limiting буфер перед Sheets API (батчинг запросов от нескольких пользователей)
- Чистый внутренний API на iOS-стороне

**Cons:** дополнительная latency iOS → backend → Sheets

### Вариант C: Apps Script как standalone middleware
```
Пользователь редактирует Sheet
       ↓ onEdit trigger
  Apps Script → POST → NestJS → APNs → iOS
```
Используется как **дополнение к B**, не замена. Нужен для push из Sheets в ответ на ручные правки.

### Вариант D: Zapier/Make (no-code)
- MVP за пару часов, задержка 5–15 мин, стоимость при масштабе
- **Только для proof-of-concept**

---

## 5. Рекомендуемая архитектура: Backend Proxy + Drive Webhook

```
┌─────────────────────────────────────────────────────┐
│                    iOS App                          │
│  SwiftData ←→ SheetsSync service                   │
│                    ↕ REST                           │
└─────────────────────────────────────────────────────┘
             ↕ Internal API
┌─────────────────────────────────────────────────────┐
│              NestJS Backend                         │
│  /sheets/sync    → Sheets API v4 (batch)            │
│  /sheets/webhook ← Drive API watch channel          │
│  GoogleOAuth     → token store (DB/Redis)           │
│  APNs push       → iOS on Sheet change              │
└─────────────────────────────────────────────────────┘
             ↕ Sheets API v4
┌─────────────────────────────────────────────────────┐
│              Google Sheets                          │
│  Transactions | Accounts | Budgets | Investments    │
│  (+ Dashboard sheet с pivot-таблицами)              │
└─────────────────────────────────────────────────────┘
```

---

## 6. Conflict Resolution стратегия

Финансовые транзакции — **append-only**. Это устраняет 90% конфликтов.

| Тип данных | Стратегия |
|-----------|-----------|
| `CashflowTransaction` | Append-only. Удаление = soft-delete флаг. Нет edit-конфликтов. |
| `BudgetPlan` / `BudgetCategoryLimit` | Last-write-wins с `updatedAt` timestamp |
| `Card` / `Investment` | Last-write-wins с `updatedAt` |
| `CashbackCustomCategory` | Last-write-wins |

Каждая строка в Sheet получает скрытую колонку `millio_id` (UUID) + `updated_at` + `source` (`app` / `sheet`). Это позволяет:
- Идентифицировать запись при update
- Разрешать конфликты
- Помечать строки по источнику для debugging

---

## 7. Структура Google Sheet (Расширенный вид)

Предлагаемая структура — один Spreadsheet, несколько листов:

### Лист `Transactions` (основной)
| date | amount | type | category | card | note | currency | recurrence | millio_id | updated_at | source |
|------|--------|------|----------|------|------|----------|------------|-----------|------------|--------|
Пользователь вводит новую строку → apps script → sync в app

### Лист `Accounts`
| name | balance | type | bank | currency | group | priority | millio_id | updated_at |
Только read (или осторожный write с подтверждением)

### Лист `Budgets`
| category | period | limit | spent | remaining | % | millio_id | updated_at |
Partial write — `limit` редактируется из Sheet

### Лист `Investments`
| name | symbol | quantity | avg_price | last_price | total_cost | current_value | p&l | p&l% | millio_id |
Read-only (котировки обновляются из market data backend)

### Лист `Dashboard` (read-only, сводный)
- Pivot-таблица расходов по категориям за месяц
- График динамики баланса
- Топ-5 категорий трат
- Бюджет vs. факт

---

## 8. Тилер-Money паттерн (эталонный кейс)

Tiller Money (лучший продукт в этой нише):
- **Архитектура:** Plaid/Yodlee → Tiller backend → Google Sheets Add-on
- **Sync:** односторонний (банк → Sheet), каждые 6 часов
- **Ключевой инсайт:** Tiller **не делает двунаправленный sync** — слишком сложная conflict resolution для массового продукта
- **Add-on:** запускается как Apps Script, дозаписывает строки в Transactions sheet

**Что это значит для нас:** двунаправленный sync — амбициозно. Для MVP разумно начать с **одностороннего (app → Sheets)** + **ввод новых транзакций** из Sheets в app. Редактирование существующих — Phase 2.

---

## 9. Риски и ограничения

| Риск | Уровень | Митигация |
|------|---------|-----------|
| Google OAuth consent screen verification | 🔴 Высокий | Начать процесс верификации немедленно — срок 2–4 недели |
| Sensitive scope `spreadsheets` | 🔴 Высокий | Privacy policy update, обоснование необходимости scope |
| Quota при масштабе (60 write/мин) | 🟡 Средний | Batch API + очередь на backend |
| `onEdit` не реагирует на API-правки | 🟡 Средний | Drive webhook для детекции всех изменений |
| Drive watch channel expiry | 🟡 Средний | Cron-задача для renewal каждые 23 часа |
| Финансовые данные на серверах Google | 🟡 Средний | Явное согласие пользователя, опциональная фича |
| Token revocation пользователем | 🟡 Средний | Graceful fallback, re-auth flow |
| Схема Sheet vs. схема app при обновлении | 🟢 Низкий | Version column в Sheet + migration script |

---

## 10. Фазирование (предлагаемый roadmap)

### Phase 0: Proof of Concept (1 неделя)
- iOS читает Transactions sheet через Sheets API (polling)
- iOS пишет новую транзакцию в Sheet при создании в app
- Ручная OAuth авторизация (без backend)
- Цель: убедиться в feasibility, показать пользователю

### Phase 1: MVP — App → Sheets (2–3 недели)
- NestJS endpoint `/sheets/connect` (OAuth flow server-side)
- Начальная выгрузка всей истории транзакций в Sheet
- Incremental sync при каждом добавлении транзакции в app
- Dashboard sheet с базовой аналитикой
- UI в Settings: "Подключить Google Таблицы"

### Phase 2: Sheets → App (3–4 недели)
- Apps Script installable trigger → NestJS webhook → iOS push
- Парсинг новых строк из Transactions sheet → `CashflowTransaction`
- Validation: сумма, категория, дата — must be valid
- Conflict detection (дублированный millio_id)

### Phase 3: Полный двунаправленный sync (4–6 недель)
- Drive API watch channel (real-time detection изменений)
- Edit транзакций из Sheet (с подтверждением в app)
- Sync бюджетных лимитов из Sheet → app
- Расширенный Dashboard с инвестициями

---

## 11. Выводы и рекомендации

### Топ-3 вывода
1. **NestJS backend — главный актив.** Не нужно хранить OAuth токены на клиенте, можно проксировать все Sheets вызовы, батчить их и обрабатывать Drive webhooks.
2. **Начни с app → Sheets, не с двунаправленного.** Tiller Money — успешный продукт с односторонним sync. Двунаправленный sync сложнее и редко нужен для транзакций (их обычно не редактируют постфактум).
3. **OAuth верификация — критический path.** Запустить процесс верификации OAuth consent screen сразу, параллельно с разработкой. Иначе задержка 2–4 недели в конце.

### Рекомендуемый первый шаг
Spec для **Phase 1 (app → Sheets)** — это даст 80% ценности при 20% сложности двунаправленного sync.

---

## 12. Ссылки и источники

- [Google Sheets API v4 — Usage Limits](https://developers.google.com/workspace/sheets/api/limits)
- [OAuth 2.0 for iOS Native Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Apps Script Simple Triggers](https://developers.google.com/apps-script/guides/triggers)
- [Apps Script Installable Triggers](https://developers.google.com/apps-script/guides/triggers/installable)
- [Google Drive Push Notifications](https://developers.google.com/workspace/drive/api/guides/push)
- [Tiller Money — How It Works](https://tiller.com/how-tiller-works/)
- [GoogleSignIn-iOS SDK](https://github.com/google/GoogleSignIn-iOS)
- [GoogleAPIClientForREST (official Swift)](https://github.com/google/google-api-objectivec-client-for-rest)
