# Finance Account Lifecycle Contract

## Наблюдение

Lifecycle продукта и lifecycle его `FinanceAccount` link расходятся:

- новый продукт сохранён, но account cache не обновлён до рендера групп;
- архивирование продукта иногда сопровождается удалением link, нужного истории.

## Правило

После create/update/archive проверять три слоя как единый контракт:

1. underlying model (`Card` / `Credit` / `Investment`);
2. `FinanceAccount` link;
3. account caches, из которых UI резолвит link.

Архивирование не равно физическому удалению link. Для replay link сохраняется.

## Regression-тесты

- add: новая карта видна сразу без ручного reload;
- archive: current scope скрывает счёт;
- history: historical scope видит счёт до `archivedAt`;
- delete group: links сохранены.
