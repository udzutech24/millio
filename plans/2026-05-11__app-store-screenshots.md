# Plan: App Store Screenshots — автоматическая генерация

**Slug:** `app-store-screenshots`
**Дата создания:** 2026-05-11
**Status:** В РАБОТЕ
**Spec:** [`specs/2026-05-11-app-store-screenshots.md`](../specs/2026-05-11-app-store-screenshots.md)

---

## Phase 1 — Screenshot Mode в iOS [x]

**Файлы:** `AppRuntimeEnvironment.swift`, `millioApp.swift`, `ScreenshotDataSeeder.swift` (новый)

- [x] Добавить `isScreenshotMode` и `screenshotTarget` в `AppRuntimeEnvironment`
- [x] Создать `millio/Core/App/ScreenshotDataSeeder.swift` с mock-данными
- [x] В `millioApp.swift` init(): при `isScreenshotMode` → lifecycle=.ready, isAppLocked=false
- [x] В `millioApp.swift` `.task {}`: при `isScreenshotMode` → запустить seeder + навигация на target

## Phase 2 — UI Tests для fastlane snapshot [x]

**Файлы:** `millioUITests/ScreenshotTests.swift` (новый)

- [x] Создать `ScreenshotTests.swift` — 7 тестов, по одному на экран
- [x] Каждый тест: `setupSnapshot(app)`, запуск с MILLIO_SCREENSHOT_MODE + MILLIO_SCREENSHOT_TARGET, wait, `snapshot("screen_name")`

## Phase 3 — fastlane Snapfile + lane [x]

**Файлы:** `fastlane/Snapfile` (новый), `fastlane/Fastfile` (обновление)

- [x] Создать `Snapfile`: устройства, локали, путь к скринам, output_directory
- [x] Добавить lane `screenshots` в `Fastfile`

## Phase 4 — Remotion проект [x]

**Папка:** `../Маркетинг/screenshots-remotion/`

- [x] `package.json`, `remotion.config.ts`
- [x] `src/Card.tsx` — компонент одной карточки (фон + телефон + заголовок)
- [x] `src/Video.tsx` — видео-превью (7 карточек × 4s = ~28s)
- [x] `src/index.ts` — регистрация композиций

---

## Журнал

- 2026-05-11: research + spec + plan + реализация всех фаз
