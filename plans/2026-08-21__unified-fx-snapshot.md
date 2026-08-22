# Plan: единый FX snapshot

## Inputs

- Research: `thoughts/research/2026-08-21-unified-fx-snapshot.md`
- Spec: `specs/2026-08-21-unified-fx-snapshot.md`

## Decision

- Chosen approach: `CurrencyRateService` хранит и публикует один полный snapshot; стандартный fallback — Millio → ER-API.
- Rejected alternatives: отдельные cache-инвалидации экранов и fallback на уровне каждого consumer.
- Rollback strategy: удаление snapshot revision возвращает прежнее поведение без миграции финансовых данных; пользовательские данные не меняются.

## Phases

- [x] Phase 8 — общий snapshot, единая revision, consumer-обновления и тесты.

## Verification

- Unit tests: `CurrencyRateServiceTests`, `ConverterViewModelTests`, `FinanceDynamicsSnapshotStoreTests`.
- Integration/build checks: iOS simulator build/test, signed physical-device build and install without deleting app data.
- Acceptance criteria audit: выполнен после тестов и установки.
