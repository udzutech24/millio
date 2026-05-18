# Account Quick Audit — Архив фичи

**Статус:** УДАЛЕНА (2026-05-18) — будет переделана с нуля  
**Причина удаления:** `FinanceBalanceAuditStore` ломал отображение балансов в `FinanceDynamicsView` — стейлые снапшоты перезаписывали live-значения из SwiftData. Также AQA показывал счета которых не существует и не обновлял список счетов после сохранения.

**Восстановить код:** `git show 581d2323` — первый коммит AQA. Вся цепочка: `581d2323..ef69666c` (27 коммитов).

---

## Идея (сохрани для v2)

**Зачем:** Счётов много (карты + кредиты + инвестиции). Актуализация сейчас = зайти в каждый счёт вручную. Quick Audit = один флоу, все счета подряд, минимум тапов.

**Запуск:** Кнопка «Актуализировать балансы» в `FinancesSettingsSheet` → `fullScreenCover`.

**UX-флоу:**
1. **Intro** (0.3с): «Проверка счетов» + иконка + кол-во счетов + кнопка «Начать»
2. **Карточка счёта** (spring снизу):
   - Иконка + название + тип (Карта/Кредит/Инвестиция)
   - Текущий баланс крупно
   - Progress bar «3 из 7»
   - Кнопка **«Верно ✓»** (зелёный) → slide-out вправо с rotation(-5°)
   - Кнопка **«Изменить ✏️»** → TextField поверх баланса, цифровая клавиатура
3. **Свайп:** вправо = верно, влево = редактировать
4. **Outro:** анимация ✓ + «Все счета проверены!» + haptic success + confetti

**Визуальный стиль:**
- `rounded 24pt`, background `.ultraThinMaterial`, цвет акцента от типа счёта
- Анимации: `spring(response: 0.5, dampingFraction: 0.75)`
- Confirm: карточка улетает вправо `rotationEffect(-5°) + opacity → 0`
- Edit: карточка остаётся, баланс «трансформируется» в TextField

## Архитектура (как было)

```
AccountQuickAuditView          ← fullScreenCover, оркестратор флоу
  ├── AccountAuditCardView     ← карточка одного счёта
  └── AccountAuditReminderView ← настройка напоминаний
  
FinanceBalanceAuditSheet       ← отдельный sheet просмотра истории балансов
  └── FinanceBalanceAuditViewModel
  
Audit/
  ├── FinanceBalanceAuditStore.swift    ← UserDefaults-хранилище снапшотов по дням
  ├── FinanceBalanceAuditModels.swift   ← модели данных
  ├── FinanceBalanceAuditViewModel.swift
  └── FinanceBalanceAuditSheet.swift
```

```swift
struct AuditableAccount {
    enum AccountType { case card(Card), investment(Investment), credit(Credit) }
    let type: AccountType
    var balance: Double
    var displayName: String
    var icon: String
    var accentColor: Color
}
```

## Баги которые нужно исправить в v2

1. **Показывал несуществующие счета** — нужна фильтрация архивированных счетов (`isArchived == false`)
2. **Список счетов не обновлялся после сохранения** — root cause: `onCommitted` вызывал `loadAccounts()` синхронно после `save()`, до SwiftData merge. Решение в v2: слушать `@Query` изменения SwiftData, не использовать callback.
3. **FinanceBalanceAuditStore ломал FinanceDynamicsView** — стейлые снапшоты перезаписывали live-балансы. В v2 **НЕ писать снапшоты в AuditStore** при сохранении баланса. Либо вообще убрать AuditStore как механизм — хранить историю изменений в отдельной SwiftData-модели.

## Файлы (все удалены)

```
millio/UI/Services/Finances/AccountQuickAuditView.swift      (865 строк)
millio/UI/Services/Finances/AccountAuditCardView.swift       (253 строки)
millio/UI/Services/Finances/AccountAuditReminderView.swift   (347 строк)
millio/UI/Services/Finances/Audit/
  FinanceBalanceAuditStore.swift      (126 строк)
  FinanceBalanceAuditModels.swift     (101 строка)
  FinanceBalanceAuditSheet.swift      (478 строк)
  FinanceBalanceAuditViewModel.swift  (474 строки)
millioTests/UI/Services/Finances/FinanceBalanceAuditStoreTests.swift
millioTests/UI/Services/Finances/FinanceBalanceAuditViewModelTests.swift
```

**Интеграция (убрана из):**
- `RootTabView.swift` — `showBalanceAudit`, `showQuickAudit`, `.fullScreenCover`, `.sheet`
- `FinancesView.swift` — `onOpenQuickAudit` callback, `showBalanceAuditSheetFromSettings`, `showQuickAuditCover`
- `FinanceDynamicsViewModel.swift` — `auditStore` property, `snapshotValues(for:)` call в `calculateBalanceAtDate`

## Что сохранить в spec/plan для v2

Spec: `specs/2026-05-16__account-quick-audit.md` — UX-описание актуально, перепиши только Acceptance Criteria с учётом багов выше.  
Plan: `plans/2026-05-16__account-quick-audit.md` — архитектура нужна новая, без AuditStore.
