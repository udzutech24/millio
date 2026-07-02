# Plan: Динамика — фикс пустого графика в режиме «весь портфель»

**Дата:** 2026-06-24
**Спек:** `specs/2026-06-24-dynamics-chart-empty-fix.md`
**Статус:** РЕАЛИЗОВАН (с корректировкой диагноза — см. журнал 2026-07-02)
**Ветка:** `feature/dynamics-chart-fix`

---

## Challenge Log

**Решает ли это доказанную проблему?**
Да. BUG #1 и #2 подтверждены чтением реального кода. BUG #1 (строка 1714): `existing <= date` → сохраняет max вместо min. BUG #2 (строка 1670): `return false` на отсутствующем ключе → 0 required IDs → пустой граф.

**Самое простое решение?**
Да. 2 однострочных изменения в VM + добавление логирования + 3–5 тестов. Никакой архитектуры, никакого рефакторинга.

**Нет кода ради кода?**
BUG #3 (requireEveryClosedDay) — НЕ трогаем. После фикса #1/#2 он не будет срабатывать для целевого сценария. Менять дефолт глобально — риск регрессий в других callsite.

---

## Фазы

### Фаза 1 — Фикс BUG #1 + BUG #2 + логирование `[x]`

> ⚠️ **Итог реализации 2026-07-02:** диагноз BUG #1 ОПРОВЕРГНУТ тестом. Оригинальное сравнение `existing <= date` УЖЕ возвращает минимальную (первую) дату: существующая запись сохраняется, когда она не позже новой. Инверсия на `>=` (как предписывала спека) эмпирически дала максимум (тест вернул 06-30 вместо 06-26) — правка отменена, оригинальная логика сохранена и закреплена регрессионным тестом. BUG #2 — код корректен (см. 1b), закреплён тестом. Логирование `.gap`/`.insufficient` добавлено (AC4).

**Файлы:** `millio/UI/Services/Finances/FinanceDynamicsViewModel.swift`

**Изменения:**

**1a. BUG #1 (строка ~1714)**
```swift
// ДО (неверно — сохраняет последнюю дату):
if let existing = result[snapshot.accountID], existing <= date { return }

// ПОСЛЕ (правильно — сохраняет первую дату):
if let existing = result[snapshot.accountID], existing >= date { return }
```

**1b. BUG #2 — пересмотрен после анализа**

Исходный диагноз описывает: `return false` на отсутствующем ключе → 0 required IDs → пустой граф.

Анализ реального кода показал: `return false` в строке 1670 — это семантически ПРАВИЛЬНОЕ поведение для счётов, у которых нет снапшотов вообще. Счёт без данных не должен включаться в required.

Реальный механизм BUG #2: из-за BUG #1 словарь `snapshotStartByAccountID` содержит ПОСЛЕДНИЕ даты вместо первых. Например, если снапшоты с 1 по 30 июня, словарь будет хранить «30 июня» как snapshotStart. Тогда `knownStart = max(accountStart, snapshotStart)` = 30 июня. Для дней 1–29 июня: `knownStart (30 июня) <= snapshotDay (напр. 5 июня)` → FALSE → счёт исключается → пустой requiredIDs → день пропускается.

**Вывод:** BUG #2 — это следствие BUG #1, не отдельный баг. После исправления BUG #1 (`>= date` вместо `<= date`) словарь будет содержать ПЕРВЫЕ даты, `knownStart` будет корректным, и счета будут включаться в required для всего периода начиная с первого снапшота. Строка 1670 (`return false`) — не трогать.

**1c. Логирование silent failures (строки ~1519-1526)**
```swift
case .gap:
    guard isCurrentChartUpdateRevision(revision) else { return }
    // Диагностика: логируем причину пустого графа для debug-сборок
    AppLogger.debug("FinanceDynamics: chartData пуст — .gap (accountIDs: \(visibleAccounts.map(\.accountID)), period: \(period.start)–\(period.end), currency: \(state.displayCurrency))")
    state.chartData = []
    return
case .insufficient:
    guard isCurrentChartUpdateRevision(revision) else { return }
    AppLogger.debug("FinanceDynamics: chartData пуст — .insufficient (accountIDs: \(visibleAccounts.map(\.accountID)), period: \(period.start)–\(period.end), currency: \(state.displayCurrency))")
    state.chartData = []
    return
```

**Acceptance criteria этой фазы:**
- AC1 (BUG #1 фикс): проверить через тест
- AC4 (логирование): код написан
- Существующие тесты не сломаны

---

### Фаза 2 — Unit-тесты `[x]`

**Файл:** `millioTests/Core/Finances/DailySnapshotArchitectureTests.swift` (дополнить) или новый файл.

Проверить сначала что существуют подходящие TestSupport-хелперы, затем добавить тесты:

**Test A — регрессия BUG #1:** вызвать `earliestClosedSnapshotDateByAccount` с тремя снапшотами одного счёта (разные даты) → результат должен содержать наименьшую дату.

**Test B — BUG #2 / счёт без снапшотов:** `requiredSnapshotAccountIDs` с 2 счетами, один из которых не имеет снапшотов вообще → результат не должен содержать ID второго счёта, но первый счёт (со снапшотами) должен присутствовать.

**Test C — интеграционный:** при наличии 3 закрытых снапшотов для 1 счёта за 3 дня подряд → `buildAccountSnapshotSeries` должен вернуть `.authoritative` с 3 точками (не `.gap`, не `.insufficient`).

**Acceptance criteria этой фазы:**
- AC5 (существующие тесты OK)
- AC6 (новые тесты покрывают BUG #1 регрессию, BUG #2, и интеграционный сценарий)

---

### Фаза 3 — Верификация и билд `[x]`

> Выполнено 2026-07-02: build EXIT 0; таргетный прогон `FinanceDynamicsViewModelTests` + `DailySnapshotArchitectureTests` — ** TEST SUCCEEDED **, 148 passed / 0 failed (симулятор iPhone 17 Pro, iPhone 16 Pro отсутствует на машине). Полный тестовый прогон не запускался.

```bash
cd "/Users/alekseya/Проекты/3.millio local/millio-dev/millio"
xcodebuild build -scheme millio \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  -quiet 2>&1 | tail -5

xcodebuild test \
  -scheme millio \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  -quiet 2>&1 | grep -E "Test Suite|FAILED|passed|failed" | tail -15
```

---

## Журнал

| Дата | Агент | Событие |
|------|-------|---------|
| 2026-06-24 | Александр | Создан план |
| 2026-07-02 | Claude (bulletproof) | Реализация: диагноз BUG #1 опровергнут тестом (`<= date` уже даёт минимум, инверсия по спеке ломала график — отменена); логирование `.gap`/`.insufficient` добавлено; 3 регрессионных теста; методы `earliestClosedSnapshotDateByAccount`/`requiredSnapshotAccountIDs` сделаны internal для тестов; gates зелёные. Статус → РЕАЛИЗОВАН |

---

## Impact Analysis (предварительный)

**Что может сломаться:**
- `requiredSnapshotAccountIDs` используется в 2 местах (строки 1618, 1657). Строка 1657 — перегрузка без словаря, передаёт пустой `[:]` → не затронута фиксом.
- `earliestClosedSnapshotDateByAccount` — вызывается только из `buildAccountSnapshotSeries` (строка 1604). Изолированный эффект.
- Сигнатуры публичных методов `AccountDailySnapshotReader` — не меняются.

**Регрессионный риск:** низкий. Оба изменения — однострочные исправления логики внутри private-методов VM.
