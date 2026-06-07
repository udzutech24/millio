# xcodebuild -only-testing всё равно собирает UITests runner

**Date:** 2026-06-07
**Category:** process
**Status:** OPEN
**Priority:** MEDIUM
**Author:** Codex

## Что произошло

В Phase 0 запуск точечной проверки:

```bash
xcodebuild test -scheme millio -destination 'platform=iOS Simulator,id=49601B0B-FAE4-4039-94BA-B333C5DFCAAB' -derivedDataPath /tmp/millio-phase0-derived -only-testing:millioTests/FinanceDynamicsViewModelTests
```

запустил нужный unit suite, но перед этим собрал и `millioUITests-Runner.app`. Для фазовых проверок это лишнее время, шум в логе и больше шанс упереться в инфраструктурный сбой, не связанный с изменением.

## На какой стадии

- [x] Implementation (gates не работали / self-audit пропущен)

## Что именно не сработало

Текущий `millio` scheme, похоже, включает UI test target в build action даже при `-only-testing:millioTests/...`. Из-за этого "маленькая" проверка контракта становится дорогой и менее диагностичной.

## Предложение

- [ ] Добавить отдельный shared scheme `millioUnitTests` без UI test target.
- [ ] Либо документировать быстрый gate-командлет для фаз, где достаточно unit tests.
- [ ] В планах указывать не только `-only-testing`, но и ожидаемый scope сборки, если это важно.

## Как измерим что помогло

Phase-level unit проверки больше не строят `millioUITests-Runner.app`; лог короче, cold run быстрее, failures относятся к app/unit target.

## Ссылки

- Сессия: [2026-06-07-finance-balance-contract-phase-0.md](../../../.business/история/2026-06-07-finance-balance-contract-phase-0.md)
- Связанный план: [plans/2026-06-07__finance-balance-contract.md](../../plans/2026-06-07__finance-balance-contract.md)
