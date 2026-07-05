# Дедуп BudgetCategoryLimit + защита QuickSetupApplier

**Дата:** 2026-07-05
**Статус:** РЕАЛИЗОВАН
**Ветка:** `fix/budget-limit-dedup` (не мержено, не запушено)

## Проблема

Адверсарное расследование подтвердило две уязвимости того же класса, что уже закрытый прод-краш
`Fatal error: Duplicate values for key` в дублях custom-категорий (Cashflow/Cashback):

1. **BudgetCategoryLimit нигде не дедуплицируется.** `dedupeAll` его не покрывал, у модели нет
   `@Attribute(.unique)`. CloudKit-merge/восстановление бэкапа могут создать два лимита на одну
   категорию внутри одного бюджетного плана. `Dictionary(uniqueKeysWithValues:)` по
   `categoryRawValue` в `CashflowViewModel+History.swift` (`monthlyBudgetSummary`,
   `previousMonthlyBudgetSuggestion`, `saveBudgetConfiguration`) падает на таких дублях.
2. **QuickSetupApplier** строит `Dictionary(uniqueKeysWithValues:)` по `normalizedName` существующих
   `CashflowCustomCategory` — падает при двух категориях с одинаковым именем (например, после
   импорта старого бэкапа с дублями). Краш на онбординге недопустим.

## Ключ уникальности BudgetCategoryLimit

`(budgetID, categoryRawValue)`. `BudgetPlan.budgetID` уникален на план (свой на каждый
период × `categoryKind` — `fetchBudgetPlan(matching:categoryKind:)`), поэтому один и тот же
`categoryRawValue` в разных планах — НЕ дубль. `categoryKindRaw` в ключ не добавлен: это атрибут
самого `BudgetPlan`, а не независимая ось — в рамках одного `budgetID` он у всех лимитов совпадает
по построению.

Победитель — более поздний `updatedAt` (то же правило, что в существующих дедупах категорий).

## Решение

### Фаза 1 — DataIntegrityCleaner.dedupeBudgetCategoryLimitsOnLaunch [x]
- `millio/Core/Repository/DataIntegrityCleaner.swift`: новый метод `dedupeBudgetCategoryLimitsOnLaunch`
  + приватный `dedupeBudgetCategoryLimits`, включён в `dedupeAll`.
- Без одноразового UserDefaults-флага — по той же причине, что у Cashflow/Cashback: guest-стор
  открывается первым `DIContainer.create()` до `restoreSession`, общий флаг сгорел бы там.
- `millio/Core/DI/DIContainer.swift`: вызов добавлен рядом с существующими дедупами в `create()`.

### Фаза 2 — Runtime defense-in-depth [x]
- `millio/UI/Services/Cashflow/Budget/BudgetCategoryLimit.swift`: новый статический
  `dedupedByCategoryRawValue(_:)` (по образцу `CashflowCategoryService.dedupedCustomCategories`).
- `millio/UI/Services/Cashflow/CashflowViewModel+History.swift:201,253,332` (было) — все три
  `Dictionary(uniqueKeysWithValues:)` по лимитам теперь строятся из
  `BudgetCategoryLimit.dedupedByCategoryRawValue(...)`.

### Фаза 3 — QuickSetupApplier [x]
- `millio/UI/QuickSetup/QuickSetupApplier.swift:86`: `Dictionary(uniqueKeysWithValues:)` заменён на
  `Dictionary(_:uniquingKeysWith:)`, победитель — более поздний `updatedAt`.

### Фаза 4 — Тесты [x]
- `millioTests/Core/DataIntegrityCleanerBudgetLimitDedupTests.swift` (6 тестов, Swift Testing):
  дедуп одинакового ключа, различие по `budgetID`, повторные запуски, guest→user сценарий,
  пустой store, runtime `dedupedByCategoryRawValue`.
- `millioTests/UI/QuickSetup/QuickSetupApplierTests.swift`: добавлен
  `testApplyDoesNotCrashOnDuplicateNormalizedNameInExistingCustomCategories` (XCTest).

## Итог тестов

```
xcodebuild test -scheme millio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:millioTests/DataIntegrityCleanerBudgetLimitDedupTests \
  -only-testing:millioTests/QuickSetupApplierTests
```
Все тесты (6 новых + 8 существующих QuickSetupApplierTests, включая новый регрессионный) — **passed**.
Полный прогон сьюта не запускался (не требовался по объёму задачи).

## Не покрыто / вне скоупа

- Backup-импортёр (`import(_:)` в `BudgetCategoryLimit`) вставляет без проверки на дубли — это
  ожидаемо: дочистка происходит на следующем `DIContainer.create()` через `dedupeAll`/
  `dedupeBudgetCategoryLimitsOnLaunch`, отдельный guard в самом импортёре не требуется (тот же
  паттерн, что у Cashflow/Cashback custom-категорий).
- `@Attribute(.unique)` на `BudgetCategoryLimit` сознательно не добавлен в этом релизе — по той же
  причине, что и у custom-категорий: лайтвейт-миграция с unique-constraint при существующих дублях
  ломает открытие контейнера целиком. Отдельный релиз после того, как патч гарантированно прогонится
  на установленных копиях.
