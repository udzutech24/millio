# План: визуальный редизайн счетов (`AccountAppearance` V11 → список → галерея → hero)

**Дата:** 2026-08-28
**Статус:** В РАБОТЕ (Ф0 смержена в `develop` 1ba9c2e; Ф1 в ветке `feature/account-card-row-redesign`, не смержена)
**Размер:** L (10+ файлов, затрагивает схему SwiftData и оба мира счетов)
**Спека:** [`specs/2026-08-28-account-card-visual-redesign.md`](../specs/2026-08-28-account-card-visual-redesign.md)
**Автор:** Александр (iOS)

---

## Решения владельца (зафиксированы, 2026-08-28)

| № | Вопрос §8 спеки | Решение |
|---|---|---|
| 1 | Хранение | **Вариант (б)** — отдельная таблица `AccountAppearance`, ключ `accountID: UUID`, аддитивная `AppSchemaV11`. Декларации `Account`/`CardMeta` **не трогаем**. |
| 2 | Пресеты | **Только градиенты/паттерны из кода.** Пользовательские фото/обложки — вне скоупа целиком (фаза с `AccountAttachment` НЕ делается). |
| 3 | Галерея дизайнов | **PRO-фича.** Free галерею не получает (дефолтный вид — да, выбор дизайна — нет). |
| 4 | Логотипы банков | **Справочник банков не заводим.** Монограмма + цвет, и всё. `CardMeta.bank` остаётся свободной строкой. |
| 5 | Порядок фаз | **Первой — редизайн списка «Счета»**, hero детального экрана позже (вопреки рекомендации спеки — решение владельца принято). |

**Дополнительно (расширение скоупа владельцем):** в этот же спринт core `Account` получает
`isFavorite`. Кладём его **в `AccountAppearance`**, а не в `Account` — иначе понадобится
рискованная правка продакшн-модели (см. §7.1 спеки, памятка `millio-schema-frozen-types-trap`).
`AccountAppearance` перестаёт быть чисто-декоративной таблицей и становится
**таблицей пользовательских атрибутов представления счёта** — это осознанное решение,
зафиксировано здесь, чтобы позже не выглядело нарушением SRP.

---

## 🚧 Блокер старта Фазы 0 (внешняя зависимость)

**Ветка `feature/cashflow-account-picker-redesign` должна быть смержена в `develop`.**

`CashflowAccountPickerDetailsFactory`
(`millio/UI/Services/Cashflow/AccountPicker/CashflowAccountPickerDetails.swift`) — единственная
существующая фабрика презентации счёта для обоих миров (Card / Account / Investment). Именно её
мы расширяем до `AccountAppearance`. Стартовать реализацию до мержа = завести **второй резолвер
презентации** параллельно первому → гарантированный класс багов «двойник легаси/core», которым
проект уже болел (`millio-dynamics-single-source-of-truth`).

**Условие снятия блокера:** `git log develop --oneline | grep <коммит пикера>` даёт результат,
`git branch --merged develop` содержит ветку пикера. До этого — план в состоянии НЕ НАЧАТ,
никакого кода.

**Точка интеграции, порождённая блокером:** `CashflowSelectableAccount.swift:93` сейчас
захардкожено `isFavorite: false` для core-счетов (у легаси `Card.isFavorite:157` источник есть,
у core — нет). После Ф0 эта константа заменяется на чтение из `AccountAppearance` — это
**acceptance-критерий Ф0**, а не «когда-нибудь потом».

---

## Фазы

Всего 5 фаз. Рискованная — только Ф0.

---

### [x] Ф0. Схема V11: `AccountAppearance` + `isFavorite` для core — ⚠️ РИСКОВАННАЯ

> **СТОП-ГЕЙТ. Перед стартом обязательны, в этом порядке:**
> 1. Снятие блокера (мерж ветки пикера) — проверено git-командой, не на слово.
> 2. **`/stress-test`** по этой фазе (правило проекта, `../CLAUDE.md` §«Базовые правила» п.7 —
>    изменение схемы = данные пользователя).
> 3. **`AskUserQuestion`** владельцу: краткий риск (сдвиг checksum V10 → `NSCocoaErrorDomain
>    134504` → исторический no-plan fallback, стиравший данные, `AppSchemaVersions.swift:79-89`)
>    + варианты «продолжить / отложить / пересмотреть».
> Без явного «да» владельца фаза не стартует. Guard phrase это правило **не отменяет**.

**Что делаем**

1. `@Model AccountAppearance` — новый файл `millio/Core/AccountsCore/Appearance/AccountAppearance.swift`.
   Поля: `id: UUID`, `accountID: UUID` (**обычное поле, без `@Relationship`** — ключ работает
   и для core `Account.id`, и для легаси `Card.uniqueID`), `presetRaw: String?`,
   `tintHex: String?`, `iconName: String?`, `isFavorite: Bool = false`, `updatedAt: Date`.
2. `AppSchemaV11` в `millio/Core/Schema/AppSchemaVersions.swift`:
   `AppSchemaV10.models + [AccountAppearance.self]`, декларации V10 — **byte-for-byte без
   изменений** (образец: V8/`AccountAttachment`, `AppSchemaVersions.swift:146-154`).
   `+ .lightweight(fromVersion: AppSchemaV10.self, toVersion: AppSchemaV11.self)` в
   `AppMigrationPlan.stages`, `typealias AppSchemaCurrent = AppSchemaV11`.
3. Регистрация в бэкапе: `ModelTypeRegistry.shared.register(AccountAppearance.self, ...)` +
   `AccountAppearanceImporter: ModelImporter` — по образцу `AccountAttachmentImporter`
   (`millio/Core/AccountsCore/AccountsCoreFeatureRegistration.swift:31,44,74-102`).
   Без этого дизайны и избранное **молча исчезают после restore**.
4. Чистка сирот в `millio/Core/Repository/DataIntegrityCleaner.swift`: каскада нет, удаление
   счёта не удаляет appearance.
5. Сервис доступа `AccountAppearanceStore` (там же в `Appearance/`): один fetch → словарь
   `[UUID: AccountAppearance]`, upsert по `accountID`, `toggleFavorite(accountID:)`.
   **Никаких запросов из тела `View`.**
6. Интеграция: `CashflowSelectableAccount.swift:93` — `isFavorite` для core берётся из стора.

**Переиспользуем:** `AccountAttachment` (`Core/AccountsCore/RealEstate/RealEstateModels.swift:118-165`)
как образец аддитивной side-таблицы; `AccountAttachmentImporter` как образец импортера;
`ModelTypeRegistry`/`ModelImporter`; `DataIntegrityCleaner` + его существующие тесты как образец.

**Критерии готовности**
- [ ] `AppSchemaV10.models` не изменён — доказать `git diff` по файлу схемы (только добавления ниже V10).
- [ ] `SchemaConsistencyTests` + `SchemaMigrationTests` зелёные; эталонные checksum V4–V10 сняты
      до и после и **совпадают** (памятка `millio-schema-frozen-types-trap`).
- [ ] Открытие реального V10-стора не даёт 134504 (тест миграции на фикстуре V10-стора).
- [ ] Тест backup → wipe → restore: `AccountAppearance` восстанавливается, `isFavorite` жив.
- [ ] Тест сирот: удаление счёта → `DataIntegrityCleaner` убирает appearance.
- [ ] `CashflowSelectableAccount` для core-счёта отдаёт реальный `isFavorite` (интеграционный
      тест пути создания, не только трансформации — урок `millio-integration-test-creation-path`).
- [ ] Билд без предупреждений, полный сьют без новых красных.

**Что тестировать:** миграция V10→V11 на непустом сторе · checksum-инварианты · backup/restore
round-trip · сироты · upsert идемпотентен (два вызова = одна строка) · пустой стор ·
guest/user scope (appearance не должна протекать между scope — см. `millio-guest-scope-backup-leak`).

**Откат:** V11 аддитивна и обратима — при проблеме удаляем стадию и таблицу, финансовые данные
не затронуты (это главный аргумент за вариант (б)).

**Факт реализации (2026-08-28, ветка `feature/account-appearance-v11`, НЕ смержена):**
- `1de96ac` — модель `Core/AccountsCore/Appearance/AccountAppearance.swift`, `AccountAppearanceStore`,
  `AppSchemaV11` (+ стадия `.lightweight(V10→V11)`, `AppSchemaCurrent = V11`),
  `AccountAppearanceImporter` + регистрация, `DataIntegrityCleaner.purgeOrphanAccountAppearancesOnLaunch`
  (вызов в `DIContainer.create`), `CashflowSelectableAccount.swift` — `isFavorite` core-счёта из стора
  (пробрасывается из `CashflowViewModel.coreAccountFavoriteIDsForCashflowPicker()` и `CashbackViewModel`).
- `7bf2768` — тесты: checksum-инварианты (V10 внесена в `historicalVersions`, Account 10.0.0 =
  `yWZTWJU6/…`, форма `AccountAppearance` запинена), `v11PreservesEveryV10Entity`, миграция реального
  V10-стора, контракт стора, backup→wipe→restore, сироты, путь создания Cashflow-пикера.
- **СМЕРЖЕНО в `develop` 2026-08-29** по явному разрешению владельца: `1ba9c2e` (merge --no-ff).
  Гейт мержа: baseline `develop` 38 red → после мержа 33 red, **0 новых красных**. Не запушено.
- Известный предел: легаси-карта с пустым `uniqueID` (composite-fallback `Card.swift:272`) не
  парсится в UUID и оформления не получает — дефолтный вид, без краша.
- `CashflowStatementReviewPolicy.options` избранное core-счетов не получает (влияет только на
  сортировку в импорте выписки) — сознательно вне скоупа Ф0.

---

### [x] Ф1. Редизайн списка «Счета»: монограмма + цвет + избранное

Без фото, без hero, без галереи. Только то, что даёт Ф0.

**Что делаем**
- `NewCoreAccountRow.swift:37-45` — заглушку `iconName: nil, iconColor: nil` заменить на резолв
  из appearance (комментарий-заглушка «до появления кастомных иконок нового ядра» `:67-68` снимается).
  Дефолт core-счёта — монограмма по имени (`AccountIconSet.monogramIconName`), fallback —
  `AccountKind.fallbackIconName`.
- Визуал строки правим **в одном компоненте**; три точки отрисовки только передают данные:
  `FinancesView.swift:1057`, `Rows/FinanceRows.swift:452`, `Editors/FinanceGroupEditorView.swift:592`.
- Избранное: звезда/секция «Избранные» наверху списка, тап-действие через `AccountAppearanceStore`.
- `ArchivedAccountsView.swift` — приглушённый вариант того же визуала (opacity/grayscale),
  не отдельная вёрстка.
- Словарь appearance грузится **одним fetch** во ViewModel списка, не по строке.

**Переиспользуем:** `AccountIconBadgeView` (`UI/Services/Finances/Icons/AccountIconBadgeView.swift`) —
API не меняем; ⚠️ внутри `Font.system(size:)` — при доработке перевести на `AppTypography`.
`AccountIconSet`; токены `AppColors`/`AppSpacing`/`AppTypography`/`AppAnimation`.
Резолвер — расширенная `CashflowAccountPickerDetailsFactory`, **второй не заводим**.

**Критерии готовности**
- [ ] Строка core-счёта показывает монограмму + цвет из appearance; при пустой appearance —
      прежний внешний вид без регрессии.
- [ ] Легаси `Card` в списке не сломан (`cardColor` — грязное поле «hex ИЛИ название»,
      **не отдавать напрямую в `Color(hex:)`**, санитайзер из фабрики пикера).
- [ ] Ни одного `Font.system(size:)` и числа-литерала в padding/spacing в новом коде.
- [ ] Ни одного raw RU-литерала — всё в `Localizable.xcstrings` (RU/EN/zh-Hans).
- [ ] Список 60+ счетов: один fetch appearance, не N (доказать тестом/логом запросов).
- [ ] Device-проверка владельцем.

**Что тестировать:** резолв иконки (appearance → монограмма → fallback) · санитайзер цвета
(hex, имя, мусор, nil) · сортировка с избранными · архивные · пустой список · длинное имя ·
одноимённые счета (монограммы совпадают — не баг, зафиксировать ожидание).

**Факт реализации (2026-08-29, ветка `feature/account-card-row-redesign`, НЕ смержена):**
- `Core/AccountsCore/Appearance/AccountAppearanceSnapshot.swift` — value-срез для UI (`@Model` в
  кэше VM опасен: `DataIntegrityCleaner` сносит сирот на старте) + `AccountAppearanceStore.loadSnapshots()`.
- `CashflowAccountPickerDetailsFactory.details(for:appearance:balance:)` — appearance добавлен
  параметром со значением по умолчанию: резолвер остался ОДИН, второго не заведено.
- `NewCoreAccountRow` — единственный компонент строки: бейдж из резолвера, звезда избранного,
  `isDimmed` для архива, `onToggleFavorite` (nil = read-only, контекстное меню не вешается).
  Все три точки отрисовки (`FinancesView:1057`, `Rows/FinanceRows:452`, `Editors/FinanceGroupEditorView:592`)
  только передают данные.
- `FinanceViewModel` — `accountAppearances: [UUID: AccountAppearanceSnapshot]`, заполняется
  `loadAccountAppearances()` ПЕРВОЙ строкой `loadGroups()` (один fetch на цикл),
  `appearance(for:)` читает кэш, `toggleFavorite(_:)` пишет через стор и перезагружает список.
- Сортировка «избранные наверх» — в `sortedAccounts` (единственная точка, её зовут и
  `orderedAccounts(for:)`, и `ungroupedAccounts()`), в ОБОИХ ветках, включая ручной порядок.
- `ArchivedAccountsView` — тот же резолвер и бейдж, `saturation(0)` + opacity; собственная
  вёрстка строки сохранена, потому что архив показывает «дата закрытия» и «баланс на закрытии»,
  которых у `NewCoreAccountRow` нет (отступление от буквы плана, зафиксировано осознанно).
- 3 ключа локализации (`finances.account.favorite.add/remove/badge`) — 7 языков, вставлены
  точечно (диф 141 строка, файл целиком не переписан).
- Тесты: `millioTests/UI/Services/Finances/FinanceAccountAppearanceRowTests.swift` — 10 кейсов,
  все зелёные. Гейт: baseline develop 38 red → после Ф1 36 red, **0 новых красных**.
- ⚠️ **Открыто:** «секция Избранные» отдельным блоком наверху списка НЕ делалась — выбран
  вариант «звезда + подъём наверх». Отдельная секция дублировала бы строку счёта (он остаётся
  и в своей группе) → знакомый проекту класс багов «двойник». Нужен вердикт владельца.
- ⚠️ Device-проверка владельцем не выполнена.

---

### [x] Ф1b. Дизайн не виден на устройстве — доведение до реальных данных владельца

**Диагноз (подтверждён кодом, 2026-08-29):** Ф1 задела ТОЛЬКО core-`Account`. У владельца
преобладают легаси-счета (`Card`/`Credit`/`Investment`), они рисовались собственной вёрсткой
(`FinanceRows.swift` + примитивный `HStack` в «Без группы»), а таблица `AccountAppearance` была
пуста — резолвер отдавал `tintHex = nil` и бейдж штатно деградировал в старый `financesGradient`.
Итого на экране не менялось ничего.

**Что сделано**

- **A. Единая строка.** `UI/Services/Finances/Rows/AccountRowView.swift` — `AccountRowPresentation`
  (value) + `AccountRowView` (единственная вёрстка, слот `accessory` под подстроки старого мира).
  `NewCoreAccountRow` стал адаптером; легаси-`FinanceAccountRow` и хвост «Без группы»
  (`FinancesView.swift`) своей разметки больше не имеют. Заодно снят дубль `marketInvestmentRow`.
- **B. Дефолт оформления — вычисляемый, а не backfill строк.**
  `UI/Services/Finances/Icons/AccountAppearanceDefaults.swift`: цвет из палитры `AccountIconSet`
  по стабильному ключу (`Account.id` / `*UniqueID`), хеш FNV-1a (не `Hasher` — тот солится на
  каждый запуск процесса, цвет «мигал» бы). Строка в БД появляется только при ЯВНОМ выборе
  пользователя → бэкап не растёт, идемпотентность следует из чистой функции, а не из флага,
  и `purgeOrphan` нечего стирать. Красный и серый исключены из авто-подбора (красный = долг).
- **C. Редактор оформления** — контекстное меню строки → «Оформление» → существующий
  `AccountIconPickerSheet`, запись через новый `AccountAppearanceStore.setAppearance`
  (полный сброс удаляет строку → счёт возвращается к вычисляемому дефолту). Один путь записи
  для обоих миров. PRO-гейта здесь нет сознательно: иконка/цвет у легаси-карт и так были
  бесплатны, гейт по плану относится к ГАЛЕРЕЕ ПРЕСЕТОВ (Ф2), она не делалась.
- **D. `DataIntegrityCleaner.purgeOrphanAccountAppearancesOnLaunch`** — владельцами стали также
  `Credit` и `Investment`. До фикса их оформление считалось сиротой и стиралось на КАЖДОМ старте.

**Гейт:** сборка `BUILD SUCCEEDED` без ошибок; 14 новых тестов
(`millioTests/UI/Services/Finances/AccountRowPresentationTests.swift` + регресс на чистку сирот);
обновлено ожидание `FinanceAccountAppearanceRowTests/missingAppearanceKeepsMonogramDefault`
(дефолт теперь несёт цвет — намеренная смена поведения).

**Открыто:** device-проверка владельцем; легаси-счёт с composite-`uniqueID` (не парсится в UUID)
оформление редактировать не может — рисуется дефолтом; звезда «избранное» у легаси не показывается
(её источник `Card.isFavorite` — мост в `AccountAppearance` это Ф4).

---

### [ ] Ф2. Каталог пресетов + галерея выбора (PRO-гейт)

**Что делаем**
- `AccountAppearancePreset` — **кодовый** каталог (id, градиент, паттерн, позиция акцента),
  палитра строится из существующих градиентов `AppColors` (`financesGradient`, `cashflowGradient`,
  `investmentsGradient`, …) + `GradientBackground`, чтобы дизайны не выпадали из системы.
  Пресеты в коде, не в БД: правка/добавление не требует миграции и не раздувает бэкап.
- Галерея — **вкладка «Дизайн» внутри существующего `AccountIconPickerSheet.swift`**, не новый экран.
- PRO-гейт: **только** через `EntitlementPolicy` (`millio/Core/AppState/AppState.swift:204`) —
  добавить `isAccountAppearanceGalleryProOnly = true` + `canUseAccountAppearanceGallery(isPro:)`.
  Никаких параллельных проверок `appState.isPro` в вёрстке мимо политики.
  Free видит галерею закрытой с paywall-переходом (как `isFinanceChartsProOnly`), дефолтный
  визуал из Ф1 остаётся доступен всем.
- Названия пресетов — в `Localizable.xcstrings`, RU/EN/zh-Hans.

**Переиспользуем:** `AccountIconPickerSheet` (готовый лист выбора), `AccountIconSet`,
`EntitlementPolicy` + существующий paywall-путь, `GradientBackground`, токены.

**Критерии готовности**
- [ ] Free: галерея под замком, тап → paywall; PRO: выбор применяется и переживает перезапуск.
- [ ] Выбор пресета пишется через `AccountAppearanceStore` (upsert), не прямым `context.insert`.
- [ ] Dark-mode-контраст: белый текст + тень читается на всех пресетах, включая жёлтый/оранжевый.
      Светлых вариантов пресетов нет (`AppColors.backgroundTop = .black`).
- [ ] Все названия пресетов локализованы в 3 языках.
- [ ] `EntitlementPolicy` — единственный источник гейта (grep: нет `isPro` рядом с галереей).

**Что тестировать:** policy-тесты Free/PRO · сохранение и перезагрузка выбора · неизвестный
`presetRaw` из чужого бэкапа (будущая версия) → graceful fallback на дефолт, не краш.

---

### [ ] Ф3. Hero-карточка детального экрана

**Что делаем**
- `AccountHeroCardView` — один компонент, встающий **над** всеми per-type секциями, чтобы не
  получить 5 разных шапок: `AccountDetailView.swift:113-151, 264-330` (`standardHeader`),
  `CreditCardDetailSection.swift`, `DebitCard/DebitCardDetailSection.swift`,
  `Deposit/DepositDetailSection.swift`, `RealEstateDetailSection.swift`.
- Содержимое hero (только существующие источники, §3.1 спеки): имя, баланс + валюта, тип
  продукта, `CardMeta.last4`, статусы «архив» / «не в тотале»; для кредитки — лимит/доступно/дата
  платежа; для вклада — ставка/срок. **Логотипа банка нет** (решение №4), бренд-акцент —
  монограмма + цвет пресета.
- Баланс на hero — **confirmed-путь** для вкладов (`millio-deposit-confirmed-balance`), не сырой
  реплей событий. Не заводить третье определение баланса.
- Hero-визуал только на детальном экране; в списке остаётся бейдж 36pt (Ф1).

**Переиспользуем:** `AccountIconBadgeView` (малый бейдж на hero), каталог пресетов из Ф2,
`GradientBackground`, токены, существующие `depositPresentation`/`creditPresentation`.

**Критерии готовности**
- [ ] Один hero для всех 5 типов продуктов, per-type секции не рисуют собственные шапки.
- [ ] Баланс на hero совпадает со строкой списка и с тоталом — до копейки (инвариант-тест).
- [ ] Архивный счёт и «не в тотале» визуально различимы.
- [ ] Токены + локализация, как в Ф1.
- [ ] Device-проверка владельцем (скрин каждого из 5 типов).

**Что тестировать:** совпадение баланса hero / список / тотал · счёт без appearance ·
очень длинное имя и большая сумма (переполнение) · архивный · нулевой баланс · отрицательный
(кредитка) · вклад с прогнозом.

---

### [ ] Ф4. Мост с легаси `Card` + чистка

**Что делаем**
- Одноразовая миграция персонализации легаси в `AccountAppearance`: `Card.customIconName:177`,
  `customIconColor:180`, `cardColor:154` (через санитайзер!), `isFavorite:157` → строка
  appearance по `Card.uniqueID`. Идемпотентно, с флагом выполнения, без перетирания того,
  что пользователь выбрал сам после Ф2.
- После миграции легаси-карта и core-счёт читают персонализацию **из одного источника** —
  цель всей затеи; `Card.*` остаются как есть (не удаляем, не мигрируем данные счетов).
- Пикер Cashflow, список, hero и архив — все через один резолвер.

**Переиспользуем:** `LegacyAccountConverter` / `LegacyConversionRegistry` как образец
одноразовой идемпотентной миграции; `DataIntegrityCleaner` для хвостов.

**Критерии готовности**
- [ ] Легаси-карта с кастомной иконкой/цветом выглядит после миграции идентично тому,
      как выглядела до (визуальная регрессия = провал фазы).
- [ ] Повторный запуск миграции ничего не меняет (идемпотентность, тест).
- [ ] Пользовательский выбор из Ф2 миграцией не перетирается.
- [ ] Нет второго резолвера презентации (grep по проекту).

**Что тестировать:** `cardColor` = hex / имя цвета / мусор / nil · карта без персонализации ·
двойной прогон миграции · `Card` без core-двойника и с ним · restore после миграции.

---

## Сводная таблица

| Фаза | Суть | Риск | Гейт перед стартом |
|---|---|---|---|
| Ф0 | Схема V11 + `AccountAppearance` + `isFavorite` | ⚠️ **высокий** | мерж ветки пикера → `/stress-test` → `AskUserQuestion` |
| Ф1 | Редизайн списка «Счета» | низкий | Ф0 done |
| Ф2 | Каталог пресетов + галерея (PRO) | низкий | Ф1 done |
| Ф3 | Hero-карточка деталки | средний (5 типов) | Ф2 done |
| Ф4 | Мост с легаси `Card` | средний (регрессия визуала) | Ф3 done |

## Вне скоупа (зафиксировано)

- Пользовательские фото/обложки счетов (`AccountAttachment`, base64 в бэкапе) — решение №2.
- Справочник банков и логотипы — решение №4.
- Платёжная система (Visa/MC/МИР), срок действия для core-счёта — полей нет, отдельная задача.
- Любые правки `AppSchemaV10.models` и продакшн-модели `Account`/`CardMeta`.

## Журнал

| Дата | Событие |
|---|---|
| 2026-08-28 | План создан. Статус НЕ НАЧАТ. Ждём мержа `feature/cashflow-account-picker-redesign`. |
| 2026-08-28 | Блокер снят: ветка смержена в `develop` (`f2870b6`, запушено). Владелец: перед Ф0-кодом — сначала визуальный дизайн + функционал, показать, до кода. |
| 2026-08-28 | Мокап готов и показан: https://claude.ai/code/artifact/5dbc1acf-0e3f-46d7-9b1a-a0c4e41adeef — 4 артборда (список · hero ×2 · галерея 12 типов · детальные экраны ×4 с KPI/графиками по спеке per-type). Прогнан ui-ux-pro-max (hairline-бордеры, top-edge sheen, tabular-nums, millioDisplayLarge на балансе). Владелец: «прикольно», скоуп = ПОСЛЕДОВАТЕЛЬНО (визуал V11 сначала, per-type графики — отдельным планом после). Код — в новой сессии. |
| 2026-08-28 | Дизайн УТВЕРЖДЁН: владелец — «правок нет». Готов к гейту Ф0 (stress-test + вопрос о риске схемы) в новой сессии. |

## Промпт для следующей сессии

```
Продолжаем визуальный редизайн карточек счетов Millio (AccountAppearance V11).

Читай сначала:
- plans/2026-08-28__account-card-visual-redesign.md (этот план, решения владельца зафиксированы)
- specs/2026-08-28-account-card-visual-redesign.md (спека, обоснование схемы)
Память: [[millio-account-card-visual-redesign]] [[millio-schema-frozen-types-trap]]
[[millio-cashflow-save-error-account-picker]]

Где встали: блокер (мерж пикера счёта) снят, develop запушен (f2870b6). Ф0-Ф4 план
готов, ни одна фаза не начата. Владелец явно попросил: СНАЧАЛА дизайн (как будет
выглядеть) и функционал (что именно делает), ПОТОМ код — не прыгать в Ф0 сразу.

Что дальше:
1. Дизайн УТВЕРЖДЁН владельцем 2026-08-28 («правок нет»). Референс-мокап:
   https://claude.ai/code/artifact/5dbc1acf-0e3f-46d7-9b1a-a0c4e41adeef
   (4 артборда: список · hero ×2 · галерея 12 типов · детальные экраны ×4).
   Исходники артбордов: /tmp/millio-account-cards/ (если потёрты — восстановить:
   Artifact read → seed-canvas.mjs --extract).
2. Скоуп решён: ПОСЛЕДОВАТЕЛЬНО — этот план (Ф0–Ф4, только визуал) сначала,
   per-type KPI/графики (план 2026-07-05__account-detail-per-type) отдельной задачей после.
3. ПЕРВЫЙ ШАГ СЕССИИ — гейт Ф0 (схема AccountAppearance V11):
   ОБЯЗАТЕЛЬНО `/stress-test` + `AskUserQuestion` про риск сдвига checksum V10
   (frozen-types trap) с явным «да» владельца перед первой строкой кода схемы.
4. Дальше по плану: Ф1 список → Ф2 галерея (PRO-гейт EntitlementPolicy) → Ф3 hero → Ф4 мост с легаси.

Развилки/ждём: явное «да» на риск схемы в Ф0 — без него код не начинать
(Guard phrase + правило стресс-теста CLAUDE.md).
```
