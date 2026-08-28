# Spec — Визуальный редизайн счетов: hero-карточка, галерея дизайнов, список «Счета»

- **Дата:** 2026-08-28
- **Статус:** DRAFT (research + spec, плана фаз НЕТ — ждём решение владельца по развилке хранения)
- **Размер:** L (10+ файлов, затрагивает схему SwiftData и оба мира счетов)
- **Автор:** Александр (iOS)

---

## 1. Запрос владельца (WHAT)

Референс — Bybit «My cards»: крупная брендированная карта сверху, лого, номер, статус; галерея дизайнов.

1. Кастомные иконки/визуалы для счетов и карт.
2. Детальный экран счёта: «светящаяся» карточка сверху вместо голого текста.
3. Выбор дизайна карты из галереи пресетов.
4. Редизайн списка «Счета» (сейчас — скудный).

## 2. Зачем (WHY)

Экран счёта — второй по частоте после Дашборда, но визуально это текстовый дамп: `AccountDetailView.standardHeader` (`millio/UI/Services/Finances/AccountsCore/AccountDetailView.swift:275-330`) = сумма + список серых строк. Строка списка — `NewCoreAccountRow` (`.../AccountsCore/NewCoreAccountRow.swift`) с монохромным бейджем без цвета и иконки. При этом в коде уже стоит явная заглушка: «до появления кастомных иконок нового ядра» (`NewCoreAccountRow.swift:67-68`) и «полей иконки/цвета/избранного в схеме нет (миграция отложена, см. `millio-schema-frozen-types-trap`)» (`CashflowAccountPickerDetails.swift:35-36`, ветка `feature/cashflow-account-picker-redesign`). То есть недостающий слой персонализации — известный, отложенный долг, а не новая хотелка.

---

## 3. Что показать на hero-карточке

### 3.1 Core `Account` (новое ядро)

| Элемент | Источник | Есть? |
|---|---|---|
| Имя счёта | `Account.name` | ✅ |
| Баланс + валюта | реплей событий (`AccountBalanceEngine`), `Account.currency` | ✅ (не поле — считается) |
| Тип продукта | `Account.productType` / `kind` | ✅ |
| Банк | `CardMeta.bank: String?` (`Core/AccountsCore/AccountMeta.swift:10`) | ⚠️ свободная строка, **справочника нет** → логотип брать неоткуда |
| Последние 4 цифры | `CardMeta.last4` | ✅ |
| Кредитный лимит / доступно / дата платежа | `CardMeta.creditLimit`, `statementDay`, `dueDay`, `graceDays`, `minPayment` | ✅ |
| Вклад: ставка, срок, капитализация, налоговый тег | `DepositMeta` (V10) | ✅ |
| Статусы «архив», «не в тотале» | `archivedAt`, `includeInTotal` | ✅ |
| Иконка / цвет / дизайн карты | — | ❌ **нет ни одного поля** |
| Избранное | — | ❌ |
| Платёжная система (Visa/MC/МИР), срок действия | — | ❌ |

### 3.2 Легаси `Card` (`millio/UI/Services/CardIndex/Card.swift`)

Персонализация уже есть и почти бесплатна: `customIconName:177`, `customIconColor:180`, `resolvedIconName:183`, `cardColor:154` (⚠️ «hex ИЛИ название» — грязное поле, нельзя отдавать напрямую в `Color(hex:)`, см. комментарий в `CashflowAccountPickerDetailsFactory`), `isFavorite:157`, `expiryDate:145`, `bank: Bank` (enum со справочником и иконкой) и `cardType: CardType`. Не хватает только идентификатора пресета дизайна.

**Вывод:** для легаси-карты hero-карточка строится из имеющихся данных сегодня; для core-счёта — нет вообще ничего визуального. Значит любое решение обязано в первую очередь закрыть core, и желательно одним механизмом для обоих миров (иначе два разных источника → класс багов «двойник легаси/core», которым проект уже болел).

---

## 4. Развилка хранения дизайна

### Вариант (а) — расширить схему core `Account` / `CardMeta`

Добавить `appearancePresetRaw`, `iconName`, `tintHex` в `Account` (или внутрь `CardMeta`).

- `CardMeta` — **composite attribute внутри `Account`**, поэтому изменение `CardMeta` меняет checksum сущности `Account`. Ровно эта грабля описана в `AppSchemaVersions.swift:130-133` (из-за неё V10 пришлось делать первой версией, снова ссылающейся на продакшн-модели).
- Так как V10 ссылается на продакшн `Account.self` (`AppSchemaVersions.swift:175-186`), любое новое поле сдвинет checksum **уже существующей на дисках V10** → `NSCocoaErrorDomain 134504` и исторический no-plan fallback, стиравший данные (`AppSchemaVersions.swift:79-89`). Чтобы сделать это безопасно, нужно сначала заморозить весь AccountsCore-граф V10 в `AppSchemaV10AccountsCoreModels.swift` (по образцу V6/V7) и только потом заводить V11. Работоспособно, но это самая дорогая и самая опасная операция в проекте, с обязательным замером эталонных checksum.
- Не покрывает легаси `Card` — для него всё равно нужен второй путь.
- Нарушает SRP ядра: `Account` — event-sourcing финансовая модель, декор в ней лишний.

### Вариант (б) — отдельная таблица `AccountAppearance`, ключ = ID счёта ✅ РЕКОМЕНДУЮ

Новый `@Model AccountAppearance` (`accountID: UUID` **обычным полем, без `@Relationship`**) + `AppSchemaV11 = AppSchemaV10.models + [AccountAppearance.self]` + lightweight-стадия V10→V11.

- **Прецедент уже в проекте:** `AccountAttachment` (`Core/AccountsCore/RealEstate/RealEstateModels.swift:118-165`) сделан ровно так и приехал аддитивной V8: «Additive tables only: V7 model declarations remain byte-for-byte unchanged» (`AppSchemaVersions.swift:146-154`). Декларации `Account` не трогаются → checksum V10 не сдвигается вовсе, риск 134504 = 0.
- **Один механизм на оба мира:** ключ — UUID, а не связь; legacy `Card.uniqueID` и core `Account.id` ложатся в одну таблицу. Один резолвер презентации, один пикер, никаких «двойников».
- **Обратимо:** не нравится дизайн — удаляется строка, финансовые данные не при чём.
- Цена: (1) нет каскадного удаления → чистка сирот при удалении счёта (`DataIntegrityCleaner`), (2) нет relationship-выборки → для списка нужен словарь `[UUID: AccountAppearance]` одним fetch (не N запросов в строках), (3) нужен экспорт/импорт в бэкап — `ModelTypeRegistry.register` + `ModelImporter` по образцу `AccountAttachmentImporter` (`Core/AccountsCore/AccountsCoreFeatureRegistration.swift:31,44,74-102`), иначе дизайны молча теряются при restore.

**Рекомендация: (б).** Риск дешевле на порядок, покрывает оба мира, не пускает декор в финансовое ядро. Вариант (а) оправдан только если решим, что визуал — часть доменной идентичности счёта; сейчас доказательств этому нет.

### Что именно хранить в `AccountAppearance`

```
id, accountID, presetRaw: String, tintHex: String?, iconName: String?, updatedAt
```

- `presetRaw` — id пресета из **кодового каталога** (градиент + паттерн + позиция лого). Пресеты в коде, не в БД: их правка/добавление не требует миграции и не раздувает бэкап.
- `iconName` — тот же формат, что понимает `AccountIconBadgeView`: SF Symbol или `monogram:СБ`.
- **Пользовательские изображения в этот шаг НЕ входят.** Если владелец захочет «своё фото на карте» — переиспользовать `AccountAttachment` (`.externalStorage`, `isCover`), отдельной фазой, с явным решением по размеру бэкапа: `AccountAttachment.export()` кладёт картинку **base64 в JSON** (`RealEstateModels.swift:160`) — десяток обложек заметно раздует CloudKit-бэкап.

---

## 5. Что переиспользуем (не пишем заново)

| Актив | Путь | Как используем |
|---|---|---|
| `AccountIconBadgeView` | `UI/Services/Finances/Icons/AccountIconBadgeView.swift` | готовый бейдж: монограмма → SF Symbol → fallback, hex-цвет, размер. Строки списка и малый бейдж на hero — без изменений API. ⚠️ внутри `Font.system(size:)` — при доработке перевести на токены. |
| `AccountIconSet` + `AccountIconPickerSheet` | `UI/Services/Finances/Icons/` | каталог иконок (120 строк) и готовый лист выбора — галерею дизайнов делаем **вкладкой рядом**, не новым экраном. |
| `CashflowAccountPickerDetailsFactory` | ветка `feature/cashflow-account-picker-redesign`, `UI/Services/Cashflow/AccountPicker/CashflowAccountPickerDetails.swift` | **единственная существующая фабрика презентации для обоих миров** (Card / Account / Investment). Её и расширяем до `AccountAppearance` — второй резолвер не заводим. Монограмма по имени (`AccountIconSet.monogramIconName`) остаётся дефолтом core-счёта. |
| `NewCoreAccountRow` + `AccountKind.fallbackIconName` | `.../AccountsCore/NewCoreAccountRow.swift:66-81` | база строки списка; заглушку `iconName: nil` (`:39-40`) заменяем на резолв из appearance. |
| Токены | `UI/Design/AppColors.swift` (`financesGradient`, `cashflowGradient`, `investmentsGradient`, …), `AppSpacing`, `AppTypography`, `AppAnimation`, `GradientBackground` | база палитры пресетов — берём из существующих градиентов, чтобы дизайны не выпадали из системы. |
| `AccountAttachment` | `Core/AccountsCore/RealEstate/RealEstateModels.swift:118` | образец аддитивной side-таблицы + готовый путь для будущих обложек-фото. |

---

## 6. Затрагиваемые экраны и ориентировочный объём

| Экран / файл | Что меняется |
|---|---|
| `AccountDetailView.swift:113-151, 264-330` | hero-карточка вместо/над `standardHeader` |
| `CreditCardDetailSection.swift`, `DebitCard/DebitCardDetailSection.swift`, `Deposit/DepositDetailSection.swift`, `RealEstateDetailSection.swift` | 4 per-type секции со своими заголовками — hero должен встать над ними единообразно, иначе получим 5 разных шапок |
| `FinancesView.swift:1057`, `Rows/FinanceRows.swift:452`, `Editors/FinanceGroupEditorView.swift:592` | три точки отрисовки `NewCoreAccountRow` — визуал строки правим в одном компоненте |
| `ArchivedAccountsView.swift` | приглушённый вариант нового визуала |
| `AccountIconPickerSheet.swift` | + вкладка «Дизайн» (галерея пресетов) |
| `CashflowAccountPickerSheet` (ветка пикера) | подхватывает appearance через существующую фабрику |
| `Localizable.xcstrings` | названия пресетов и заголовки галереи, RU/EN/zh-Hans |

**Ориентир по фазам (план будет отдельным документом после решения владельца):** Ф1 модель + V11 + бэкап-импортер + чистка сирот; Ф2 каталог пресетов + `AccountHeroCardView`; Ф3 галерея выбора; Ф4 редизайн строки/списка «Счета»; Ф5 мост с легаси `Card` (миграция `cardColor`/`customIconColor` в appearance). Ф1 — единственная рискованная.

---

## 7. Риски

1. **Схема (главный).** Даже аддитивная V11 обязана пройти проверку на реальном V10-сторе: `SchemaConsistencyTests` + `SchemaMigrationTests` + замер checksum до/после (памятка `millio-schema-frozen-types-trap`). Никаких правок `AppSchemaV10.models`.
2. **Бэкап/restore.** Без `ModelTypeRegistry.register` + importer дизайны исчезнут после restore, причём молча. Тест: backup → wipe → restore → пресеты на месте.
3. **Сироты.** Удаление/tombstone счёта не удаляет appearance (нет каскада) → чистка в `DataIntegrityCleaner` + тест.
4. **Производительность списка (60+ счетов).** Hero-визуал — только на детальном экране. В списке — существующий бейдж 36pt; appearance грузим одним fetch в словарь, а не запросом на строку. Градиенты дёшевы, а вот декодирование `Data` картинки в теле `View` — нет: если дойдём до обложек, нужен кэш thumbnail'ов вне рендера.
5. **Dark-mode only.** Пресеты рисуются только на чёрном фоне (`AppColors.backgroundTop = .black`); нужен фиксированный контраст текста на ярких градиентах (белый + тень), проверка читаемости на жёлтом/оранжевом. Никаких «светлых» вариантов пресетов.
6. **Локализация.** Названия пресетов — в `Localizable.xcstrings`, RU/EN/zh-Hans; raw-литералов не заводить.
7. **Монетизация.** Галерея дизайнов — естественный PRO-кандидат. Решение принимает владелец; если PRO, гейт только через `EntitlementPolicy`, без параллельных проверок.
8. **Ветка пикера не смержена.** `CashflowAccountPickerDetailsFactory` живёт в `feature/cashflow-account-picker-redesign`. Стартовать реализацию либо после её мержа, либо от неё — иначе получим два резолвера презентации.

---

## 8. Вопросы владельцу (до плана)

1. Хранение — подтвердить (б) (отдельная таблица `AccountAppearance`, V11 аддитивная).
2. Пресеты: только градиенты/паттерны из кода — или сразу нужны свои фото на карте (это +фаза и рост бэкапа)?
3. Галерея дизайнов — Free или PRO?
4. Логотипы банков для core-счетов: заводить справочник банков для `CardMeta.bank` (сейчас свободная строка) или на первом шаге ограничиться монограммой + цветом?
5. Порядок: сначала hero детального экрана (виден сразу) или сначала редизайн списка «Счета»?
