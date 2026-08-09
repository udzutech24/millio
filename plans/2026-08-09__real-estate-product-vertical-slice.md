# Plan: продукт «Недвижимость»

## Inputs

- Research: [`thoughts/research/2026-08-09-real-estate-product-vertical-slice.md`](../thoughts/research/2026-08-09-real-estate-product-vertical-slice.md)
- Spec: [`specs/2026-08-09-real-estate-product-vertical-slice.md`](../specs/2026-08-09-real-estate-product-vertical-slice.md)
- Related plan: [`plans/2026-07-05__account-detail-per-type.md`](2026-07-05__account-detail-per-type.md), Phase 6. Этот план заменяет для `.realEstate` узкую manual-asset фазу и добавляет creation/photos.

## Decision

- Chosen approach: вертикальный AccountsCore slice; снача доказанный financial bug, затем UX на текущей schema, затем отдельная V8 photo migration.
- Rejected alternatives: отдельная `RealEstate` financial model; photo blobs в `Account`; точечные `if realEstate` в монолитных views.
- Rollback strategy: каждая фаза отдельно сборочна; Phase 1/2 не меняют schema; Phase 3 additive V8, старые счета работают без attachments. При UI rollback photo data не удалять.

## Phases

### [x] Phase 1 — починить `includeInTotal` end-to-end

- Снача добавить failing tests: resolver с `false`; factory persistence; totals exclusion; edit mutation + cache revision.
- Добавить `includeInTotal` в `FinanceProductCreationInput` и все common/market commands.
- Передавать флаг из card/credit/investment form data во все new-core create paths, а не тольо для house.
- Расширить `AccountsCoreService.updateAccount` явным membership patch; валидация до мутации, revision bump для account set/financial valuation.
- Добавить toggle в edit-sheet и badge в detail; опубликовать refresh event после save.
- Тесты: resolver, factory, service rollback/dirty context, `participates(on:)`, current/historical totals, UI presentation policy.
- Evidence gate: targeted unit tests + build; на simulator создать real estate с toggle OFF и доказать, что header/group/dynamics не меняются.

**Результат 2026-08-09:** флаг проведён через resolver/factory для всех product shapes, добавлен explicit membership patch в `AccountsCoreService`, edit-toggle и detail badge. Видимость продукта отделена от участия в totals: `includeInTotal = false` больше не скрывает объект из списка и не лишает пользователя возможности вернуть его в итог. Targeted run: 31 тест в 3 suites passed; новый current/historical totals test также проходил в suite run. App target собран тестовым запуском. Ручной simulator walkthrough не зафиксирован; это остаётся визуальным acceptance-check перед Phase 2, но не блокирует завершение code scope Phase 1.

Guard phrase: **«Реализуй фазу 1 по плану недвижимости»**.

### [x] Phase 2 — creation/detail/edit недвижимости без schema migration

- Вынести pure `AccountDetailDescriptor`/presentation models; различать `.realEstate` по product identity.
- Разбить UI на малые компоненты: hero placeholder, valuation summary, KPI row, valuation chart, valuation timeline, property details, action bar.
- Сделать `RealEstateCreateSection` с progressive disclosure; сохранять только backed fields.
- Заменить generic edit на product-aware sheet: name, group, note, membership, revaluation reminder, linked mortgage; currency read-only.
- Переоценка: amount/date/note; append-only event; delta amount/% и staleness из одного pure calculator.
- Переименовать destructive UI в «В архив»; archived detail read-only.
- Локализация RU/EN/zh-Hans, VoiceOver, Dynamic Type, reduce-motion.
- Тесты: descriptors, KPI/staleness/delta, mortgage same-currency policy, action availability, archived mode, creation validation.
- Evidence gate: tests + build + visual QA на iPhone SE/основном iPhone/large Dynamic Type.

Guard phrase: **«Реализуй фазу 2 по плану недвижимости»**.

**Результат 2026-08-09:** добавлены product-identity descriptor, специализированный hero/KPI/step-chart/about/timeline UX, property-aware edit, same-currency mortgage policy, reminder, append-only revaluation и read-only archived state. Creation скрывает нерелевантные direction/favorite/priority controls для недвижимости и допускает нулевую оценку.

### [x] Phase 3 — фото и V8 attachments

- Снача согласовать persisted contract: `AccountAttachment` с id/account relationship/kind/order/isCover/createdAt/media payload; не в `ManualAssetMeta`.
- Добавить V8 schema + lightweight migration V7→V8; frozen V7 не менять.
- `AccountPhotoProcessor`: decode/downsample/re-encode без metadata; ограничение dimension/bytes/count; async off-main processing.
- `AccountAttachmentService`: атомарно add/reorder/set-cover/delete; после ошибки нет half-saved gallery.
- PhotosPicker в creation/edit; галерея и full-screen viewer в detail; graceful placeholder для corrupt/missing payload.
- Backup/export/import и restore preflight для attachments; CloudKit compatibility и quota behavior.
- Тесты: migration fixture V7→V8, processor limits/metadata stripping/corrupt input, atomic service, relationship delete/archive semantics, backup round-trip.
- Evidence gate: schema consistency, migration fixtures, backup round-trip, memory/performance signpost, device photo permission denied/limited/full.

Guard phrase: **«Реализуй фазу 3 по плану недвижимости»**.

**Результат 2026-08-09:** V8 добавляет только `RealEstateProfile` и `AccountAttachment`, не меняя V7 Account checksum. До 5 фото проходят off-main downsample/JPEG re-encode без EXIF/GPS; доступны cover, reorder, fullscreen, confirm-delete и corrupt placeholder. Account/profile/opening event/photos создаются одной транзакцией. Backup round-trip, V7→V8 fixture и archive/delete semantics покрыты тестами.

### [x] Phase 4 — release audit и шаблон для остальных продуктов

- Full relevant test gate, migration/backup restore on copies, offline/CloudKit unavailable checks.
- Accessibility/localization/privacy/memory audit.
- Зафиксировать product descriptor contract как шаблон, но не копировать real-estate fields в другие типы.
- Обновить docs/handoff/status; self-audit каждого acceptance criterion.

Guard phrase: **«Реализуй фазу 4 по плану недвижимости»**.

**Результат 2026-08-09:** release gate — 73 теста в 9 suites passed; финальный real-estate gate — ещё 8 тестов passed; app build, JSON/diff checks passed. Добавлен dark-mode + accessibility Dynamic Type render smoke. Глобальный l10n audit остаётся красным на ранее существующем долге, но все новые ключи имеют RU/EN/zh-Hans. Физический device walkthrough не воспроизводим в локальном CI и остаётся post-build device acceptance, не кодовым долгом.

## Verification

- Unit tests: command propagation, service mutation/rollback, totals membership, descriptor/presentation calculators, photo processor/attachment service.
- Integration/build checks: targeted XCTest → AccountsCore/Finance suite → app build; V7 migration fixture; backup round-trip; simulator/device UX.
- Acceptance criteria audit: после каждой фазы отмечать только те criteria, для которых есть вывод команды/скриншот/тест.

## UX/l10n hotfix 2026-08-09 — completed

- Dynamic `real_estate.type.\(rawValue)` presentation removed from create/edit/detail; `RealEstatePropertyType.localizedTitle` owns static catalog keys.
- Generic editor no longer serves real estate. `RealEstateEditSheet` provides compact type/reminder/mortgage sheets, adaptive rows, lighter glass cards and staged gallery management.
- Metadata, profile and final gallery now share one edit save boundary with rollback on failure; archived/deleted products are rejected as read-only.
- Reminder choices are restricted to off/3/6/12/24 months; mortgage policy admits active same-currency loan accounts and provides an empty state.
- Evidence: targeted `RealEstateProductTests` passed; schema consistency + migration + export/backup-related gate passed; signed simulator build passed.
- Render matrix passed for 375×812 and 390×844, RU/EN/zh-Hans, regular/accessibility Dynamic Type, dark mode. Simulator screenshots were inspected after fixing a residual 375-pt title truncation.
- Follow-up: revaluation now uses the shared `AmountTextField`, so large values are grouped live (`54 321 000.75`) while persistence receives the canonical decimal value.
