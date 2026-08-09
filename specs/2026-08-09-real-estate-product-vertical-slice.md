# Spec: продукт «Недвижимость» от создания до страницы

## Problem

Недвижимость создаётся через generic investment form, а затем открывается в пустом generic detail. Выбор «не учитывать в итоге» теряется при создании AccountsCore-счёта. После создания флаг и параметры актива нельзя полноценно редактировать.

## Goal

Сделать недвижимость полноценным продуктом: быстрое создание, наглядная карточка, честная история оценки, полное редактирование и фото без поломки финансовой модели.

## Product UX

### Creation

Progressive disclosure вместо общей формы:

1. «Объект»: название (обязательно), фото (опционально), тип объекта (квартира/дом/земля/коммерческая/другое).
2. «Оценка»: текущая стоимость, валюта, дата оценки. Нуль допустим, но показан как «не оценено», а не как реальная цена 0.
3. «Организация»: группа, заметка.
4. «Капитал»: один toggle «Учитывать в общем капитале» с превью вклада. Переключатель «увеличивает/уменьшает» для недвижимости убирается: real estate — актив, а ипотека — отдельное обязательство.
5. «Дополнительно» (collapsed): период напоминания о переоценке, связанная ипотека.

### Detail page

- Hero 16:9: cover photo или качественный gradient placeholder; название и type badge. Карусель открывается тапом.
- Главная цифра: текущая оценка + дата/статус актуальности. Если исключён из total — видимый badge «Не входит в общий капитал».
- Primary actions: «Переоценить» и «Изменить». «В архив» уходит в overflow/destructive zone; ложного «Удалить» нет.
- KPI: изменение с прошлой оценки (сумма и %), давность оценки, equity после ипотеки при same currency.
- График/история оценок: step-line по `openingBalance`/`revaluation`; timeline с датой, значением, delta и note. Никакой выдуманной рыночной динамики между оценками.
- Секция «Об объекте»: type, group, currency (read-only), reminder, linked mortgage, note.
- Empty states: нет фото → «Добавить фото»; нет оценки → «Добавить оценку»; нет ипотеки → секция не занимает место.

### Editing

Один sheet редактирует name, type, group, note, includeInTotal, reminder, linked mortgage и gallery. Валюта показана read-only. Стоимость не меняется как metadata: она всегда пишет `revaluation`, чтобы история не ломалась.

## Acceptance criteria

- [x] Выключенный при создании `includeInTotal` сохраняется как `false`; счёт не входит в current/historical total и групповой total.
- [x] Флаг можно изменить в edit-sheet; detail явно показывает статус исключения.
- [x] Изменение membership инвалидирует valuation revision и обновляет list/dashboard без relaunch.
- [x] Creation для `.realEstate` показывает только релевантные поля; название обязательно, цена может быть 0.
- [x] Detail различает тип продукта по `productType`, а не только по generic `.manualAsset`.
- [x] Переоценка записывает append-only event с date/note; timeline и график показывают ту же историю.
- [x] Для недвижимости нет irrelevant controls «увеличивает/уменьшает», market ticker, favorite/priority без persisted mapping.
- [x] Архивация названа «В архив»; при archived state экран read-only, история и фото сохраняются.
- [x] Можно добавить до 5 фото, выбрать cover, переставить и удалить одно фото с confirm; битый asset не ломает detail.
- [x] Фото downsampled, сжаты, без EXIF/GPS; лимиты проверяются до persistence; decode не блокирует main actor.
- [x] V8 migration сохраняет V7 Account/Event data; backup round-trip сохраняет attachments либо явно отказывается до частичного restore.
- [x] RU/EN/zh-Hans localization, VoiceOver labels, Dynamic Type, Reduce Motion и dark mode проверены автоматическим render smoke и code audit.
- [x] Критичная логика покрыта unit/integration tests; экран render-проверен на simulator. Физический device walkthrough остаётся внешним release acceptance.

## Scope

- AccountsCore creation command, real-estate form/detail/edit/revaluation.
- Отдельная photo attachment model, V8 migration, backup/restore.
- Переиспользуемый product descriptor/shell для будущих типов без преждевременной реализации их UX.

## Non-goals

- Автооценка по рынку, кадастру или AI.
- Адрес, геолокация, документы права собственности: это PII/legal scope и требует отдельного privacy design.
- Доход от аренды, расходы на ремонт, sale transaction: это cashflow/linking scope, не valuation.
- Смена валюты существующего актива.
- Массовое распространение UX на все остальные продукты в этой задаче.

## Constraints and risks

- Не писать photo blobs в `ManualAssetMeta`/`Account`.
- Не мутировать balance напрямую; только event/service.
- Не переписывать V7 задним числом; только V8 migration.
- Не показывать equity при разных валютах без честного FX source/date.

## UX/l10n hotfix acceptance (2026-08-09)

- [x] Property type presentation uses typed static keys; RU/EN/zh-Hans never expose `real_estate.*` keys.
- [x] The 375/390-pt edit title is fully visible and does not compete with toolbar actions.
- [x] Type, reminder and mortgage selection use compact accessible sheets rather than wide system menus/steppers.
- [x] Real estate has a dedicated adaptive editor with staged add/preview/cover/reorder/confirm-delete gallery management (maximum five).
- [x] Active same-currency mortgage policy and useful empty state are explicit and unit-tested.
- [x] Name/photo-processing validation gates Save; Account/profile/gallery persistence is atomic and rolls back together.
- [x] Archived/deleted real estate is read-only.
- [x] Dark render matrix covers 375×812, 390×844, RU/EN/zh-Hans and regular/accessibility Dynamic Type.
