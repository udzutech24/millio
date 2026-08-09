# Рефлексия сессии: Accounts history final plan

**Дата:** 2026-08-08
**Автор:** Codex
**Ветка / PR:** не создавались

## 1. Задача

Прочитать дополнительный independent review
`thoughts/research/2026-08-08-accounts-history-plan-review.md` и собрать итоговый implementation plan.

## 2. Как решалась

- Сопоставлены выводы review, предыдущего adversarial audit и текущего кода.
- Перепроверены CloudKit/store scope, `LegacyAccountConversion`,
  `LegacyConversionRegistry`, create/save paths и schema constraints.
- Десятифазный draft заменён на итоговый граф из независимых
  valuation/product tracks и фаз cutover.
- Обновлён status sidecar; production code и spec не менялись.

- Research: [`thoughts/research/2026-08-08-accounts-history-plan-review.md`](../../thoughts/research/2026-08-08-accounts-history-plan-review.md)
- Spec: [`specs/2026-08-07-accounts-history-source-of-truth.md`](../../specs/2026-08-07-accounts-history-source-of-truth.md)
- Plan: [`plans/2026-08-08__accounts-history-source-of-truth.md`](../../plans/2026-08-08__accounts-history-source-of-truth.md)

## 3. Решена ли

- [x] Полностью для текущего Stage 3: итоговый plan и status созданы.

Код не реализовывался. Phase 0 должна сначала синхронизировать spec с
итоговыми решениями.

## 4. Эффективно ли

- Drive-by production changes: нет.
- Упрощение: удалены ложные live-CloudKit guarantees, full-event SHA-256,
  обязательная product→valuation dependency и полуреализация conversion.
- Gates: JSON parse и `git diff --check` прошли; tests/build не запускались, так как код
  не менялся.
- AC: в plan есть полный mapping; нормативный spec будет исправлен в Phase 0.

## 5. Было → Стало

| Область | Было | Стало |
|---|---|---|
| Фазы | 10 жёстко последовательных фаз | 8 execution phases с параллельными V/P tracks |
| Product identity | Блокировал valuation fix | Optional valuation input; отдельный writer track |
| Storage | Live CloudKit winner assumptions | Local scope + encrypted backup/restore semantics |
| Fingerprint | Full-event SHA-256 | Revisions; rolling digest only if writer inventory insufficient |
| Conversion | Неопределённый successor mechanism | In-place guard; full conversion вынесена в future spec |

## 6. Идеи по улучшению

### Агенты

- Review назвал device-local registry persisted link и сделал слишком сильный migration
  вывод.
- Зафиксировано: `improvements/agents/2026-08-08-persisted-link-evidence.md`.

### Токены / контекст

- 0 новых наблюдений.

### Процесс

- Большой plan не должен объявлять READY, пока Open Questions spec определяют
  key/storage semantics. Вывод закрыт самим итоговым plan; отдельный improvement не нужен.

### Бизнес

- 0 новых наблюдений.

## 7. Артефакты и коммиты

- Коммиты: не создавались.
- Обновлёны: plan, status, эта рефлексия и agent-improvement.
- План: `plans/2026-08-08__accounts-history-source-of-truth.md` —
  `READY FOR PHASE 0 ONLY`.

## 8. Что для следующей сессии

Начинать только после явной команды `Реализуй фазу 0 по плану`. Первый шаг —
исправить normative spec, затем добавить red characterization tests; production code в Phase 0
не менять.
