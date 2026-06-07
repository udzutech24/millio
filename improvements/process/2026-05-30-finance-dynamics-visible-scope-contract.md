# Finance Dynamics Must Share Visible Scope

## Наблюдение

Верхний chart/header и нижний breakdown использовали разные наборы счетов:
breakdown скрывал архивные счета по умолчанию, а chart/header всегда включали их
через `includeArchivedForHistory: true`.

## Правило

Для current-mode экрана финансов chart, header и breakdown обязаны использовать
один visible-scope contract. Архивные счета можно включать только явным фильтром
или отдельным historical API.

## Regression-тест

Создать видимый и архивный счета с разными суммами и проверить:

- start/end графика совпадают с суммой start/end нижнего breakdown;
- header current balance совпадает с нижним end value;
- header delta совпадает с нижней дельтой.
