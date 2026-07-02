# Research: Account Ledger Mutation Service
**Date:** 2026-06-21
**Task:** Архитектурный аудит + проектирование надёжного слоя денежных мутаций

---

## Источники

- Аудит millio-audit (агент, 2026-06-21) — full codebase scan
- Stress-test (агент, 2026-06-21) — 10 причин провала
- Ревью Алексея (2026-06-21) — ручная проверка кода
- Чтение CashflowPersistenceService.swift:229–435

---

## Что обнаружено

### Критические проблемы (подтверждены живым кодом)

**C-1: Нет rollback при падении save()**
Файл: `CashflowPersistenceService.swift:229–305`
```
applyAccountBalanceEffect(.revert)  // карта мутирована в памяти
existing.hasAppliedBalanceEffect = false
applyAccountBalanceEffect(.apply)   // карта мутирована снова
// ...
try modelContext.save()             // если throws — in-memory грязный, on-disk старый
catch { return false }              // ← проглатывает, баланс не откатывается
```
`ModelContext.rollback()` нигде не вызывается. SwiftData имеет этот метод и он
сбрасывает все несохранённые in-memory изменения к последнему save.

**C-2: Silent .expense fallback при битом rawValue**
Файл: `CashflowTransaction.swift:797`
```swift
CashflowTransactionType(rawValue: transactionTypeRaw) ?? .expense
```
CloudKit merge-конфликт или импорт со старой версией enum → тип становится расходом молча.
`balanceDelta()` применяет неверный знак → баланс уплывает без алерта.

**H-5: Transfer валидирует только source**
Файл: `CashflowPersistenceService.swift:351–364`
```swift
case .transfer:
    guard let fromCardID = transaction.cardID else { return false }
    return try await isAmountAvailable(amount:..., fromCardID: fromCardID, ...)
    // toCardID НЕ проверяется
```
Файл: `CashflowPersistenceService.swift:418–425`
```swift
let resolvedCards = impactedCardIDs.compactMap { cardID -> (String, Card)? in
    guard let card = cardProvider(cardID) else { return nil }  // ← silent skip
    return (cardID, card)
}
```
Если destination-карта удалена/архивирована: source списывается, destination пропускается.

**H-1: Снапшоты не инвалидируются при backdated edit**
Файл: `AccountBalanceHistoryStore.swift`, `AccountBalanceSnapshotService.swift:27`
Один снапшот в сутки, только при открытии дашборда. При редактировании прошлой
транзакции баланс счёта корректно пересчитывается, но исторические снапшоты — нет.
Графики показывают старую реальность навсегда.

### Уже работает (лучше, чем думали)

- `hasAppliedBalanceEffect` корректно отслеживает применение эффекта
- Интеграционные тесты в `FinanceLifecycleIntegrationTests.swift:27` покрывают happy path
- `revertTransactionsForDelete` корректен при удалении
- Архивация (soft delete) работает правильно, история сохраняется

### Не работает инфраструктура тестов

Firebase/Google ZIP-артефакты мешают запуску unit-тестов локально.
Финансовые policy-тесты не должны зависеть от аналитики.

---

## Паттерн решения (из SwiftData документации и практики)

SwiftData `ModelContext`:
- `save()` персистирует in-memory → on-disk. Throws при ошибке.
- `rollback()` сбрасывает все in-memory изменения к состоянию последнего save.
- Не существует `beginTransaction()` / `commit()` — это не RDBMS.
- Эмулировать транзакцию можно через: capture beforeState → mutate → save → catch { rollback }

Правильный паттерн:
```swift
func commit(plan: MutationPlan) async throws {
    try plan.validate()          // все cardID резолвятся, суммы OK
    await plan.applyDeltas()     // только in-memory мутации
    do {
        try modelContext.save()  // persist
    } catch {
        modelContext.rollback()  // reset in-memory к last save
        throw error              // propagate, не глотать
    }
}
```

---

## Альтернативы

**A: Точечные патчи** — добавить `modelContext.rollback()` в каждый catch в CashflowPersistenceService
- Плюс: минимально инвазивно
- Минус: дублирование, следующий разработчик снова забудет
- Решение: промежуточный шаг, но не финальная архитектура

**B: AccountLedgerMutationService** (рекомендовано)
- Единственная точка записи balance + transaction
- Явный контракт: validate → apply → save | rollback
- Тестируется изолированно от UI
- Минус: рефакторинг callers в CashflowViewModel и FinanceViewModel

**C: Core Data NSManagedObjectContext savepoint** — не применимо, SwiftData не поддерживает

---

## Вывод

Выбрать B (AccountLedgerMutationService) в 4 фазы:
1. Defensive rollback — быстрая защита без архитектурных изменений
2. Transfer validation — обе стороны до мутации
3. Fail-fast enum — .unknown(String) вместо ?? .expense
4. Snapshot invalidation — при backdated edit инвалидировать диапазон
