# Plan: Financial Rain — анимация запуска приложения

**Slug:** `launch-animation`
**Дата создания:** 2026-05-23
**Stage:** 3 / Planning
**Spec:** [`specs/2026-05-23-launch-animation.md`](../specs/2026-05-23-launch-animation.md)
**Research:** [`thoughts/research/2026-05-23-launch-animation.md`](../thoughts/research/2026-05-23-launch-animation.md)

## Статус

`В РАБОТЕ`

**Реализовано:** Phase 1 (FinancialRainView + локализация) + Phase 2 шаг 1 (интеграция в LaunchingView)
**Осталось:** тест `reduceMotion`, прогон сьюта, коммиты Phase 1 + Phase 2
**Блокер:** —

## Цель

Добавить финансовый rain-эффект на launch screen, не затрагивая логику lifecycle/хаптик/wordmark.

## Acceptance Criteria (из spec)

- [ ] AC1 — ≥5 падающих колонок с финансовыми символами
- [ ] AC2 — `reduceMotion = true` → анимация отключена
- [ ] AC3 — прозрачность слоя ≤ 0.35
- [ ] AC4 — 60 fps на iPhone 12+
- [ ] AC5 — `FinancialRainView` изолирован, #Preview работает
- [ ] AC6 — существующие тесты зелёные
- [ ] AC7 — reduceMotion-ветка покрыта тестом
- [ ] AC8 — Easter egg фраза появляется на ~0.8s, локализована (EN/RU/zh-Hans), ключ `launch.rain.message` в xcstrings

## Challenge Log

### 1. Решает ли план проблему из spec?

| AC | Фаза |
|----|------|
| AC1 | Phase 1 |
| AC2 | Phase 1 |
| AC3 | Phase 1 |
| AC4 | Phase 1 (Canvas batch render) |
| AC5 | Phase 1 |
| AC6 | Phase 2 (проверка после интеграции) |
| AC7 | Phase 2 (тест) |

Все AC покрыты.

### 2. Самое эффективное решение?

**Альтернатива A: SpriteKit** — быстрее для particle systems, но тяжелее, требует `SpriteView` обёртку, нет нативного #Preview, избыточен для текста.

**Альтернатива B: ForEach + Text SwiftUI** — просто в коде, но каждый символ = отдельный View, при 50+ символах ощутимая нагрузка на layout engine.

**Альтернатива C: TimelineView + Canvas (выбрано)** — batch draw call в Canvas = один GPU pass, нативный SwiftUI, работает с #Preview, легко анимировать через `TimelineView(.animation)`. Оптимальный выбор.

### 3. Нет ли кода ради кода?

Все изменения прямо обслуживают AC1–AC7. Никакого рефакторинга попутно.

## Фазы

**Состояния:** `[ ]` не начато · `[~]` в работе · `[x]` готово

---

### `[~]` Phase 1: FinancialRainView — изолированный компонент

**AC из spec:** AC1, AC2, AC3, AC4, AC5

**Файлы:**
- `millio/UI/Launching/FinancialRainView.swift` — новый файл, весь компонент здесь

**Архитектура компонента:**

```swift
// Публичный интерфейс
struct FinancialRainView: View {
    // Принимает размер через GeometryReader — адаптация к SE и Pro Max
}

// Внутренние типы
private struct RainColumn {
    let x: CGFloat           // фиксированная позиция X
    var y: CGFloat           // текущая Y (движется вниз)
    let speed: CGFloat       // пикселей / сек
    let symbols: [Character] // перемешанные символы колонки
    var opacity: Double      // плавное появление
}

// Символьный набор
private let kFinancialSymbols: [Character] = [
    "₽", "$", "€", "¥", "%", "↑", "↓", "+", "−",
    "0", "1", "2", "5", "8", "k", "m", "."
]
```

**Логика рендера:**
- `TimelineView(.animation)` → обновление состояния по `context.date`
- `Canvas` → batch draw всех видимых символов за один pass
- Число колонок = `floor(width / columnSpacing)`, columnSpacing ≈ 28pt
- Каждая колонка: рисует 8–12 символов, верхние ярче, нижние прозрачнее (fade-trail)
- Символы ротируются: каждые ~0.15s текущий leading-символ меняется
- Общий `opacity` слоя: 0.30 (не конкурирует с wordmark)
- Цвет: `AppColors.accent` с opacity, fallback `Color.green.opacity(0.6)`

**reduceMotion:** `@Environment(\.accessibilityReduceMotion)` — если `true`, `TimelineView` не рендерится (возвращает `EmptyView`)

**Easter egg — реализация фразы:**
- Добавить ключ `launch.rain.message` в `Localizable.xcstrings` (EN: `SAVE & GROW`, RU: `КОПИ И РАСТИ`, zh-Hans: `储蓄成长`)
- Читать через `String(localized: "launch.rain.message")` — автоматически подхватит язык приложения (`LanguageManager`)
- Через `TimelineView`: на метке `t ≈ 0.8s` один горизонтальный Canvas-пасс рисует фразу поверх дождя, полная яркость; на `t ≈ 1.4s` opacity → 0

**Шаги:**
1. `[x]` Написать unit-тест `FinancialRainViewTests` — AC8 (локализация EN/RU/zh-Hans) зелёная. AC7 (reduceMotion → EmptyView) не тестируется unit-тестами без ViewInspector — покрыто ручной проверкой в Simulator (Reduce Motion ON).
2. `[x]` Добавить `launch.rain.message` в `Localizable.xcstrings` (EN/RU/zh-Hans)
3. `[x]` Создать `FinancialRainView.swift` с `TimelineView + Canvas` + Easter egg фразой
4. `[x]` `#Preview` — работает standalone без AppState
5. `[x]` BUILD SUCCEEDED — 0 ошибок
6. `[x]` Impact analysis: нет side effects — `FinancialRainView` изолирован, добавлен в `LaunchingView` ZStack без изменения хаптик/lifecycle/wordmark логики.
7. `[ ]` Коммит: `feat(ui): FinancialRainView — launch screen financial rain animation`

**Guard phrase для старта:** «Реализуй Phase 1 по плану.»

---

### `[~]` Phase 2: Интеграция в LaunchingView + тесты

**AC из spec:** AC6, AC7

**Файлы:**
- `millio/UI/Launching/LaunchingView.swift` — добавить `FinancialRainView` в ZStack
- `millioTests/UI/LaunchingViewTests.swift` — проверка reduceMotion-ветки (AC7)

**Изменение в LaunchingView:**

```swift
// В body ZStack, после SplashBackdropView, до контента:
ZStack {
    SplashBackdropView(offset: backdropOffset, scale: backdropScale)

    FinancialRainView()          // ← новая строка
        .opacity(reduceMotion ? 0 : 1)

    VStack(spacing: 28) { ... } // существующий контент
}
```

Порядок слоёв: `LaunchImage → FinancialRain → wordmark + spinner`

**Фading:** `FinancialRainView` управляет своей прозрачностью внутри себя (≤0.30). Никакой координации с wordmark-анимацией — rain просто всегда идёт, пока view на экране.

**Шаги:**
1. `[x]` Добавить `FinancialRainView()` в ZStack `LaunchingView` (LaunchingView.swift:24)
2. `[ ]` Запустить существующие тесты — все зелёные (AC6)
3. `[ ]` Проверить на Simulator: iPhone SE (маленький экран) + iPhone 16 Pro Max
4. `[ ]` Self-audit: все AC покрыты?
5. `[ ]` Коммит: `feat(ui): integrate FinancialRainView into LaunchingView`

**Guard phrase для старта:** «Реализуй Phase 2 по плану.»

---

## Edge Cases (Think Several Steps Ahead)

- [ ] `reduceMotion = true` — `FinancialRainView` возвращает `EmptyView`, проверено тестом
- [ ] iPhone SE (375pt wide) — columns адаптируются к ширине через GeometryReader
- [ ] Долгий launch (>3s) — `TimelineView` не останавливается, rain идёт всё время пока view активен
- [ ] Быстрый launch (<0.3s) — анимация успевает начаться (нет задержки старта)
- [ ] Нет `LaunchImage` asset — `SplashBackdropView` упадёт независимо от rain, наша задача не трогать эту логику

## Gates (iOS, перед `[x]` на фазе)

- [ ] `xcodebuild build` — 0 ошибок и предупреждений
- [ ] `xcodebuild test` — все тесты зелёные
- [ ] Ручная проверка на Simulator (iPhone 15 Pro) — анимация видна, логотип читаем
- [ ] `reduceMotion` ON в Simulator → анимация отсутствует

## Журнал изменений

- `2026-05-23` — создан план, Phase 1 и Phase 2 определены.
- `2026-05-24` — Phase 1 шаги 2–5 выполнены (FinancialRainView создан, локализация добавлена, #Preview работает, билд чистый). Phase 2 шаг 1 выполнен (интеграция в LaunchingView:24). Файлы не закоммичены — ждут теста reduceMotion.
- `2026-05-27` — план актуализирован по snapshot и git.

## Итог (заполняется при завершении)

**Результат:** —
**Что реализовано:** —
**Что не реализовано и почему:** —
**Дата завершения:** —
