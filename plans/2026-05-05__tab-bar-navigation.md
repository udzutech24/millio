# Plan: Tab Bar Navigation

**Slug:** `tab-bar-navigation`
**Дата:** 2026-05-05
**Размер:** L
**Статус:** НЕ НАЧАТ
**Spec:** [`specs/2026-05-05-tab-bar-navigation.md`](../specs/2026-05-05-tab-bar-navigation.md)

---

## Архитектурная схема

```
RootViewResolver (.ready)
    └── RootTabView                         ← НОВЫЙ файл
            ├── NavigationStack [Финансы]
            │       ├── FinancesMainTabView  ← был private, станет internal
            │       │     └── top: ChipsBar (Курсы, Кешбэк)
            │       ├── push → CoursesView
            │       └── push → CashbackView
            ├── NavigationStack [Динамика]
            │       └── FinanceDynamicsTabView ← был private, станет internal
            ├── FAB [+] (overlay в ZStack)
            │       └── sheet → Income / Expense
            └── NavigationStack [Кэшфлоу]
                    └── CashflowView (без изменений)
```

---

## Фазы

### Фаза 0: Аудит и решения [ ]

**Цель:** зафиксировать все точки изменений до первой строчки кода.

**Задачи:**
- [ ] Прочитать `FinancesView.swift` — убедиться, что `FinancesMainTabView` и `FinanceDynamicsTabView` можно сделать `internal` (нет приватных зависимостей, которые не вынести)
- [ ] Проверить `CashflowView.swift` — убедиться, что история и подписки уже внутри (без изменений таба Кэшфлоу)
- [ ] Решить: Quick Setup banner остаётся на Финансах или убирается совсем?
- [ ] Решить: нужен ли отдельный NavigationStack на каждый таб, или один shared (рекомендую: per-tab)
- [ ] Сверить все тесты, которые ссылаются на `MainAppView`, `ServiceItem`, `MainAppViewModel`

**Выход:** список файлов + строк для изменения (подтверждён).

---

### Фаза 1: Декомпозиция FinancesView [ ]

**Файлы:** `millio/UI/Services/Finances/FinancesView.swift`

**Задачи:**
- [ ] Убрать `private` у `FinancesMainTabView` и `FinanceDynamicsTabView` — сделать `internal`
- [ ] Переименовать внутренний enum `FinancesTab` → `FinancesInternalTab` (во избежание путаницы с `RootTab`)
- [ ] Вынуть `TabView` из `FinancesView.body` — теперь `FinancesView` больше не нужен как контейнер (или превращается в thin wrapper для preview/обратная совместимость тестов — решить в Фазе 0)
- [ ] Заменить `selectedTab = .dynamics` (строка 801) на callback / `AppRouter.selectedTab = .dynamics`
- [ ] Проверить: `FinancesMainTabView` принимает `router` через Environment — не аргументом

**Acceptance checkpoint:**
- `FinancesMainTabView` компилируется как standalone
- `FinanceDynamicsTabView` компилируется как standalone
- `FinancesView` можно удалить без ошибок (или остаётся пустым wrapper)

---

### Фаза 2: RootTab + AppRouter [ ]

**Файлы:**
- `millio/UI/Main/RootTab.swift` ← НОВЫЙ
- `millio/Core/Navigation/AppRouter.swift`

**Задачи:**

`RootTab.swift`:
```swift
enum RootTab: String, CaseIterable {
    case finances
    case dynamics
    case cashflow
}
```

`AppRouter.swift` — добавить:
```swift
var selectedTab: RootTab = .finances
var pendingFABAction: FABAction? = nil  // .income / .expense

enum FABAction { case income, expense }
```

- [ ] `RootTab` enum создан
- [ ] `AppRouter.selectedTab` добавлен
- [ ] `AppRouter.pendingFABAction` добавлен

**Acceptance checkpoint:** компилируется без предупреждений.

---

### Фаза 3: RootTabView [ ]

**Файлы:**
- `millio/UI/Main/RootTabView.swift` ← НОВЫЙ
- `millio/UI/Main/RootTabBar.swift` ← НОВЫЙ (кастомный таб бар)

**Задачи:**

`RootTabView.swift`:
- [ ] `ZStack`: контент табов + `RootTabBar` в bottom overlay
- [ ] `@State var selectedTab: RootTab = .finances`
- [ ] `@State var showIncomeSheet`, `showExpenseSheet` — для FAB
- [ ] `@StateObject var cashflowVM` — инициализируется один раз здесь (передаётся в sheets)
- [ ] Таб Финансы: `NavigationStack` → `FinancesMainTabView` + `ChipsBar` вверху
- [ ] Таб Динамика: `NavigationStack` → `FinanceDynamicsTabView`
- [ ] Таб Кэшфлоу: `NavigationStack` → `CashflowView`
- [ ] Sheets: `CashflowIncomeTransactionSheet`, `CashflowExpenseTransactionSheet`
- [ ] `onChange(of: router.pendingFABAction)` — открыть нужный sheet
- [ ] `onChange(of: router.selectedTab)` — синхронизировать local state

`RootTabBar.swift`:
- [ ] Кастомный `HStack` с 4 элементами (Финансы, Динамика, [+], Кэшфлоу)
- [ ] FAB [+] по центру: увеличенная кнопка, `confirmationDialog` → income/expense
- [ ] Иконки: `creditcard`, `chart.line.uptrend.xyaxis`, `plus.circle.fill`, `arrow.left.arrow.right`
- [ ] Анимация переключения: `withAnimation(.easeInOut)`
- [ ] Тёмный фон таб бара с `ultraThinMaterial` или `Color.black.opacity(0.52)`

**Acceptance checkpoint:** Tab bar рендерится, переключение табов работает, FAB открывает sheets.

---

### Фаза 4: ChipsBar на Финансах [ ]

**Файлы:**
- `millio/UI/Main/ChipsBar.swift` ← НОВЫЙ (или inline в FinancesMainTabView)
- `millio/UI/Services/Finances/FinancesView.swift`

**Задачи:**
- [ ] Горизонтальный `HStack` с чипами Курсы + Кешбэк
- [ ] Тап → push `CoursesView` / `CashbackView` в NavigationStack таба Финансы
- [ ] Чипы: иконка + короткое название + (опционально) живое значение для Курсы
- [ ] Локализация через `Localizable.xcstrings` (`tab.chip.courses`, `tab.chip.cashback`)
- [ ] Профиль-иконка в `toolbar` (.navigationBarLeading)

**Acceptance checkpoint:** чипы отображаются, навигация работает, локализация покрыта (RU/EN).

---

### Фаза 5: Deep links и виджет [ ]

**Файлы:**
- `millio/UI/Main/RootTabView.swift`
- `millio/Core/Navigation/AppRouter.swift`

**Маппинг pending-флагов → действия:**

| Флаг | Действие |
|---|---|
| `pendingOpenConverterService` | `selectedTab = .finances` + push CoursesView |
| `pendingOpenMainExpenseSheet` | `pendingFABAction = .expense` |
| `pendingOpenMainIncomeSheet` | `pendingFABAction = .income` |
| `pendingOpenCashflowExpense` | `selectedTab = .cashflow` + appState.pendingOpenCashflowExpense = true |
| `pendingOpenCashflowIncome` | `selectedTab = .cashflow` + appState.pendingOpenCashflowIncome = true |
| `pendingOpenCashflowHistory` | `selectedTab = .cashflow` + appState.pendingOpenCashflowHistory = true |

**Задачи:**
- [ ] `RootTabDeepLinkHandler` в `RootTabView.swift` (заменяет `MainWidgetDeepLinkHandler`)
- [ ] Все 6 флагов обработаны
- [ ] `.onOpenURL` работает через `AppWidgetDeepLinkHandler` (без изменений)

**Acceptance checkpoint:** виджет «добавить расход» открывает FAB sheet. Виджет «курсы» переключает Финансы и открывает Курсы.

---

### Фаза 6: Wire up в RootViewResolver [ ]

**Файлы:** `millio/Core/Navigation/RootViewResolver.swift`

**Задачи:**
- [ ] Заменить `MainAppView(router: router)` → `RootTabView(router: router)` на строке `.ready`
- [ ] Убедиться, что `router.popToRoot()` сбрасывает и NavigationPath каждого таба

**Acceptance checkpoint:** приложение запускается, всё отображается корректно.

---

### Фаза 7: Cleanup [ ]

**Файлы к удалению:**
- `millio/UI/Main/MainAppView.swift`
- `millio/UI/Main/MainAppViewModel.swift`
- `millio/UI/Main/ServiceItem.swift`
- `millio/UI/Main/MainQuickActionsLayout.swift`
- `millio/UI/Main/MainLocalization.swift` (проверить, нет ли переиспользования)

**Задачи:**
- [ ] Проверить каждый файл на наличие символов, которые используются вне `UI/Main/`
- [ ] Удалить или заменить
- [ ] Убрать из `Localizable.xcstrings` ключи `main.*`, которые больше не нужны
- [ ] Проверить `FinancesView.swift` — если стал пустым wrapper → удалить

---

### Фаза 8: Тесты и self-audit [ ]

**Задачи:**
- [ ] Найти все тесты с `MainAppView`, `ServiceItem`, `MainAppViewModel` → обновить или удалить
- [ ] Добавить тесты для `RootTabDeepLinkHandler` (unit)
- [ ] Прогнать `xcodebuild test` — все зелёные
- [ ] Self-audit по acceptance criteria из spec
- [ ] Impact analysis: регрессии в Финансах, Кэшфлоу, Deep links, Widget

---

## Журнал

| Дата | Фаза | Итог |
|------|------|------|
| — | — | — |

---

## Риски

| Риск | Вероятность | Митигация |
|------|-------------|-----------|
| `FinancesMainTabView` имеет скрытые приватные зависимости | Средняя | Фаза 0 — аудит до кода |
| `selectedTab` в `AppRouter` создаёт retain cycle | Низкая | `@Observable` + `@Bindable` — стандартный паттерн |
| Кастомный таб бар ломает safe area на iPhone SE / Pro Max | Средняя | Тестировать на обоих симуляторах |
| Widget deep links: race condition pendingFlag vs tab switch | Средняя | Устанавливать selectedTab перед флагом, использовать `Task { @MainActor }` |
| `NavigationPath.popToRoot()` — нужен per-tab path, не shared | Высокая | `@State var financesPath`, `dynamicsPath`, `cashflowPath` отдельно |
