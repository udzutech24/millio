# Research: вертикальный сценарий продукта «Недвижимость»

- Date: 2026-08-09
- Scope: iOS, AccountsCore; создание → детали → редактирование → переоценка; фото; корректное исключение из total.

## Reproduction/evidence

1. `InlineInvestmentCreateForm` хранит `includeInTotal` и возвращает его в `investmentData`.
2. `FinanceAddAccountView.createAssetAccountOnNewCore` создаёт `FinanceProductCreationInput`, но не передаёт `investmentData.includeInTotal`.
3. В `FinanceProductCreationInput` поля `includeInTotal` вообще нет.
4. `FinanceProductCreationCommandResolver` создаёт `CreateProductCommand` без флага; срабатывает дефолт `includeInTotal = true`.
5. `AccountProductGraphBuilder` корректно переносит флаг в `Account`; `Account.participates(on:)` и `AccountsTotalsService` корректно исключают счёт при `false`.

Вывод: баг на границе UI → creation command, а не в формуле total. Корневой фикс должен провести флаг через общий command resolver для всех продуктов.

## Current architecture and constraints

- `AccountProductType.realEstate` сохраняется как `AccountKind.manualAsset`; баланс — replay `openingBalance`/`revaluation`.
- `ManualAssetMeta` содержит только период переоценки, амортизацию и linked loan.
- Текущий detail для manual asset показывает сумму, кнопки «Переоценить / Изменить / Удалить» и ленту событий. Это технически рабочий, но продуктово пустой экран.
- `AccountEditDetailsSheet` редактирует только name/group/note. `includeInTotal` и metadata в UI не выведены, хотя service уже умеет валидировать metadata.
- Изменение валюты запрещено: оно переинтерпретирует всю историю событий.
- Текущая SwiftData-схема V7 заморожена; новая `@Model` требует V8, lightweight migration, backup/import и schema tests.

## UX diagnosis

- Форма создания перегружена одинаковыми секциями для всех инвестиций, но не собирает полезные для недвижимости данные.
- Экран деталей не отвечает на вопросы: что за объект, как изменилась цена, когда его переоценить, есть ли ипотека, входит ли он в капитал.
- «Удалить» фактически архивирует. Текст опасно неточен: пользователь ожидает потерю данных.

## Options considered

1. Оставить generic form/detail и добавить ещё несколько `if realEstate`. Отвергнуто: `AccountDetailView` уже перегружен, а switch-логика не масштабируется на остальные продукты.
2. Сделать отдельный экран и отдельную модель `RealEstate`. Отвергнуто: дублирует event-sourcing, totals, archive и backup.
3. Вертикальный slice на AccountsCore: общий product shell + real-estate descriptor/sections; отдельная attachment-сущность. Выбрано: KISS, не дублирует финансовую логику и даёт шаблон для бизнеса/авто/других продуктов.

## Recommended option and why

Сделать real-estate vertical slice в три гейта: (1) исправить persistence флага и дать его редактировать; (2) пересобрать creation/detail/edit на существующей схеме; (3) только после стабилизации добавить V8 attachments/photos. Так баг total не блокируется рисковой миграцией фото.

## Risks and unknowns

- Фото может раздуть CloudKit, backup и memory. Mitigation: лимит 5 фото, downsample, JPEG/HEIC compression, thumbnail, external storage, size validation.
- Изменение `includeInTotal` меняет исторические totals за все даты, потому что флаг не time-aware. Для v1 это явно объясняем в UI; event-sourced membership — отдельная архитектурная задача.
- Linked mortgage может быть в другой валюте. В v1 equity показываем только при совпадении валют; иначе честный empty state.
- PhotosPicker может вернуть большой/повреждённый asset. Decode/downsample нужно делать вне main actor, а сохранение — атомарно.
- Privacy: EXIF/GPS нужно удалять при перекодировании; в логи не писать адреса/файлы.

## Relevant files/tests

- `millio/UI/Services/Finances/Editors/FinanceAddAccountView.swift`
- `millio/UI/Services/Finances/InlineForms/InlineCreateForms.swift`
- `millio/UI/Services/Finances/Editors/FinanceProductCreationCommandResolver.swift`
- `millio/Core/AccountsCore/ProductCatalog/AccountProductFactory.swift`
- `millio/Core/AccountsCore/Account.swift`
- `millio/Core/AccountsCore/AccountsCoreService.swift`
- `millio/UI/Services/Finances/AccountsCore/AccountDetailView.swift`
- `millio/UI/Services/Finances/AccountsCore/AccountDetailSheets.swift`
- `millio/Core/Schema/AppSchemaVersions.swift`
- `millioTests/UI/Services/Finances/FinanceProductCreationCommandResolverTests.swift`
- `millioTests/Core/AccountsCore/AccountProductFactoryTests.swift`
- `millioTests/Core/AccountsCore/AccountsTotalsHistoricalValuationTests.swift`
