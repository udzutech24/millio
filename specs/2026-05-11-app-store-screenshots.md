# Spec: App Store Screenshots — автоматическая генерация

**Date:** 2026-05-11
**Status:** РЕАЛИЗУЕТСЯ
**Research:** [`thoughts/research/2026-05-11-app-store-screenshots.md`](../thoughts/research/2026-05-11-app-store-screenshots.md)
**Plan:** [`plans/2026-05-11__app-store-screenshots.md`](../plans/2026-05-11__app-store-screenshots.md)

## WHAT — что делаем

Система автоматической генерации App Store скриншотов и видео-превью:
1. **Screenshot Mode** в iOS-приложении — запуск с mock-данными, без авторизации
2. **fastlane snapshot** — автоматический захват 7 экранов в 2 размерах и 2 локалях
3. **Remotion** — финальный рендер карточек (PNG) и видео-превью (MP4)

## WHY — зачем

При каждом обновлении дизайна нужно пересобирать все скриншоты. Ручной процесс занимает ~полдня. Автоматизация сократит это до одной команды `fastlane screenshots`.

## Экраны (7 карточек EN/RU)

| # | Экран | Заголовок EN | Заголовок RU |
|---|-------|-------------|-------------|
| 1 | Finances (accounts) | A complete picture of your finances | Полная картина ваших финансов |
| 2 | Finances (dynamics chart) | Your finances. At a glance | Ваши финансы. Одним взглядом |
| 3 | Cashflow | Your personal cash flow | Личный денежный поток |
| 4 | Courses (converter) | More than a converter | Больше, чем конвертер |
| 5 | Cashback | All your cashback. In one place | Весь кэшбэк. В одном месте |
| 6 | Dashboard | Track everything. In one app | Всё под контролем. В одном приложении |
| 7 | Backup | Your data. Under your control | Ваши данные. Под вашим контролем |

## Mock-данные (реалистичные)

### Cards
- Credit Card A Bank: credit, баланс -125 USD, лимит 1500
- My Debit Card: debit, баланс 87 002 USD
- Local Cash: local, баланс 11 200 USD

### Investments
- AAPL: 7 акций, цена покупки 183 USD, текущая 257.44 USD

### CashflowTransactions
- Income: +1 000 USD (январь 2026)
- Expense: -125 USD (январь 2026)

### Cashback categories
- Pharmacies 7%, Car sharing 6%, Taxi 5%, Auto services 5%, Air tickets 5%, Healthcare 5%, Transport 5%, Train tickets 4%

## Screenshot Mode

Запуск через env vars:
- `MILLIO_SCREENSHOT_MODE=1` — включает режим
- `MILLIO_SCREENSHOT_TARGET=finances|dynamics|cashflow|courses|cashback|dashboard|backup`

Поведение:
- Firebase не инициализируется
- Авторизация пропускается → lifecycle = .ready сразу
- AppLock пропускается
- DataSeeder вставляет mock-данные в SwiftData context
- AppRouter навигирует на target-экран

## Acceptance Criteria

- [ ] `MILLIO_SCREENSHOT_MODE=1` — приложение стартует без авторизации с mock-данными
- [ ] 7 скринов захватываются через `bundle exec fastlane screenshots`
- [ ] Скрины для iPhone 16 Pro Max (6.7") и iPhone 15 Plus (6.5")
- [ ] Локали: EN и RU
- [ ] Remotion рендерит карточку (PNG) и видео-превью (MP4 30s)
- [ ] Mock-данные выглядят реалистично
