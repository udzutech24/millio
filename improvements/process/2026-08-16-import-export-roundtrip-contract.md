# Import/export должны проверяться как один round-trip контракт

## Наблюдение

Cashflow exporter уже сохранял `importSourceRaw` и `importReferenceKey`, но importer их не восстанавливал. Обычные export/import тесты по отдельности оставались зелёными, а statement fingerprint терялся только при реальном scope merge.

## Правило

При добавлении identity/provenance поля в переносимый payload обязательны два доказательства:

1. exporter записывает поле;
2. round-trip `model -> payload -> model` сохраняет семантическую identity, включая backward-compatible payload без нового поля.

Изолированный тест только exporter или только importer недостаточен.

## Ожидаемый эффект

Меньше скрытых duplicate/regression дефектов при guest→user merge, backup restore и будущих миграциях.
