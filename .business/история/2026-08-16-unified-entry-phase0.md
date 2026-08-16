# Unified Entry redesign: Phase 0

Date: 2026-08-16

## 1. Какая задача была поставлена

Реализовать Phase 0 плана Unified Entry: измеримые signpost-границы, обезличенный performance fixture, baseline на целевом iPhone и точный контракт `upcoming/paid/all`.

## 2. Как задача решалась

- В Unified Entry добавлены privacy-safe signposts для tab transition и monthly snapshot load.
- Добавлен изолированный perf-mode с 1 152 детерминированными синтетическими операциями.
- Введён чистый status policy: recurring link только по `series + type + calendar day`; one-time plan оплачен только после applied effect.
- Добавлены unit- и UI-performance tests, runbook baseline и status sidecar плана.

## 3. Решена ли задача

Частично. Код, fixture и контракт готовы; focused unit gate зелёный. Physical baseline не снят: iPhone был заблокирован, затем стал unavailable; fresh build также блокируется незавершённым чужим Share Extension.

## 4. Эффективно ли решение

Да, в доступной части. Production UI не менялся, performance data не содержит PII, а симуляторный результат не выдан за physical baseline.

## 5. Как было до и как стало

| Область | До | Стало |
|---|---|---|
| Performance | Тормоз только по ощущению | Есть воспроизводимый fixture, signposts и physical test harness |
| History | Нет формальной семантики paid/upcoming | Есть pure policy и тесты связи/фильтра/порядка |
| UI | Текущий экран | Без визуальных изменений, как и требует Phase 0 |

## 6. Идеи по улучшению

- Агенты: 0 новых наблюдений.
- Токены/контекст: 0 новых наблюдений.
- Процесс: dirty parallel feature может блокировать scheme-wide gate; зафиксировано в baseline runbook, без drive-by исправления чужой фичи.
- Бизнес: 0 новых наблюдений.

## 7. Артефакты

- `docs/UNIFIED_ENTRY_PERFORMANCE_BASELINE.md`
- `plans/2026-08-16__unified-entry-redesign.md` — `IN PROGRESS`
- Коммиты: нет.

## 8. Что дальше

Завершить Share Extension build/provisioning в его задаче, разблокировать `iPhone A (2)` и повторить physical baseline из runbook. Только после этого закрыть Phase 0.
