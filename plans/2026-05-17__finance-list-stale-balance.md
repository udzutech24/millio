# Plan: Finance List — Stale Balance After Quick Audit

**Статус:** РЕАЛИЗОВАН  
**Дата:** 2026-05-17  
**Ветка:** `feature/finance-list-stale-balance`

## Проблема

После сохранения баланса через `AccountQuickAuditView` (и `FinanceQuickEditAccountView`) список счётов в `FinancesView` показывает старые значения. При этом детальный экран (FinanceDynamicsView) всегда показывает правильные данные.

## Root Cause (доказан research-фазой)

Два независимых слоя:

**Слой 1 — Мёртвые триггеры в `FinancesMainTabView`:**
- `onChange(of: _cardBalanceMonitor)` никогда не срабатывает: `Card: @Model` реализует `Equatable` через `PersistentIdentifier` (identity). Изменение `card.balance` не меняет identity → массив `[Card]` "равен" → `onChange` не триггерится. Мёртвый код.
- `onChange(of: showQuickAuditCover)` стреляет в начале dismiss-анимации. К этому моменту iOS может уже сделать snapshot подлежащего view для перехода. Триггер `loadAccounts()` попадает в window анимации и рендер не гарантирован до её завершения.

**Слой 2 — `cardByID` не @Published:**
- `onCachesRebuilt` обновляет `cardByID` (строка 377) без уведомления SwiftUI. `FinanceGroupRow.accountsAccordion` читает из `cardByID` через `getAccountInfo`, но SwiftUI не знает, что эта зависимость изменилась.
- `@Published var state` из `onAccountsLoaded` срабатывает раньше (`cardByID` ещё старый), но к моменту render-pass SwiftUI оба callback уже выполнены (оба synchronous @MainActor). Тем не менее явной гарантии нет.

## Решение

**Два точечных изменения:**

### Изменение 1 — `FinanceViewModel.swift`

Сделать `cardByID` (`creditByID`, `investmentByID`) @Published.

**Было:**
```swift
private var cardByID: [String: Card] = [:]
private var creditByID: [String: Credit] = [:]
private var investmentByID: [String: Investment] = [:]
```

**Станет:**
```swift
@Published private(set) var cardByID: [String: Card] = [:]
@Published private(set) var creditByID: [String: Credit] = [:]
@Published private(set) var investmentByID: [String: Investment] = [:]
```

Эффект: каждый `onCachesRebuilt` гарантированно стреляет `objectWillChange` после обновления кэшей. `FinanceGroupRow` подписан через `@ObservedObject var viewModel` — получит сигнал и пересчитает `accountsAccordion` с актуальными значениями из `cardByID`.

Оба callback (`onAccountsLoaded` + `onCachesRebuilt`) выполняются synchronous на @MainActor → SwiftUI батчит оба `objectWillChange` в один render-pass → один рендер, не два.

### Изменение 2 — `FinancesView.swift` (строки 425–438)

Убрать мёртвые триггеры. Заменить `onChange(of: showQuickAuditCover)` на `onDismiss:` — он гарантированно стреляет **после завершения** анимации.

**Было:**
```swift
.fullScreenCover(isPresented: $showQuickAuditCover) {
    AccountQuickAuditView {
        viewModel.handle(.loadAccounts)   // onCommitted
    }
}
.onChange(of: showQuickAuditCover) { _, isPresented in
    guard !isPresented else { return }
    viewModel.handle(.loadAccounts)
}
// SwiftData-observer: срабатывает после полного merge save-а в контекст,
// гарантируя что loadAccounts увидит актуальные балансы карт.
.onChange(of: _cardBalanceMonitor) { _, _ in
    viewModel.handle(.loadAccounts)
}
```

**Станет:**
```swift
.fullScreenCover(isPresented: $showQuickAuditCover, onDismiss: {
    viewModel.handle(.loadAccounts)     // после завершения анимации
}) {
    AccountQuickAuditView {
        viewModel.handle(.loadAccounts) // prefetch пока cover ещё виден
    }
}
```

`@Query private var _cardBalanceMonitor: [Card]` — удалить (строка 371).

Роль каждого оставшегося триггера:
- **`onCommitted` closure**: prefetch — вызывает `loadAccounts()` пока cover ещё показан. К моменту dismiss данные в `cardByID` уже готовы.
- **`onDismiss:`**: гарантированный финальный рендер ПОСЛЕ завершения анимации. `loadAccounts()` + `@Published cardByID` → `objectWillChange` → view показывает актуальные значения.

## Фазы

### Фаза 1 — FinanceViewModel: @Published caches [x]

**Файл:** `millio/UI/Services/Finances/FinanceViewModel.swift`, строки 298–300

- [ ] Изменить `private var cardByID` → `@Published private(set) var cardByID`
- [ ] Изменить `private var creditByID` → `@Published private(set) var creditByID`
- [ ] Изменить `private var investmentByID` → `@Published private(set) var investmentByID`
- [ ] Проверить компиляцию — `private(set)` не ломает ни один читающий callsite (все read-only)
- [ ] Убедиться что `cardByIDProvider` в строке 313 и 400 не сломан (замыкание читает `self?.cardByID` — ОК)

**Gate:** `Build succeeds. No new compiler errors.`

### Фаза 2 — FinancesView: fix triggers [x]

**Файл:** `millio/UI/Services/Finances/FinancesView.swift`

- [ ] Строка 371: удалить `@Query private var _cardBalanceMonitor: [Card]`
- [ ] Строки 425–438: заменить `fullScreenCover` + два `onChange` на новый `fullScreenCover(onDismiss:)` (см. код выше)
- [ ] Удалить комментарий про SwiftData-observer (строки 434–435) вместе с `onChange`
- [ ] Проверить компиляцию

**Gate:** `Build succeeds.`

### Фаза 3 — Тестирование [x]

**Сценарии:**

| Сценарий | Путь | Ожидание |
|----------|------|----------|
| Дебетовая карта — изменить баланс | AQA → Save | Список показывает новый баланс после dismiss |
| Кредитная карта — изменить баланс | AQA → Save | Список показывает новый **долг** (`debtAmount`) с маркировкой `isCreditCardDebt` |
| Инвестиция — изменить баланс | AQA → Save | Список показывает новое значение |
| Изменение через QuickEdit | FinanceQuickEditAccountView → Save | Список обновляется (путь через `updateAccountAmount` → `loadAccounts`) |
| Без изменений → выйти из AQA | AQA → Cancel / swipe dismiss | Список не мигает, значения не меняются |

- [ ] Все 5 сценариев пройдены в симуляторе
- [ ] Нет регрессии по анимации открытия/закрытия cover

### Фаза 4 — Коммит [x]

- [ ] Коммит: `fix(finances): @Published cardByID + onDismiss fix stale balance in account list`
- [ ] Обновить этот план: статус РЕАЛИЗОВАН

## Затронутые файлы

| Файл | Изменение |
|------|-----------|
| `millio/UI/Services/Finances/FinanceViewModel.swift` | 3 строки: `private var` → `@Published private(set) var` |
| `millio/UI/Services/Finances/FinancesView.swift` | удалить `@Query _cardBalanceMonitor` + 2 `onChange`; добавить `onDismiss:` |

## Acceptance Criteria

- [ ] AC1: После сохранения в AQA список счётов показывает обновлённый баланс без лагов
- [ ] AC2: Кредитные карты показывают обновлённый `debtAmount` с маркировкой долга
- [ ] AC3: Значения корректны сразу после завершения dismiss-анимации (не мигают)
- [ ] AC4: Нет лишних повторных рендеров — только один render-pass на `loadAccounts()`

## Журнал

- 2026-05-17: Research-фаза завершена. Определены два слоя root cause: мёртвые onChange-триггеры и non-@Published cardByID. Написан план.
- 2026-05-17: Реализовано. cardByID/creditByID/investmentByID → @Published private(set). onChange(of: showQuickAuditCover) + onChange(of: _cardBalanceMonitor) → onDismiss:. Добавлено 3 unit-теста. Все тесты прошли (0 failures).
