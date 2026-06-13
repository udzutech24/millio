# Спринт 1 — «Монетизация перестаёт течь»
**Создан:** 2026-05-31 · **Статус:** НЕ НАЧАТ · **Источник:** аудит 20 точек роста + оценка Максима

## Контекст

Проведён глубокий аудит приложения (8 агентов): архитектура, UX/HIG, монетизация, тесты, локализация, производительность, ASO. Максим приоритизировал 20 точек роста по Score = Impact × (6−Effort) × Risk. Спринт 1 закрывает главную бизнес-боль: PRO-ценность отдаётся бесплатно, а продавать не умеем.

Полный бэклог: см. артефакты сессии 2026-05-31 (аудит + оценка Максима).

---

## Спринт 1 — задачи (приоритет по зависимостям)

### [ ] #5 — Paywall full-screen sheet вместо alert
**Score: 60 · Исполнитель: Александр · Делать ПЕРВЫМ**

Во всех точках срабатывания (`FinanceAddAccountView`, `InvestmentEditorView`, `CashbackView`, `FinanceCreateViews`) paywall — это `UIAlertController` с двумя кнопками. Без объяснения ценности, без benefits, без trial CTA.

**Что сделать:**
- Единый `PaywallSheet` с contextual заголовком («Добавь безлимитные карты»)
- 3 key benefits + сравнение Free/PRO таблицей
- Кнопка trial activation (7 дней) как primary CTA
- Заменить все alert-точки на sheet
- Открывается через `AppRouter` / Environment

**Зависимость:** этот пункт делать ДО закрытия флагов (#2). Без продающего экрана закрытие = стена без двери.

**Файлы:** `millio/UI/Services/Finances/FinanceAddAccountView.swift`, `millio/UI/Cashflow/CashbackView.swift`, `millio/UI/Investments/InvestmentEditorView.swift`, `millio/UI/Subscriptions/SubscriptionView.swift`

**Метрика:** Конверсия paywall impression → trial start +20%

---

### [ ] #2 — Закрыть 5 beta-флагов PRO
**Score: 80 · Исполнитель: Александр (код) + решение Алексея (grandfathering)**

5 флагов в `AppState.swift:204–211` (`false`) открывают для Free: криптоконвертер, все кэшбэк-карты, акции и крипто-активы в финансах, лимиты на тикеры.

**Решение по grandfathering:** Вариант C — анонс + промо
- За 2 недели до закрытия — in-app пуш «фича становится PRO, успей оформить по промо MILLIO3M»
- Бьётся с активной промо-стратегией `2026-05-16__launch-promo-strategy.md`
- Минимум негатива, конвертирует привыкших

**Что сделать:**
- Добавить in-app banner/push с анонсом (за 14 дней)
- Через 14 дней: сменить 5 флагов `false → true` в `AppState.swift:204–211`
- Убедиться, что `EntitlementPolicy` корректно блокирует при `true`

**Зависимость:** делать ПОСЛЕ #5 (paywall). Сначала экран, потом замок.

**Файлы:** `millio/Core/AppState/AppState.swift:204-211`, `millio/Core/Features/EntitlementPolicy`, `docs/monetization-free-pro.md`

**Метрика:** Конверсия Free→PRO +15% за 30 дней после закрытия флагов

---

### [ ] #1 — Верификация launch-recovery + доказательные тесты
**Score: 64 · Исполнитель: Денис**

`LaunchRecoveryPolicy.evaluate()` вызывается на старте (`millioApp.swift:792`), план `2026-05-10__launch-recovery-hardening.md` имеет статус РЕАЛИЗОВАН. НО: release-blocker из аудита — нет доказательных тестов, что сценарий «пустой store + найден backup» реально работает.

**Что сделать:**
- UI-тест: пустой store + существующий backup → проверить, что `RestoreView` открывается
- Убедиться в покрытии AC1–AC6 из плана hardening
- Починить raw RU literals в `RestoreView` (release-blocker для zh-Hans)

**Файлы:** `millio/Core/Backup/LaunchRecoveryPolicy.swift`, `millioTests/Core/`, `millio/UI/Backup/RestoreView.swift`

**Метрика:** 0 crash-репортов «потеря данных после переустановки»; сценарий покрыт UI-тестом

---

### [ ] #9 — Tap target ≥44pt в DashboardView
**Score: 45 · Исполнитель: Александр · Дёшево, App Review-гигиена**

Кнопки профиля (34×34) и toolbar-иконки (38×38) в `DashboardView.swift:130,142,152` нарушают HIG.

**Что сделать:**
- `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())` на кнопки профиля и toolbar
- Проверить Accessibility Inspector — 0 нарушений

**Файлы:** `millio/UI/Dashboard/DashboardView.swift:130,142,152`

**Метрика:** Xcode Accessibility Inspector — 0 нарушений tap target

---

## Полный приоритизированный бэклог (спринты 2-4)

### Спринт 2 — «Trial конвертирует, zh-Hans не стыдный»
- [ ] **#6** Trial urgency — sticky banner с таймером + offboarding modal при истечении
- [ ] **#8** Онбординг от ценности — value-слайд перед настройками + in-app trial activation на шаге summary
- [ ] **#14** DateFormatter с локалью — централизованная фабрика, 8 файлов с хардкодом
- [ ] **#11** App Store скриншоты zh-Hans → Nova

### Спринт 3 — «Вирусность и UX-долг»
- [ ] **#12** Виджет «какой картой платить» — Small/Medium, топ-3 карты по кэшбэку
- [ ] **#10** Swipe-to-delete в истории транзакций
- [ ] **#3** Cashflow fetch с предикатами (после мержа `feature/finance-chart-history`)
- [ ] **#15** Plural forms EN/RU для ключей с `%lld`

### Спринт 4 — «Доступность и качество кода»
- [ ] **#16** UI-тесты: 5 критических сценариев с assertions
- [ ] **#17** Haptics на дашборде (long-press, удаление виджета, backup success)
- [ ] **#18** VoiceOver: accessibilityLabel + accessibilityHint на DashboardView

### Бэклог (фоном / линтером, не планировать в спринт)
- [ ] **#13** 1300 нарушений токенов типографики — SwiftLint-правило + постепенная замена
- [ ] **#4** God-объекты (декомпозиция FinanceDynamicsViewModel) — только при касании файла
- [ ] **#7** Singleton-эпидемия (219 .shared) — системный рефакторинг, отдельный большой цикл

### Стратегический бэклог (после стабилизации монетизации)
- [ ] **#19** In-app referral loop — deep link, 30 дней PRO за реферал
- [ ] **#20** Live Activity (дневной лимит расходов в Dynamic Island) + App Clip (конвертер валют)

---

## Оценочная таблица (полная, от Максима)

| # | Пункт | Imp | Eff | Risk | Score |
|---|-------|-----|-----|------|-------|
| 2 | Закрыть beta-флаги PRO | 5 | 2 | 4 | **80** |
| 1 | Launch-recovery верификация | 4 | 2 | 4 | **64** |
| 5 | Paywall full-screen sheet | 5 | 3 | 4 | **60** |
| 3 | Fetch предикаты (Cashflow) | 4 | 3 | 4 | **48** |
| 14 | DateFormatter локаль zh-Hans | 3 | 2 | 4 | **48** |
| 9 | Tap target ≥44pt | 3 | 1 | 3 | **45** |
| 6 | Trial urgency | 4 | 3 | 3 | **36** |
| 8 | Онбординг от ценности | 4 | 3 | 3 | **36** |
| 11 | App Store скриншоты zh-Hans | 3 | 2 | 3 | **36** |
| 10 | Swipe-to-delete | 3 | 1 | 2 | **30** |
| 12 | Виджет «какой картой платить» | 5 | 4 | 2 | **20** |
| 15 | Plural forms EN/RU | 2 | 2 | 2 | **16** |
| 19 | In-app referral | 4 | 4 | 2 | **16** |
| 16 | UI-тесты с assertions | 2 | 3 | 3 | **18** |
| 17 | Haptics на дашборде | 2 | 1 | 1 | **10** |
| 4 | God-объекты декомпозиция | 3 | 5 | 4 | **12** |
| 13 | Токены типографики | 2 | 4 | 2 | **8** |
| 18 | VoiceOver / accessibilityLabel | 2 | 4 | 2 | **8** |
| 7 | Singleton-эпидемия | 2 | 5 | 3 | **6** |
| 20 | Live Activity / App Clip | 3 | 5 | 1 | **3** |

---

## Журнал

- **2026-05-31** — Создан по итогам аудита 8 агентов + приоритизации Максима. Grandfathering: выбран Вариант C (анонс + промо). Реализацию начнём в Claude Code.
