# Research v2: Millio → Google Sheets (одностороннний экспорт)

**Дата:** 2026-06-02  
**Статус:** Stage 1 — Research Complete (v2, обновлённый)  
**Предыдущий research:** [`2026-05-11-google-sheets-sync.md`](2026-05-11-google-sheets-sync.md)  
**Следующий шаг:** обновить план `2026-05-12__google-sheets-sync.md`

---

## Изменение scope

Пользователь хочет **одностороннюю выгрузку** (app → Sheets) без обратной синхронизации.  
Phase 2 (Sheets → App) и Phase 3 (двунаправленный sync) — исключены из текущего scope.

Приоритеты нового scope:
- Полная история транзакций
- Графики и визуализация (встроенные средства Sheets)
- Навигация по дням, месяцам, счетам
- Архивные счета — видны отдельно
- Простое подключение одной кнопкой

---

## Мировой опыт — что делают лучшие

### Tiller Money (эталон одностороннего sync)
- Архитектура: Plaid → Tiller backend → Google Sheets Add-on
- **Ключевой инсайт:** sync раз в сутки утром, не real-time — пользователи не жалуются
- Используют Templates Gallery: пользователь сам выбирает шаблон Dashboard
- Отдельный лист `Balance History` — баланс каждого счёта на каждый день: это основа для графика
- Source field `Institution` — аналог нашего account name

### Copilot, YNAB — CSV-экспорт
- Стандартные поля: date, payee, amount, category, account, notes, transaction_id
- Обязательно: `transaction_id` для дедупликации при повторном экспорте
- Тип транзакции кодируется знаком: расход = отрицательный amount, доход = положительный

### Monarch Money — расширенный экспорт
- Добавляют `original_name` (название операции из банка), `type`, `tags[]`
- Месячные сводки — **отдельный лист** `Monthly Summary`, строится формулами (не выгружается из app)
- Это ключевой UX-паттерн: app выгружает raw data, пользователь видит аналитику из формул Sheets

### Личный Finance трекеры (r/personalfinance)
- Самый популярный паттерн: один лист Transactions (raw) + автоматические Dashboard-листы на формулах
- Пользователи ценят возможность добавить свои колонки рядом с данными
- Conditional formatting по категориям — очень востребована
- Frozen header row + auto-filter — обязательно

---

## Идеальная структура Spreadsheet (вывод из research)

### Принцип: raw data + formula-driven analytics

App выгружает сырые данные. Sheets сам строит аналитику через формулы — это и надёжнее, и масштабируемее.

### Лист 1: `Transactions` (основной, raw data)

```
| date | amount | type | category | subcategory | account | account_type | 
| note | currency | exchange_rate | amount_rub | recurrence | 
| is_transfer | transfer_to | millio_id | updated_at |
```

**Особенности:**
- `amount` всегда положительное, знак задаёт `type` (expense / income / transfer)
- `amount_rub` — сумма в базовой валюте (для сводок в смешанных валютах)
- `is_transfer` + `transfer_to` — пара записей переводов (не дублируют расходы)
- Frozen row 1 (заголовки) + auto-filter включён
- Conditional formatting: расходы — красный, доходы — зелёный, переводы — серый

### Лист 2: `Accounts` (активные счета)

```
| name | balance | balance_rub | type | bank | currency | group | priority | millio_id | synced_at |
```

### Лист 3: `Accounts_Archive` (архивные счета)

```
| name | final_balance | final_balance_rub | type | bank | currency | group | 
| opened_at | archived_at | millio_id |
```

**Важно:** архивные счета — отдельный лист. Иначе они засоряют активный список и ломают формулы.

### Лист 4: `Investments` (портфель)

```
| name | ticker | quantity | avg_price | buy_currency | 
| total_cost | total_cost_rub | millio_id | updated_at |
```

Рыночные цены (last_price, current_value, p&l) — **не выгружаем из app**. Пользователь может добавить колонку с `=GOOGLEFINANCE(ticker)` самостоятельно.

### Лист 5: `Budgets` (бюджеты)

```
| category | period_type | limit_amount | currency | millio_id | synced_at |
```

### Лист 6: `Dashboard` (auto-built, formulas only)

Создаётся нашим кодом один раз при инициализации, потом **не трогается** (только raw листы обновляются).

| Секция | Формулы |
|--------|---------|
| Расходы за текущий месяц | `=SUMIFS(Transactions!B:B, ...)` |
| Топ-5 категорий (текущий месяц) | `QUERY` + `SORT` |
| Динамика расходов по месяцам (12 мес) | `SPARKLINE` + `SUMIFS` по month |
| Баланс по счетам | `=SUM(Accounts!B:B)` |
| График по дням (текущий месяц) | встроенный `Chart` из данных Transactions |

### Лист 7: `Monthly` (сводка по месяцам, formula-driven)

```
| month | income | expenses | savings | savings_rate |
```

Строится целиком через `SUMIFS` — app ничего не пишет в этот лист.

### Лист 8: `By_Account` (история по каждому счёту, formula-driven)

```
| month | account_name | income | expenses | balance_change |
```

Через `QUERY(Transactions!..., "SELECT ...")` — pivot по счетам.

---

## Техническая архитектура (уточнённая)

### Путь данных

```
iOS SwiftData
    ↓ SheetsExportService (новый, не SheetsSync)
NestJS /sheets/export endpoint
    ↓ batch valueBatchUpdate
Google Sheets API v4
    ↓
Spreadsheet пользователя
```

### Ключевые решения

**1. Spreadsheet создаётся один раз**
- При первом подключении: NestJS создаёт spreadsheet с нужными листами, форматированием, frozen rows, auto-filter, conditional formatting
- При повторных экспортах — только обновляет данные (clear + rewrite raw листов)

**2. Clear + Rewrite (не Append)**
- Для `Accounts`, `Accounts_Archive`, `Investments`, `Budgets` — полная перезапись при каждом sync
- Для `Transactions` — append только новых (по `millio_id`, которых ещё нет в листе)
- Dashboard и Monthly листы — **никогда не трогаем** после создания

**3. Хранение spreadsheetId**
- Backend хранит `{userId → spreadsheetId, last_sync_at, total_rows}`
- iOS получает ссылку при подключении — показывает в ProfileView

**4. Частота sync**
- При первом подключении: full sync всей истории (фоновая задача)
- При добавлении транзакции в app: incremental append в течение 30 сек (fire-and-forget)
- Ежедневный полный refresh Accounts/Budgets (баланс мог измениться)
- Manual "Обновить сейчас" в ProfileView

**5. Обработка архивных счетов**
- `Card.archivedAt != nil` → попадает в `Accounts_Archive`, не в `Accounts`
- При архивировании счёта в app → incremental update: строка перемещается между листами

---

## UX подключения (рекомендация)

### В ProfileView

```
╔═══════════════════════════════╗
║  Google Таблицы        🟢     ║
║  Подключено · 145 строк       ║
║  Обновлено сегодня в 14:32    ║
║  [Открыть таблицу ↗] [•••]    ║
╚═══════════════════════════════╝
```

Состояния: Не подключено → Подключение... → Первичный sync... (прогресс) → Подключено → Ошибка токена.

### Первый запуск

1. Кнопка «Подключить Google Таблицы»
2. OAuth в SafariViewController
3. Появляется Progress: «Выгружаем историю... 234/891 транзакций»
4. «Готово! Ваша таблица создана» + кнопка «Открыть»

---

## Критические риски (только одностороннего sync)

| Риск | Уровень | Действие |
|------|---------|----------|
| OAuth consent screen verification | 🔴 КРИТИЧНО | Запустить **сейчас**. 2–4 недели. |
| Privacy Policy апдейт | 🔴 КРИТИЧНО | Добавить раздел про Google Sheets opt-in до релиза |
| Пользователь вручную правит Transactions | 🟡 СРЕДНИЙ | Документировать: «ручные правки не синхронизируются обратно» |
| Full sync > 2 МБ payload | 🟡 СРЕДНИЙ | Batch по 500 строк, несколько запросов |
| Token revocation пользователем в Google | 🟡 СРЕДНИЙ | Показать ошибку в ProfileView, re-auth flow |
| Перезапись Dashboard при sync | 🟢 НИЗКИЙ | Dashboard лист не трогаем после создания — только raw листы |

---

## Источники

- [Tiller Money — How Tiller Works](https://tiller.com/how-tiller-works/)
- [Google Sheets API v4 — Batch Update](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets.values/batchUpdate)
- [Google Sheets API — Usage Limits](https://developers.google.com/workspace/sheets/api/limits)
- [Monarch Money CSV Export format](https://help.monarchmoney.com/hc/en-us/articles/4415968251156-Exporting-transactions)
- [NoCodeAPI — Rate Limit Hacks](https://nocodeapi.com/stop-wasting-time-on-api-rate-limits-5-google-sheets-sync-hacks-that-actually-work/)
- [r/personalfinance — Google Sheets templates](https://www.reddit.com/r/personalfinance/wiki/tools/)
