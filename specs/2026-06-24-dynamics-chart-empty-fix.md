# Spec: Динамика — фикс пустого графика в режиме «весь портфель»

**Дата:** 2026-06-24
**Размер:** M
**Статус:** READY

---

## Проблема

Экран «Динамика» в режиме aggregated (весь портфель, без фильтра по счёту) всегда возвращает пустой `chartData`. Пользователь видит пустой граф вместо истории портфеля.

Причина — цепочка из трёх связанных багов, в сумме дающих пустой массив точек.

---

## Диагноз (доказанные баги)

### BUG #1 — инвертированное сравнение в `earliestClosedSnapshotDateByAccount`
**Файл:** `FinanceDynamicsViewModel.swift:1714`
**Код:** `if let existing = result[snapshot.accountID], existing <= date { return }`
**Проблема:** сохраняет ПОСЛЕДНЮЮ дату снапшота вместо ПЕРВОЙ.
**Фикс:** `existing >= date` вместо `existing <= date`.

### BUG #2 — `requiredSnapshotAccountIDs` исключает ВСЕ счета без записи в словаре
**Файл:** `FinanceDynamicsViewModel.swift:1670`
**Код:** `guard let snapshotStart = snapshotStartByAccountID[account.accountID] else { return false }`
**Проблема:** если BUG #1 искажает словарь → у некоторых счетов нет записи → `return false` → 0 required IDs → все дни пропускаются → пустой массив.
**Фикс:** счета без снапшотов не ломают весь список — их нужно исключать из required (а не делать required пустым). Это меняет семантику: «дни ДО первого снапшота счёта не требуют этот счёт».

### BUG #3 — `requireEveryClosedDay: true` по умолчанию в `accountPortfolioDailyPoints`
**Файл:** `AccountDailySnapshotReader.swift:187` + `:235`
**Код:** параметр по умолчанию `= true` → при любом не-закрытом снапшоте возвращает `[]`.
**Решение (ревью):** не менять дефолт глобально. Вместо этого — вызывающий код (в `buildAccountSnapshotSeries`) уже передаёт `requireEveryClosedDay` через замыкание `requiredAccountIDsByDateKey`, который возвращает пустой список для дней без нужных счетов. Дефолт `true` используется в других вызовах (напр. строка 132 — `false`). Безопаснее не трогать дефолт, убедиться что BUG #1 и #2 починены — тогда `requiredAccountIDsByDateKey` будет возвращать корректные non-empty ID и `requireEveryClosedDay` станет неактуален для этого кейса. **BUG #3 — не фиксить, мониторить после BUG#1/#2.**

### Silent failures
**Файл:** `FinanceDynamicsViewModel.swift:1521/1525`
`state.chartData = []` без логирования причины — невозможно диагностировать в продакшне.
**Фикс:** добавить `AppLogger.debug(...)` с указанием `.gap` / `.insufficient` + контекст (accountIDs, period, displayCurrency).

---

## Цель

После фикса: при наличии хотя бы 2 снапшотов для портфеля в выбранном периоде пользователь видит заполненный граф в режиме aggregated.

---

## Acceptance Criteria

- [ ] **AC1.** `earliestClosedSnapshotDateByAccount` возвращает ПЕРВУЮ дату закрытого снапшота (минимальная дата по каждому accountID).
- [ ] **AC2.** `requiredSnapshotAccountIDs` включает только счета, у которых есть снапшот на этот день или раньше. Счета без единого снапшота — не ломают всю цепочку.
- [ ] **AC3.** `buildAccountSnapshotSeries` с 2+ закрытыми снапшотами возвращает `.authoritative(points)`, не `.gap` и не `.insufficient`.
- [ ] **AC4.** При `.gap` и `.insufficient` в лог идёт `AppLogger.debug` с причиной и контекстом.
- [ ] **AC5.** Все существующие тесты `FinanceDynamicsViewModelTests` и `DailySnapshotArchitectureTests` проходят без изменений.
- [ ] **AC6.** Новые unit-тесты покрывают BUG #1 (регрессионный), BUG #2 (регрессионный), и сценарий «счёт без снапшотов не ломает requiredIDs».

---

## Scope

**В скоуп:**
- `FinanceDynamicsViewModel.swift` — `earliestClosedSnapshotDateByAccount`, `requiredSnapshotAccountIDs`, silent failures в `.gap`/`.insufficient`
- Новый тестовый файл или дополнение к `DailySnapshotArchitectureTests`

**Вне скоупа:**
- `buildTimeSeriesData` (фильтрованный режим, другой codepath)
- `AccountDailySnapshotReader` — не трогать (BUG #3 не фиксим)
- Race condition `isCurrentChartUpdateRevision` — отдельная задача
- Edge case «только 1 снапшот» — корректное поведение `.insufficient`, не баг

---

## Риски

| Риск | Митигация |
|------|-----------|
| Мисматч валют: снапшоты в USD, displayCurrency в RUB | Предикат `baseCurrency == displayCurrency` в `earliestClosedSnapshotDateByAccount` уже фильтрует. После BUG#1 фикса словарь будет правильным. |
| BUG #2 фикс расширяет «видимость» — счета ДО первого снапшота будут не required | Это правильное поведение: счёт которого нет — не нарушает полноту дня. Нужен тест. |
| Изменение в VM затрагивает `accountPortfolioDailyPoints` вызов через замыкание | Только параметр замыкания меняется (логика внутри requiredSnapshotAccountIDs). Сигнатура `accountPortfolioDailyPoints` не меняется. |

---

## Non-Goals

- Не исправлять `requireEveryClosedDay` глобально.
- Не декомпозировать `FinanceDynamicsViewModel`.
- Не трогать `buildTimeSeriesData`.
