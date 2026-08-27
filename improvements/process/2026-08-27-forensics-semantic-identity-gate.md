# Форензик-аудит должен проверять семантическую идентичность до объявления дублей

**Date:** 2026-08-27
**Category:** process
**Status:** OPEN
**Priority:** HIGH
**Author:** Codex

## Что произошло

В `thoughts/research/2026-08-27-full-data-audit.md` несколько аномалий были
классифицированы по упрощённым ключам, которые не совпадают с контрактами кода:
`HistoricalPortfolioValuation` сравнивались по дню без input revision,
legacy `opaqueAccountID` проверялись только против core `Account`, а пары
архивный → новый `Account` по имени считались recovery-дублями без проверки
маркера product transition.

## На какой стадии

- [x] Research (не нашли / поверхностно)
- [ ] Spec (неполные acceptance criteria / размытые non-goals)
- [ ] Plan (пропущены edge cases / слишком крупные фазы / Challenge Log формален)
- [ ] Implementation (gates не работали / self-audit пропущен)
- [x] Review / Security scan
- [ ] Handoff (в новой сессии не понял что делать)
- [ ] Рефлексия (забыл / формальная)

## Что именно не сработало

Отчёт смешал физические повторы, допустимые immutable revisions, migration
boundary IDs и настоящие конфликты. Для части находок не показан активный
reader и пользовательский эффект. Сырые выкладки и точные запросы, на которые
ссылается отчёт, в workspace отсутствуют, поэтому числа нельзя независимо
воспроизвести.

## Предложение

- [ ] Поправить шаблон forensic research: для каждой находки обязательны
  canonical key из кода, допустимые исключения, active reader/writer, impact,
  запрос/скрипт воспроизведения и безопасный repair boundary.
- [ ] Добавить gate: запрещать data cleanup, пока кандидат не прошёл
  классификацию `confirmed corruption / intentional history / derived cache /
  unproven anomaly` и dry-run не выдал проверяемый receipt.
- [ ] Добавить к отчёту SHA-256 источника, версию схемы/сборки и сохранённые
  агрегированные запросы без персональных финансовых данных.

## Как измерим что помогло

Следующий полный аудит не объявляет product transitions, revisioned closes и
legacy boundary IDs дублями; все P0/P1-находки воспроизводятся одним локальным
скриптом и имеют ссылку на реальный consumer.

## Ссылки

- Сессия: [2026-08-27-full-data-audit-review.md](../../.business/история/2026-08-27-full-data-audit-review.md)
- Research: [2026-08-27-full-data-audit.md](../../thoughts/research/2026-08-27-full-data-audit.md)
