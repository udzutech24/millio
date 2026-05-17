# Plan: Account Quick Audit

**Статус:** РЕАЛИЗОВАН  
**Spec:** `specs/2026-05-16__account-quick-audit.md`  
**Дата:** 2026-05-16

## Архитектура

```
AccountQuickAuditView          ← fullScreenCover, оркестратор флоу
  ├── AccountAuditIntroView    ← intro экран
  ├── AccountAuditCardView     ← карточка одного счёта (переиспользуется)
  └── AccountAuditOutroView    ← финальный экран

FinancesView.swift             ← добавить кнопку в FinancesSettingsSheet
```

### Модель данных флоу

```swift
struct AuditableAccount {
    enum AccountType {
        case card(Card)
        case investment(Investment)
        case credit(Credit)
    }
    let type: AccountType
    var balance: Double          // текущее значение (для редактирования)
    var displayName: String
    var icon: String             // emoji или название банка
    var accentColor: Color
}
```

`AccountQuickAuditView` получает `[AuditableAccount]` при инициализации, формируя список из всех Card + Investment + Credit через `FinanceViewModel`.

## Фазы

### Фаза 1 — AccountAuditCardView (основная карточка) [x]

Файл: `millio/UI/Services/Finances/AccountAuditCardView.swift`

**Что делает:**
- Принимает `AuditableAccount` + `Int index` + `Int total` + колбэки `onConfirm` / `onEdit(newBalance:)`
- Показывает иконку, название, тип, баланс
- Progress bar + «N из M»
- Кнопки «Верно ✓» и «Изменить ✏️»
- Режим редактирования: при нажатии «Изменить» баланс превращается в `TextField` с цифровой клавиатурой и кнопкой «Сохранить»
- Spring-анимация появления (`.transition(.move(edge: .bottom).combined(with: .opacity))`)
- Offset gesture для свайпа: +100pt → confirm, −100pt → edit

**Acceptance gate:** карточка рендерится в Preview с тестовыми данными Card, Investment, Credit.

---

### Фаза 2 — AccountQuickAuditView (оркестратор) [x]

Файл: `millio/UI/Services/Finances/AccountQuickAuditView.swift`

**Что делает:**
- Получает `modelContext: ModelContext` через environment
- При инициализации: загружает все Card (не archived, `includeInTotal`), Investment, Credit → `[AuditableAccount]`
- `@State var currentIndex: Int = 0` + enum `FlowState { case intro, card(Int), outro }`
- Переключение с `withAnimation(.spring(...))` при `onConfirm` / `onEdit`
- При `onEdit(newBalance:)` — обновляет соответствующую модель в SwiftData (`card.balance = newBalance`, `investment.amount = newBalance`, `credit.remainingAmount = newBalance`), автосохранение через `try? modelContext.save()`
- Intro экран: заголовок, иконка 🔄, кол-во счетов, кнопка «Начать»
- Outro: заголовок «Всё проверено!», confetti-частицы (простой `TimelineView` с точками или SF Symbol confetti), haptic `.notificationOccurred(.success)`, кнопка «Готово»

**Acceptance gate:** полный флоу от Intro до Outro без краша, SwiftData обновляется.

---

### Фаза 3 — Интеграция в FinancesSettingsSheet [x]

Файл: `millio/UI/Services/Finances/FinancesView.swift`

**Что делает:**
- Добавить `@State var showQuickAudit = false` в `FinancesSettingsSheet`
- Добавить кнопку «Актуализировать балансы» в секцию настроек (ниже сортировки)
- `.fullScreenCover(isPresented: $showQuickAudit) { AccountQuickAuditView() }`

**Acceptance gate:** кнопка видна в settings sheet, нажатие открывает флоу.

---

### Фаза 4 — Анимации и полировка [x]

**Что делает:**
- Swipe gesture на карточке: `DragGesture` → при release >80pt X → trigger confirm/edit
- Visual cue при свайпе: зелёная / оранжевая подсветка края карточки в зависимости от направления
- Карточка при confirm: улетает вправо с `rotationEffect(-5°)` + `opacity → 0`
- Confetti outro: `ConfettiView` через `Canvas` — 20–30 разноцветных точек с randomized physics за 2с
- Haptic на каждый шаг: `.impactOccurred(intensity: 0.5)`

**Acceptance gate:** смотрится плавно в симуляторе, нет janky frames.

---

## Файлы изменений

| Файл | Действие |
|------|---------|
| `millio/UI/Services/Finances/AccountAuditCardView.swift` | создать |
| `millio/UI/Services/Finances/AccountQuickAuditView.swift` | создать |
| `millio/UI/Services/Finances/FinancesView.swift` | изменить (FinancesSettingsSheet) |

## Журнал сессий

| Дата | Фазы | Итог |
|------|------|------|
| 2026-05-16 | 1–4 | BUILD SUCCEEDED, коммит 581d2323 |
| 2026-05-17 | bugfix s1 | Фикс: список счетов не обновлялся после сохранения. Root cause: одновременный dismiss sheet+fullScreenCover ломал onDismiss. Решение: pendingDismissAfterSave flag + onChange(of: showExitConfirmation) в AccountQuickAuditView; onChange(of: showQuickAuditCover) вместо onDismiss в FinancesMainTabView |
| 2026-05-17 | bugfix s2 | Баг сохранялся через 3 сессии. Root cause установлен: onCommitted/onChange вызывали loadAccounts() СИНХРОННО сразу после save(), до того как SwiftData успевал смёрджить изменения обратно в mainContext — cardByID получал Card со СТАРЫМ балансом. Решение: @Query private var _cardBalanceMonitor: [Card] в FinancesMainTabView. @Query стреляет АСИНХРОННО после полного merge SwiftData-нотификации — гарантирует что loadAccounts() видит актуальные балансы. |
