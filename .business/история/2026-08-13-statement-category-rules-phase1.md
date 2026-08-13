# Рефлексия: statement category rules Phase 1

**Дата:** 2026-08-13
**Ветка:** `agent/accounts-history-source-of-truth`

## 1. Задача

Реализовать фазу 1: зафиксировать общую taxonomy и добавить детерминированные категории Alfa XLSX без deployment.

## 2. Как решалась

- Доказан hardcoded `other/0.35` в adapter.
- Test-first добавлены matcher/golden/negative/parity contracts.
- Вынесен pure normalization/rule matcher; кириллическая ошибка `\b` поймана первым прогоном и устранена.
- Runtime contract стал блокировать custom/unknown/wrong-kind IDs.
- Taxonomy fixture зеркалирован в iOS и сверен с enum-ами.

## 3. Решена ли

- [x] Да, фаза 1 закрыта.

## 4. Эффективно ли

Да. Правила малы, чисты и объяснимы; LLM/новая зависимость не добавлялись. Drive-by правок нет. Backend tests 50/50 и build зелёны; iOS parity зелёный. Новые matcher/taxonomy проходят ESLint; full-folder lint остаётся красным на pre-existing untracked adapter/spec, которые не были массово переформатированы.

## 5. Было → стало

| Область | Было | Стало |
|---|---|---|
| Suggestions | Всегда `other/0.35` | Консервативные high-confidence rules |
| Taxonomy | Строка без runtime parity | Versioned backend/iOS fixture |
| Boundary | Любой category ID | Только system ID нужного kind |
| Unknown input | `other` | По-прежнему safe `other/0.35` |

## 6. Идеи по улучшению

- Агенты: 0.
- Токены: 0.
- Процесс: fixture test доказал, что JS `\b` нельзя считать Unicode-boundary; отдельный improvement не нужен, проблема закреплена negative/positive tests.
- Бизнес: 0.

## 7. Артефакты

- Commit/push/deploy: не выполнялись.
- Plan/status/handoff обновлены; Phase 1 = complete.

## 8. Что дальше

Только по явной guard phrase перейти к Phase 2: iOS resolver, validation, precedence и safe learning lifecycle.
