# Рефлексия: создание счёта из выписки, Phase 3

**Дата:** 2026-08-16

## 1. Задача

Подключить атомарное ядро создания счёта из выписки к существующей форме создания продукта и переиспользовать текущий Cashflow review.

## 2. Как решалась

- CTA добавлен только для дебетовой карты и банковского счёта.
- Существующий `CashflowStatementImportController`, category resolver, disposition policy и `CashflowStatementReviewView` переиспользованы через явный review context.
- Pending account ID фиксируется до preview, поэтому account picker в onboarding отсутствует.
- Добавлен balance resolver: bank-declared closing point имеет приоритет; иначе нужны ручные amount, `as of` date и явное подтверждение.
- Финальное действие строит reviewed operations общим builder и вызывает coordinator Phase 2.
- Побочные refresh/learning публикуются только после успешного durable commit.

## 3. Решена ли

- [x] Да, Phase 3 реализована.
- [ ] Внешнее открытие файла через Files/Share Sheet не входит сюда — Phase 3A.
- [ ] Скриншоты, Dynamic Type, VoiceOver и полный перевод нового copy остаются Phase 4.

## 4. Эффективность решения

Решение узкое: второй parser, controller или review screen не создавались. Тяжёлая часть сохранения не перенесена в SwiftUI. Общий builder убрал расхождение между обычным импортом и onboarding.

## 5. Было → стало

| Область | Было | Стало |
|---|---|---|
| Create-flow | Только ручное создание | Опциональная выписка для debit/bank account |
| Review | Только Cashflow import | Один review с двумя явными context |
| Target account | Пользователь выбирает существующий | Pending account ID фиксирован, picker скрыт |
| Остаток | Только поле формы | Bank evidence либо explicit manual amount/date |
| Save | Manual account factory | Atomic onboarding coordinator |

## 6. Стресс-проверка

- Mixed currency, multi-month, reconciliation failure, backend failure и existing fingerprint блокируют persistence.
- Cancel/back не сохраняют graph и не уничтожают поля родительской формы.
- Смена продукта или переход карты в credit инвалидирует statement draft.
- Ноль одобренных строк допустим только для подтверждённого balance snapshot; пустой обычный Cashflow import не ослаблен.

## 7. Проверки

- Focused create-flow/controller/coordinator/apply gate: 29/29.
- Localization catalog regression: 16/16.
- All visible product presets regression: 5 suites/tests, включая parameterized cases, green.
- Simulator build-for-testing: green.
- Commit, push, backend deploy и device install не выполнялись.

## 8. Что дальше

По отдельной guard phrase перейти к Phase 3A: безопасный `Open in Millio` и deferred `Save to Millio` через Share Extension.
