# Spec: Account Ledger Mutation Service
**Date:** 2026-06-21
**Author:** Алексей (требования) + архитектурный аудит

---

## Problem

Система денежных мутаций в Millio нарушает главный финансовый инвариант:
`account.balance` и ledger (история транзакций) могут разойтись при ошибке
сохранения, падении сети или transfer с недостающим destination-счётом.

Конкретные точки отказа:
- `CashflowPersistenceService` мутирует in-memory баланс до `modelContext.save()`,
  при throw из save возвращает `false` не откатывая изменения.
- Transfer валидирует только source-карту; если destination архивирована — средства
  списываются без зачисления.
- Неизвестный `transactionTypeRaw` молча становится `.expense`, знак delta меняется.
- Исторические снапшоты не инвалидируются при редактировании прошлых транзакций,
  графики показывают устаревшую реальность.

---

## Goal

Создать единый надёжный слой мутаций (`AccountLedgerMutationService`), в котором:
- `account.balance` никогда не расходится с ledger — даже при crash или throw
- Transfer гарантированно проверяет обе стороны до любой мутации
- Повреждённые данные обнаруживаются явно, не молча конвертируются
- Графики истории остаются консистентными после backdated редактирований

---

## Scope

### In Scope

- Defensive rollback: `modelContext.rollback()` при любом throw после мутации баланса
- `MutationPlan` struct: capture validate → apply → save | rollback в одном месте
- Transfer: валидация `toCardID` (существует, не архивирована, доступна) до apply
- `CashflowTransactionType.unknown(String)`: fail-fast вместо `?? .expense`
- `AccountBalanceHistoryStore.invalidate(from: Date)`: вызов при backdated transaction
- Failure-path unit-тесты: save failure, invalid rawValue, transfer с missing destination
- Отделение финансовых тестов от Firebase binary (отдельный test plan или mock target)

### Out of Scope

- Перепроектирование модели `Card` или `CashflowTransaction` (SwiftData schema)
- Декомпозиция `CashflowViewModel` (отдельная задача, spec 2026-05-03)
- CloudKit sync снапшотов (отдельная задача)
- Миграция снапшотов в SwiftData (следующий этап после этой задачи)
- UI изменения (ошибки уже показываются, меняется только propagation)

---

## Acceptance Criteria

### Rollback (C-1)
- [ ] При любом throw из `modelContext.save()` после мутации баланса —
      `modelContext.rollback()` вызывается до возврата из сервиса
- [ ] `account.balance` после catch равен значению до вызова метода
- [ ] Ошибка propagates как `throw`, не глотается через `return false`
- [ ] Существующие happy-path тесты (`FinanceLifecycleIntegrationTests`) проходят без изменений

### Transfer validation (H-5)
- [ ] При создании transfer с отсутствующим/архивированным `toCardID` —
      выбрасывается ошибка до любой мутации баланса
- [ ] `source.balance` не изменяется если transfer отклонён по destination
- [ ] Тест: transfer с missing destination → source баланс неизменен

### Fail-fast enum (C-2)
- [ ] `CashflowTransactionType` содержит кейс `.unknown(String rawValue)`
- [ ] `balanceDelta(for:)` для `.unknown` выбрасывает ошибку, не применяет delta
- [ ] Importer при неизвестном rawValue выбрасывает `throw`, не `?? .expense`
- [ ] При обнаружении `.unknown` в существующих данных транзакция помечается `isCorrupted = true`
      и не влияет на баланс
- [ ] Тест: транзакция с rawValue="future_type" → ошибка, баланс не изменён

### Snapshot invalidation (H-1)
- [ ] При сохранении/редактировании транзакции с `transactionDate < now() - 1 день`
      вызывается `AccountBalanceHistoryStore.invalidate(from: transactionDate)`
- [ ] `invalidate(from:)` удаляет все снапшоты начиная с указанной даты
- [ ] Тест: backdated edit → соответствующий диапазон в store очищен

### Test infrastructure
- [ ] Финансовые unit-тесты запускаются без Firebase (через mock или отдельный test plan)
- [ ] Failure-path тесты: save throw → rollback (мок ModelContext), rawValue corruption, transfer missing dest

---

## Constraints

- Swift Concurrency: все мутации на `@MainActor` (как сейчас в CashflowPersistenceService)
- SwiftData: `ModelContext.rollback()` уже существует, не требует зависимостей
- Обратная совместимость данных: `isCorrupted` — новое опциональное поле, не ломает существующие записи
- Тесты: не мокировать `ModelContext` там где можно использовать in-memory SwiftData
- Scope ограничен: не трогать `CashflowViewModel` и `FinanceViewModel` глубже callers

---

## Non-Goals

- Не вводить полноценную транзакционность уровня БД (ACID) — SwiftData не поддерживает
- Не переписывать весь `CashflowPersistenceService` — только добавить rollback-слой
- Не менять UX отображения ошибок — ошибки уже показываются через существующие механизмы
- Не делать async batch-пересчёт истории снапшотов (только инвалидация, пересчёт будет при следующем open)
