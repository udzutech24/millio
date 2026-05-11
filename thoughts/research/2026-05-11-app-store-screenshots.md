# Research: App Store Screenshots — Screenshot Mode + fastlane snapshot + Remotion

**Date:** 2026-05-11
**Stage:** 1 / Deep Research (read-only)
**Related:** [`specs/2026-05-11-app-store-screenshots.md`](../specs/2026-05-11-app-store-screenshots.md)

## Задача исследования

Нужно автоматически генерировать App Store скриншоты (PNG) и видео-превью (MP4) при обновлении дизайна. Текущие скриншоты устарели, дизайн обновился, нужна воспроизводимая система.

## Findings from codebase

### Структура

**Точки входа:**
- `millioApp.swift` — `@main`, в `init()` загружает `AppRuntimeEnvironment.current()`
- `millio/Core/AppRuntimeEnvironment.swift` — 5 свойств: `isUnitTesting`, `isUITesting`, `isAnyTesting`, определяется по env vars

**UI тест инфра:**
- `millioUITests/millioUITests.swift` — `makeApp()` выставляет `launchEnvironment["MILLIO_UI_TEST_MODE"] = "1"`, Firebase не инициализируется при `isAnyTesting`
- Текущие тесты минимальны: только `testExample()` (скелет) и `testLaunchPerformance()`

**Экраны для скриншотов:**
- `UI/Dashboard/DashboardView.swift` — главный экран
- `UI/Services/Cashflow/` — кэшфлоу
- `UI/Services/Finances/` — финансы
- `UI/Services/Cashback/` — кэшбэк
- `UI/Services/Courses/` — курсы валют
- `UI/Services/Investments/` — инвестиции
- `UI/Profile/` — профиль / backup

**Текущие карточки (7 штук):**
1. "A complete picture of your finances" → Dashboard
2. "Manage all your finances in one place" → Finance
3. "Your finances. At a glance" → Cashflow?
4. "All your cashback. In one place" → Cashback
5. "More than a converter" → Courses (курсы)
6. "Your personal cash flow" → Cashflow
7. "Your data. Under your control" → Profile/Backup

### Существующие паттерны

- `MILLIO_UI_TEST_MODE=1` уже отключает Firebase, CloudKit в тестах — паттерн launch environment уже в коде
- `AppRuntimeEnvironment` — расширяемая структура, легко добавить `isScreenshotMode`
- Fastlane уже настроен (`Fastfile`, `Appfile` с bundle ID и team), но lanes только для TestFlight

### Зависимости

- `fastlane snapshot` (gem, входит в fastlane) — потребует `Snapfile`
- `Remotion` (npm) — отдельный проект вне iOS-репо, для финального рендера карточек
- Симулятор: iPhone 15 Pro (6,1" / 6,7") или iPhone 16 Pro — нужен в Xcode

### Тесты

Существующих snapshot-тестов нет. UI-тест инфра минимальна, но работающая. Новые `XCUIApplication` тесты для screenshot-режима не конфликтуют с текущими.

## Alternatives

### Вариант A: Screenshot Mode в app + fastlane snapshot (чистый iOS)
Добавляем `MILLIO_SCREENSHOT_MODE=1` → app загружает mock-данные → UI-тесты навигируют по экранам → fastlane делает скрины автоматически.
- **Плюсы:** нативно, реальный UI приложения, поддерживает все локали и размеры автоматически
- **Минусы:** карточки (рамка телефона + фон + текст) нужно делать отдельно в Figma/Remotion
- **Трудоёмкость:** M (3-4 дня: mock data + UI tests + Snapfile + Remotion шаблон)

### Вариант B: SwiftUI PreviewSnapshots
Снимать скрины прямо из SwiftUI Preview через `swift-snapshot-testing`.
- **Плюсы:** не нужен симулятор с данными
- **Минусы:** Preview ≠ реальный запуск, сложно с навигацией, нет поддержки нескольких размеров
- **Трудоёмкость:** M, но хуже результат

### Вариант C: Вручную — реальные данные на симуляторе
Заполнить симулятор руками, сделать скрины через Xcode, передать в Remotion.
- **Плюсы:** быстрый старт (сегодня)
- **Минусы:** не воспроизводимо, при каждом обновлении дизайна — руками заново
- **Трудоёмкость:** S сейчас, но ∞ в сумме

## Recommendation

**Выбран:** Вариант A — Screenshot Mode + fastlane snapshot + Remotion для карточек.

**Почему:**
1. `AppRuntimeEnvironment` уже есть — добавить `isScreenshotMode` тривиально
2. fastlane уже настроен — нужно только добавить `Snapfile` и lane
3. Remotion даёт одну команду для финального рендера (PNG карточки + MP4 видео) с любыми изменениями дизайна

**Что учесть при имплементации:**
- Mock-данные должны выглядеть реалистично: реальные суммы, категории, даты — не "Test User", не нули
- `isScreenshotMode` должен подавлять авторизацию/онбординг — app стартует сразу на нужном экране
- Remotion-проект — отдельная папка вне iOS-репо (например, `../Маркетинг/screenshots-remotion/`)
- Порядок: сначала mock data + навигация → скрины raw → потом Remotion оборачивает в карточки
- Локали: EN первый, потом RU — Snapfile поддерживает несколько локалей
