# Clean-context boundary требует заранее сохранённых prerequisites

**Date:** 2026-08-09
**Category:** agents
**Status:** DONE
**Priority:** MEDIUM
**Author:** Codex

## Что произошло

`LegacyAccountsMigrator` создавал `AccountGroup`, после чего вызывал `LegacyAccountConverter`.
Converter корректно отвергал грязный `ModelContext`, поэтому grouped accounts не мигрировали.

## Почему это проблема

Локально корректные компоненты образовали неверную композицию, а ошибка выглядела как проблема
исторической оценки и создавала ложную уверенность в независимом падении тестов.

## Корень

Не был обозначен transaction boundary между созданием prerequisite и atomic converter operation.

## Предложение

- [x] Перед вызовом компонента с clean-context guard сохранять или включать prerequisite в его
  собственную атомарную операцию; при ошибке откатывать prerequisite.
- [x] Покрывать композиционный путь grouped fixture, а не только converter изолированно.

## Как проверим что внедрение сработало

Focused `LegacyAccountsMigratorTests` и grouped cases в
`FinanceDynamicsCoreContributionTests` проходят вместе.

## Ссылки

- Сессия: [Phase 5 device acceptance](../../.business/история/2026-08-09-phase5-device-acceptance-and-publish.md)
- Связанный plan: [Accounts history source of truth](../../plans/2026-08-08__accounts-history-source-of-truth.md)
- Commit внедрения: `5ae6ff8`.
