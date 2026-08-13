# Рефлексия: statement review и modern month UX

**Дата:** 2026-08-13
**Ветка:** `agent/accounts-history-source-of-truth`

## 1. Задача

Пройти оставшиеся фазы statement-review и исправить слабый UX выбора месяца/Add/Import.

## 2. Как решалась

- Код доказал, что month picker был спрятан в первой секции `List` без явной кнопки.
- Test-first добавлены typed disposition, grouping/filtering и confirmation policies.
- Month context вынесен в hero; Add/Import показывают канонический месяц.
- Review вынесен в отдельный navigation screen; confirmation — в отдельный шаг.

## 3. Решена ли

Частично: фазы 3–4 закрыты, фаза 5 реализована, но честно оставлена `implemented_pending_manual_qa`: физический iPhone отключён, ручной VoiceOver/screenshot gate не мог быть выполнен.

## 4. Эффективность

Корневая UX-проблема устранена без второго дашборда. Drive-by backend/data правок нет.

## 5. Было → стало

| Было | Стало |
|---|---|
| Месяц спрятан в list row | Явный month hero + arrows + picker label |
| Обычные Add/Import | Action cards с месяцем |
| Review внутри import hub | Dedicated review destination |
| Булевый transfer gate | Typed safe dispositions |
| Счёт до review | Счёт на confirmation step |

## 6. Идеи по улучшению

- Процесс: physical-device availability нужно проверять до финального gate, а не после regression suite.
- Следующий QA: подключить iPhone, пройти compact/large, VoiceOver, AX5 и снять acceptance screenshots.

## 7. Дополнение: счета в confirmation

- До фикса picker читал только stale `availableCards`, поэтому AccountsCore-счета не показывались.
- После фикса используется общий `CashflowSelectableAccountResolver`: старые карты + активные AccountsCore cash/debit/bank accounts, валютный фильтр и apply-time revalidation.
- Focused tests и signed generic iOS build зелёны. Широкий Finance gate всё ещё падает только на ранее зафиксированном baseline `duplicateCardsStayConsistentAcrossModules`.
