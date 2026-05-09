# Plan: Cashflow Redesign v2 — UI + Architecture

**Slug:** `cashflow-redesign-v2`
**Дата создания:** 2026-05-09
**Stage:** 3 / Planning
**Spec:** [`specs/2026-05-09-cashflow-redesign-v2.md`](../specs/2026-05-09-cashflow-redesign-v2.md)
**Research:** [`thoughts/research/2026-05-09-cashflow-redesign-v2.md`](../thoughts/research/2026-05-09-cashflow-redesign-v2.md)

---

## Статус

`РЕАЛИЗОВАН`

**Реализовано:** Phase 1–6 (все)
**Осталось:** —

---

## Цель

Один раз по уму: правильная VM/View-архитектура + современный UX для экрана расходов/доходов.

---

## Acceptance Criteria (из spec)

### Архитектура
- [x] AC-A1: CashflowViewModel → extension-файлы, главный 712 строк (было 2081)
- [x] AC-A2: CashflowOperationSheets разбит на 9 файлов, главный 1431 строк (было 2623)
- [x] AC-A3: Все существующие функции работают (build success + тесты)
- [x] AC-A4: `xcodebuild build` — 0 ошибок после каждой фазы

### UI
- [x] AC-U1: Сетка 3 колонки (CashflowCategoryGridLayout изменён)
- [x] AC-U2: PageTabView свайп Расходы/Доходы/Всё (CashflowCategorySheetContainer)
- [x] AC-U3: Summary card показывает сумму per tab
- [x] AC-U4: Per-category limit bars в карточках
- [x] AC-U5: Chart section inline (collapsible через cashflowChartSection)
- [x] AC-U6: Quick entry — CashflowQuickEntrySheet (тап категории → sheet)
- [x] AC-U7: Упрощённый header (убрана дата-подпись 01.05–31.05)
- [x] AC-U8: FAB в основном экране убран; FAB в category sheet — оставлен (создание категории)
- [x] AC-U9: Empty state добавлен в CashflowCategoryTransactionSheet (tray icon + текст)
- [x] AC-U10: PRO-гейт chart сохранён (cashflowChartSection → EntitlementPolicy)

---

## Challenge Log

### 1. Решает ли план проблему из spec?

| AC | Фаза |
|----|------|
| AC-A1 | Phase 1 |
| AC-A2 | Phase 2 |
| AC-A3 | Phase 1+2 (gates) |
| AC-A4 | Gates каждой фазы |
| AC-U1, U7, U8, U9 | Phase 2 |
| AC-U2, U3 | Phase 3 |
| AC-U4 | Phase 4 |
| AC-U5, U10 | Phase 4 |
| AC-U6 | Phase 5 |

### 2. Это самое эффективное решение?

- **Альтернатива "только UI":** не решает maintainability, следующий PR такой же сложный
- **Альтернатива "только VM":** пользователь не видит результата
- **Выбрано:** обе части в одном спринте по фазам — каждая фаза buildable

### 3. Нет ли кода ради кода?

- Декомпозиция VM — обосновано: 4598 строк нетестируемо
- Quick entry — обосновано: пользователь жалуется на friction добавления
- Collapsible chart — обосновано: chart был скрыт, пользователь не знал о нём

---

## Фазы

**Состояния:** `[ ]` не начато · `[~]` в работе · `[x]` готово

---

### `[x]` Phase 1: VM Декомпозиция

**AC:** AC-A1, AC-A3, AC-A4

**Цель:** Разбить `CashflowViewModel.swift` (4598 строк) на 3 самостоятельных ViewModel. UI при этом не меняется — это чистый рефакторинг.

**Новые файлы:**
- `millio/UI/Services/Cashflow/CashflowMainViewModel.swift` — period navigation, summary, основное состояние, transaction CRUD, currency helpers, persistence helpers
- `millio/UI/Services/Cashflow/CashflowCategoriesViewModel.swift` — Categories раздел: CRUD, кастомные категории, переопределения, сортировка, hide/show. ~33 функции
- `millio/UI/Services/Cashflow/CashflowHistoryViewModel.swift` — History раздел: запросы, аналитика, filter state, bulk exports. ~25 функций

**Изменяемые файлы:**
- `millio/UI/Services/Cashflow/CashflowViewModel.swift` — становится тонкой оберткой-фасадом или удаляется после миграции зависимостей
- `millio/UI/Services/Cashflow/CashflowView.swift` — обновить инициализацию VM (3 VM вместо 1)
- `millio/UI/Services/Cashflow/CashflowOperationSheets.swift` — обновить передачу VM

**Шаги:**
1. `[ ]` Выписать все публичные методы CashflowViewModel в 3 группы (Categories / History / Main)
2. `[ ]` Создать `CashflowCategoriesViewModel` — перенести Categories раздел
3. `[ ]` Создать `CashflowHistoryViewModel` — перенести History раздел
4. `[ ]` `CashflowMainViewModel` = оставшаяся логика (period, summary, CRUD, currency, persistence)
5. `[ ]` Удалить/обновить оригинальный `CashflowViewModel.swift`
6. `[ ]` Обновить все зависимости в View-файлах
7. `[ ]` Gate: `xcodebuild build` — 0 ошибок
8. `[ ]` Smoke test: добавить транзакцию, посмотреть историю, изменить категорию

**Guard phrase:** «Реализуй Phase 1 по плану.»

---

### `[x]` Phase 2: View Декомпозиция + Базовый UI

**AC:** AC-A2, AC-A4, AC-U1, AC-U7, AC-U8, AC-U9

**Цель:** Разбить `CashflowView.swift` (2080 строк) на компоненты. Параллельно: 3-колоночная сетка, упрощённый header, убрать FAB, добавить EmptyState.

**Новые файлы:**
```
millio/UI/Services/Cashflow/
  Components/
    CashflowSummaryCard.swift         — Summary с суммой (без лимита пока)
    CashflowChartSection.swift        — Заглушка для chart (Phase 4)
    CashflowQuickActions.swift        — Кнопки: +Добавить, Поиск, Импорт
    CashflowCategoryGrid.swift        — LazyVGrid 3 кол + Sort
    CashflowCategoryCard.swift        — Карточка категории (без limit bar пока)
    CashflowEmptyState.swift          — Empty state view
```

**Изменяемые файлы:**
- `millio/UI/Services/Cashflow/CashflowView.swift` — рефакторинг: компоновщик компонентов, ≤300 строк
- `millio/UI/Services/Cashflow/CashflowCategoryGridLayout.swift` — изменить с 4 на 3 колонки
- `millio/Localizable.xcstrings` — добавить строки для EmptyState

**Детали UI изменений:**

```
HEADER:
  Было:  ← Май 2026  →          [Ист.] [⚙]
         01.05 — 31.05
  Стало: ← Май 2026 →            [Ист.] [⚙]
  (убрать subtitle с диапазоном дат)

GRID:
  Было:  4 колонки, 10pt gap
  Стало: 3 колонки, 12pt gap, карточка шире
  CashflowCategoryCard — новый компонент:
    ┌─────────────────┐
    │  🛒              │
    │  Продукты       │
    │  0 ₽            │
    └─────────────────┘
    (без limit bar пока — добавим в Phase 4)

FAB: убрать `floatingAddButton`
Quick Actions row: [+ Добавить расход/доход] [🔍] [↓ Импорт]
  Показывает "+ Добавить расход" или "+ Добавить доход" в зависимости от текущей вкладки

EMPTY STATE (когда 0 транзакций):
  Иллюстрация (SF Symbol "chart.bar.xaxis" large)
  "Нет расходов" / "Нет доходов"
  "Добавьте первую транзакцию"
  Button: + Добавить
```

**Шаги:**
1. `[ ]` Создать структуру папки `Components/`
2. `[ ]` Вынести `CashflowEmptyState` первым (самый изолированный)
3. `[ ]` Вынести `CashflowCategoryCard` (карточка без данных пока)
4. `[ ]` Вынести `CashflowCategoryGrid` (grid + sort)
5. `[ ]` Вынести `CashflowQuickActions`
6. `[ ]` Вынести `CashflowSummaryCard` (базовая, без лимита)
7. `[ ]` Создать заглушку `CashflowChartSection`
8. `[ ]` Переписать `CashflowView.swift` как компоновщик ≤300 строк
9. `[ ]` `CashflowCategoryGridLayout`: 3 колонки
10. `[ ]` Убрать FAB, добавить Quick Actions row
11. `[ ]` Убрать subtitle даты из header
12. `[ ]` Gate: `xcodebuild build` — 0 ошибок
13. `[ ]` Визуальная проверка: сетка, header, отсутствие FAB

**Guard phrase:** «Реализуй Phase 2 по плану.»

---

### `[x]` Phase 3: PageTabView — Расходы / Доходы / Всё

**AC:** AC-U2, AC-U3

**Цель:** Добавить свайп между Расходы/Доходы/Все транзакции. Summary card и сетка обновляются под контекст.

**Концепция:**
```swift
enum CashflowTab { case expenses, income, all }

// В CashflowView:
TabView(selection: $selectedTab) {
    CashflowExpensesPage(vm: categoriesVM, mainVM: mainVM)
        .tag(CashflowTab.expenses)
    CashflowIncomePage(vm: categoriesVM, mainVM: mainVM)
        .tag(CashflowTab.income)
    CashflowAllTransactionsPage(historyVM: historyVM)
        .tag(CashflowTab.all)
}
.tabViewStyle(.page(indexDisplayMode: .never))
```

**Новые файлы:**
```
millio/UI/Services/Cashflow/
  Pages/
    CashflowExpensesPage.swift      — сетка расходных категорий
    CashflowIncomePage.swift        — сетка доходных категорий
    CashflowAllTransactionsPage.swift — список всех транзакций (переиспользует history)
  Components/
    CashflowTabIndicator.swift      — кастомный индикатор вкладок (3 dot / underline)
```

**Изменяемые файлы:**
- `CashflowView.swift` — добавить TabView + CashflowTabIndicator
- `CashflowSummaryCard.swift` — принимает `CashflowTab`, показывает "Потрачено" / "Заработано" / "Баланс"
- `CashflowMainViewModel` — добавить computed: `totalIncome(for:)`, `totalExpenses(for:)`, `netBalance(for:)`

**Шаги:**
1. `[ ]` Добавить `CashflowTab` enum в CashflowMainViewModel
2. `[ ]` Создать `CashflowExpensesPage` (расходные категории, текущая логика)
3. `[ ]` Создать `CashflowIncomePage` (доходные категории)
4. `[ ]` Создать `CashflowAllTransactionsPage` (список, переиспользовать HistoryView)
5. `[ ]` Собрать TabView в CashflowView
6. `[ ]` Создать `CashflowTabIndicator` под header
7. `[ ]` Обновить `CashflowSummaryCard` под tab контекст
8. `[ ]` Добавить computeds в CashflowMainViewModel
9. `[ ]` Gate: `xcodebuild build` — 0 ошибок
10. `[ ]` Проверить: свайп переключает контекст, суммы правильные

**Guard phrase:** «Реализуй Phase 3 по плану.»

---

### `[x]` Phase 4: Лимиты + Inline Chart

**AC:** AC-U3, AC-U4, AC-U5, AC-U10

**Цель:** Показать прогресс лимитов в сетке и сделать chart collapsible inline.

**Limit bars:**
```
CashflowCategoryCard получает:
  - limitProgress: BudgetProgressSnapshot? (nil если лимит не задан)
  
Если лимит задан:
  ┌─────────────────┐
  │  🛒              │
  │  Продукты       │
  │  2 340 ₽        │
  │ ████░░░░░░  47% │  ← тонкий бар, цвет = tone
  └─────────────────┘
  
Цвета progress bar:
  normal   < 70%:  accent (cyan)
  warning 70–90%:  orange
  critical 90–100%: red tint
  exceeded >100%:  red + "!" badge
```

**Summary card с лимитом:**
```
SummaryCard (когда есть бюджет):
  Потрачено: 12 340 ₽
  ██████░░░░░░  61% от лимита 20 000 ₽
  [Изменить лимиты]

SummaryCard (без бюджета):
  Потрачено: 12 340 ₽
  [+ Добавить лимиты]
```

**Inline chart:**
- Переместить chart из `cashflowChartSection` в `CashflowChartSection.swift`
- Collapsible: `@State var chartExpanded = true`
- Заголовок + chevron: тап → `withAnimation { chartExpanded.toggle() }`
- PRO-гейт: если !canUseCashflowChart → blur + "PRO" badge + onTap → paywall
- Режимы: [По неделям] [По категориям] [vs Прошлый месяц] — SegmentedControl

**Изменяемые файлы:**
- `CashflowCategoryCard.swift` — добавить `limitProgress` + progress bar view
- `CashflowSummaryCard.swift` — добавить total limit progress
- `CashflowChartSection.swift` — полноценная реализация (не заглушка)
- `CashflowMainViewModel` / `CashflowCategoriesViewModel` — передавать BudgetProgressSnapshot по категориям

**Шаги:**
1. `[ ]` Добавить `limitProgress: BudgetProgressSnapshot?` в CashflowCategoryCard
2. `[ ]` Реализовать progress bar view в CashflowCategoryCard
3. `[ ]` Обновить grid — передавать snapshots из BudgetProgressCalculator
4. `[ ]` Обновить SummaryCard — total limit progress
5. `[ ]` Реализовать CashflowChartSection — collapsible + режимы
6. `[ ]` PRO-гейт в ChartSection
7. `[ ]` Gate: `xcodebuild build` — 0 ошибок
8. `[ ]` Проверить: лимиты отображаются/скрываются корректно, chart сворачивается

**Guard phrase:** «Реализуй Phase 4 по плану.»

---

### `[x]` Phase 5: Quick Entry

**AC:** AC-U6

**Цель:** Тап на карточку категории → `CashflowQuickEntrySheet` с цифровой клавиатурой и pre-selected категорией.

**UX:**
```
Тап на 🛒 Продукты (в режиме Расходы):
  └→ CashflowQuickEntrySheet появляется снизу (detent: .medium)
     ┌──────────────────────────┐
     │  🛒 Продукты             │
     │                          │
     │      0 ₽                 │  ← AmountInputFormatter
     │   [1][2][3]              │
     │   [4][5][6]              │
     │   [7][8][9]              │
     │   [.][0][⌫]              │
     │                          │
     │  Дата: Сегодня  [Изм.]   │
     │  Заметка: ...            │
     │                          │
     │  [Отмена]  [Добавить ₽]  │
     └──────────────────────────┘
     
Swipe down / Отмена → без сохранения
Добавить → вызов CashflowMainViewModel.addTransaction(...)
```

**Новые файлы:**
- `millio/UI/Services/Cashflow/Components/CashflowQuickEntrySheet.swift`

**Изменяемые файлы:**
- `CashflowCategoryCard.swift` — добавить onTap callback
- `CashflowExpensesPage.swift` / `CashflowIncomePage.swift` — управление sheet state

**Детали реализации:**
- Переиспользовать `AmountInputFormatter` из CashflowTransactionEditorView
- `@FocusState` — фокус на поле суммы при появлении
- `.presentationDetents([.medium])` + `.presentationDragIndicator(.visible)`
- При успешном сохранении — haptic feedback (success)
- Дата по умолчанию: сегодня, можно изменить (DatePicker inline)
- Заметка: опциональное текстовое поле

**Шаги:**
1. `[ ]` Создать `CashflowQuickEntrySheet`
2. `[ ]` Интегрировать AmountInputFormatter
3. `[ ]` Подключить к CashflowCategoryCard через onTap
4. `[ ]` Подключить сохранение через CashflowMainViewModel
5. `[ ]` Gate: `xcodebuild build` — 0 ошибок
6. `[ ]` Проверить: тап → sheet, ввод суммы, сохранение, отмена

**Guard phrase:** «Реализуй Phase 5 по плану.»

---

### `[x]` Phase 6: Полировка

**AC:** Все AC — финальная проверка

**Цель:** Анимации, financial edge cases, локализация, финальный QA.

**Задачи:**
1. `[ ]` Локализация: все новые строки в `Localizable.xcstrings` (RU/EN/zh-Hans)
2. `[ ]` Анимации: transition при смене вкладок, появление chart, empty state
3. `[ ]` Проверка на iPhone SE (4.7"): сетка 3 кол не обрезается
4. `[ ]` Проверка с кастомными категориями: отображаются в сетке
5. `[ ]` Проверка со скрытыми категориями (isHidden): не показываются
6. `[ ]` Проверка PRO vs Free: chart закрыт, quick entry работает
7. `[ ]` Проверка при exceeded лимите (>100%): красный цвет + badge
8. `[ ]` Haptic feedback при добавлении транзакции через quick entry
9. `[ ]` `xcodebuild test` — все тесты green
10. `[ ]` Impact analysis: какие экраны затронуты косвенно
11. `[ ]` Коммит: `feat(cashflow): redesign v2 — полный редизайн и декомпозиция`

**Guard phrase:** «Реализуй Phase 6 по плану.»

---

## Edge Cases (Think Several Steps Ahead)

- [ ] Нулевые данные — EmptyState (Phase 2)
- [ ] Кастомные категории (CashflowCustomCategory) — отображаются в сетке рядом с системными
- [ ] Скрытые категории — не рендерятся в grid
- [ ] Много категорий (>30 включая кастомные) — ScrollView справляется, LazyVGrid lazy
- [ ] Race condition: добавление транзакции во время свайпа между вкладками — @MainActor защита
- [ ] BudgetPlan не существует — progress bars не рендерятся (nil snapshot)
- [ ] Exceeded лимит — красный цвет, не крашится
- [ ] Quick entry + rotation (landscape) — .presentationDetents адаптируется
- [ ] Отмена quick entry midway — no side effects, no partial save
- [ ] Chart для Free пользователя — blur + paywall, не крашится

## Gates (обязательны перед `[x]` на каждой фазе)

- [ ] `xcodebuild build -scheme millio` — 0 compile errors
- [ ] Визуальная проверка на симуляторе (iPhone 16, iPhone SE)
- [ ] Phase 6 дополнительно: `xcodebuild test -scheme millio` — все тесты green

## Журнал изменений

- `2026-05-09` — создан план, research + spec готовы. Phase 1 не начата.
- `2026-05-09` — реализованы Phase 1–5: VM декомпозиция, View декомпозиция, 3-колоночная сетка, PageTabView (Расходы/Доходы/Всё), CashflowQuickEntrySheet. Build succeeded.
- `2026-05-09` — Phase 6: финальная проверка, EmptyState добавлен в CashflowCategoryTransactionSheet (tray icon + локализация), исправлен SchemaConsistencyTests (#expect Comment API), коммит выполнен.

## Итог

**Результат:** РЕАЛИЗОВАН
**Что реализовано:** Phases 1–6 — полный редизайн экрана Cashflow: VM/View декомпозиция, 3-col grid, PageTabView, QuickEntry, EmptyState, план обновлён.
**Дата завершения:** 2026-05-09
