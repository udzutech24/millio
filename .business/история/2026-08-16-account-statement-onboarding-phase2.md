# Рефлексия: создание счёта из выписки, Phase 2

**Дата:** 2026-08-16

## 1. Задача

Собрать persistence-core для создания банковского счёта из уже проверенной выписки: один атомарный Account graph, подтверждённый balance anchor и Cashflow-проекции без двойного изменения баланса.

## 2. Как решалась

- Из существующего apply-сервиса выделен persistence-neutral stager без собственного `save`, rollback и публикации событий.
- Добавлен узкий onboarding command и координатор поверх `AccountProductFactory.graphEnricher`.
- Финальная команда повторно проверяется непосредственно перед записью: продукт, валюта, месячный диапазон, открытость месяца, fingerprints, категории, привязка и подтверждение баланса.
- Локальные writers сериализованы на `MainActor`; стабильный onboarding marker, digest и deterministic IDs обеспечивают идемпотентный retry.
- Для импортированных Cashflow-строк scope merge использует `source + fingerprint`, а не случайное время создания.

## 3. Решена ли

- [x] Да, persistence-core Phase 2 реализован.
- [ ] UI create-flow не подключён: это Phase 3.
- [ ] Межустройственная CloudKit-атомарность не обещается; partial graph recovery остаётся gate Phase 4.

## 4. Было → стало

| Область | Было | Стало |
|---|---|---|
| Apply выписки | Сам валидирует и сохраняет | Общий stager, save принадлежит boundary |
| Создание счёта | Отдельный account save | Один Account + anchor + Cashflow commit |
| Retry | Check-then-save без uniqueness | Serialized writer + marker/digest + deterministic IDs |
| Fingerprint conflict | Duplicate мог быть только пропущен | Чужая/неопределённая привязка fail closed |
| Scope merge | Identity зависела от локального `uniqueID` | Import source + fingerprint сходятся между scope |

## 5. Что выявил стресс-тест

Экспорт Cashflow сохранял import provenance, но импортёр её игнорировал. Поэтому одинаковая банковская строка после guest→user round-trip переставала быть одинаковой. Контракт round-trip исправлен; это был реальный дефект, а не косметика.

## 6. Проверки

- `AccountStatementOnboardingCoordinatorTests`, `CashflowStatementApplyServiceTests`, `ScopeMergeWorkerTests`: 26/26 green.
- `AccountProductFactoryTests`: 8/8 regression tests green.
- Проверены success, zero rows, duplicate request, conflict, changed retry, concurrent double apply, closed-month race, injected failures и durable save rollback.
- Production/backend/schema/deploy не изменялись.

## 7. Ограничения

SwiftData save атомарен только внутри локального store. CloudKit может доставлять объекты частично и не предоставляет межустройственную транзакцию этого graph. Детерминированная identity закрывает duplicate convergence, но полноценный detection/repair partial graph должен быть доказан интеграционно в Phase 4.

## 8. Что дальше

Только по guard phrase перейти к Phase 3: подключить существующий review к форме создания debit/bank account, сохранив ручной create-flow без изменений.
