# Рефлексия: statement category resolution Phase 2

**Дата:** 2026-08-13
**Ветка:** `agent/accounts-history-source-of-truth`

## 1. Задача

Реализовать iOS resolver категорий, безопасное обучение и apply-result с точными fingerprint sets.

## 2. Как решалась

- Test-first зафиксированы precedence, fail-closed validation, custom category, ambiguous merchant и lifecycle learning.
- Resolver отделён от SwiftUI и persistence.
- Merchant prefs закрыты narrow protocol; full bank description не может стать learning key.
- Apply возвращает inserted/skipped sets; controller обучается только по inserted corrections.

## 3. Решена ли

- [x] Да, фаза 2 закрыта.

## 4. Было → стало

| Область | Было | Стало |
|---|---|---|
| Category suggestion | Backend ID или `other` | Validated layered resolution |
| Learning | Нет lifecycle boundary | Только confirmed + successful + inserted |
| Duplicate apply | Только count | Exact inserted/skipped fingerprints |
| Local duplicate | Виден лишь на apply | Аннотирован и исключён в review |

## 5. Проверки

- Focused resolver/apply/controller suite: green.
- Statement/taxonomy/bulk-import/category regression suite: green.
- Signed physical-device Release build: green.
- Backend/data/commit/push/deploy: не выполнялись. Штатный Crashlytics build phase сообщил о фоновой отправке symbols во время обязательной signed build.

## 6. Что дальше

Только по явной guard phrase перейти к Phase 3: typed transfer/exclusion disposition policy.
