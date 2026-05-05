# Spec: Tab Bar Navigation (корневая навигация)

**Slug:** `tab-bar-navigation`
**Дата:** 2026-05-05
**Размер:** L
**Статус:** УТВЕРЖДЁН

---

## Проблема

Главный экран — лаунчер со списком кнопок-сервисов. Пользователь сначала видит меню, потом проваливается в нужный раздел. Это лишний шаг и устаревший UX-паттерн.

## Решение

Убрать экран-лаунчер. Заменить на корневой tab bar с мгновенным доступом к Финансам, Динамике и Кэшфлоу. Добавить FAB-кнопку по центру для быстрого ввода операций.

---

## Экраны после изменений

### Tab bar (снизу)

```
[ Финансы ]  [ Динамика ]  [ ╋ ]  [ Кэшфлоу ]
```

| Таб | Контент | Иконка |
|-----|---------|--------|
| Финансы | `FinancesMainTabView` (балансы, счета, группы) | `creditcard` |
| Динамика | `FinanceDynamicsTabView` (графики, периоды) | `chart.line.uptrend.xyaxis` |
| **[+]** | FAB — action sheet → Доход / Расход | `plus` (circle, увеличенный) |
| Кэшфлоу | `CashflowView` (операции + Подписки внутри) | `arrow.left.arrow.right` |

### Финансы таб — шапка

Поверх основного контента добавляется горизонтальная полоска с чипами:

```
[ 💱 Курсы ]  [ % Кешбэк ]
```

Тап на чип → push в NavigationStack текущего таба (CoursesView / CashbackView).

### Профиль

Иконка профиля — в top-left navigation bar таба Финансы (как сейчас на главном).

### История операций

Кнопка истории переезжает в top-right CashflowView (там она логичнее).

---

## Поведение FAB

- При тапе — появляется `ActionSheet` / `confirmationDialog` с вариантами: «Доход», «Расход»
- Открывает соответствующий sheet (`CashflowIncomeTransactionSheet` / `CashflowExpenseTransactionSheet`)
- Не переключает таб — sheet появляется поверх текущего таба
- `CashflowViewModel` инициализируется в `RootTabView` и передаётся в sheets

---

## Deep links и виджет

| Pending flag | Новое поведение |
|---|---|
| `pendingOpenConverterService` | переключить таб → Финансы, открыть chips → Курсы push |
| `pendingOpenMainExpenseSheet` | открыть FAB sheet → Расход (без переключения таба) |
| `pendingOpenMainIncomeSheet` | открыть FAB sheet → Доход |
| `pendingOpenCashflowExpense` | переключить таб → Кэшфлоу, открыть sheet Расход |
| `pendingOpenCashflowIncome` | переключить таб → Кэшфлоу, открыть sheet Доход |
| `pendingOpenCashflowHistory` | переключить таб → Кэшфлоу, открыть историю |

---

## Что исчезает

- Экран-лаунчер `MainAppView` (grid сервисов) — удаляется
- `MainAppViewModel` — удаляется
- `ServiceItem`, `ServiceOrderManager` — удаляются (drag-to-reorder больше не нужен)
- `MainQuickActionsLayout` — удаляется
- Кнопки «Доход» / «Расход» внизу главного экрана → заменяются FAB
- История на главном — переезжает в Кэшфлоу

---

## Acceptance criteria

- [ ] Tab bar рендерится из `RootTabView`, заменяет `MainAppView` в `RootViewResolver`
- [ ] Финансы: показывает `FinancesMainTabView` + чипы Курсы/Кешбэк вверху
- [ ] Динамика: показывает `FinanceDynamicsTabView`
- [ ] FAB [+]: открывает выбор Доход/Расход без смены таба
- [ ] Кэшфлоу: показывает `CashflowView` с Подписками внутри (без изменений)
- [ ] Профиль: доступен из top-left Финансов
- [ ] История: доступна из Кэшфлоу
- [ ] Кнопка «Динамика» внутри Финансов переключает корневой таб, а не внутренний
- [ ] Widget deep links работают корректно (все 6 pending-флагов)
- [ ] Quick Setup banner переезжает на экран Финансы (или убирается — решить в Phase 0)
- [ ] Все существующие тесты проходят
- [ ] Локализация чипов Курсы/Кешбэк — через `Localizable.xcstrings`
