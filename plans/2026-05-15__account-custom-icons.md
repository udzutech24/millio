# Кастомные иконки счетов / Custom Account Icons

**Статус:** РЕАЛИЗОВАН  
**Дата создания:** 2026-05-15  
**Размер:** M (7 файлов изменяются, 3 создаются)

## Задача

Дать пользователю возможность выбрать иконку для каждого финансового счёта (Card / Credit / Investment). Базовый набор — 29 кураторских SF Symbols в 5 категориях. Расширенные опции: монограмма (2–3 символа), выбор цвета бейджа. Фото из галереи — MVP v2 (подфаза 2b, опциональна).

Точки входа: форма создания счёта (inline row → sheet) и форма редактирования.

## Acceptance Criteria

- [ ] У каждого счёта (Card / Credit / Investment) можно задать кастомную иконку
- [ ] 29 SF Symbol пресетов, сгруппированных в 5 категорий
- [ ] Монограмма (2–3 символа) работает как иконка
- [ ] Выбор цвета бейджа — 12 пресетов + color wheel
- [ ] Иконки отображаются в списке счетов (`FinanceRows`) и в обзоре (`FinanceOverviewCardView`)
- [ ] Без кастомной иконки — fallback на тип-based иконку (без регрессий)
- [ ] Пикер доступен при создании счёта (`FinanceAddAccountView`) — inline row → sheet
- [ ] Пикер доступен при редактировании (`CardEditorView`, `CreditEditorView`, `InvestmentEditorView`)
- [ ] Lightweight migration SwiftData (Optional поля = auto-migration, без VersionedSchema)
- [ ] Локализованы все новые строки (RU + EN + zh-Hans)

## Архитектура

### Новые поля в моделях

```swift
// Card.swift, Credit.swift, Investment.swift — добавить в каждый @Model:
var customIconName: String?       // SF Symbol name или "monogram:СБ"
var customIconColor: String?      // Hex цвет фона бейджа, nil = дефолтный акцент типа
```

> Optional без default → SwiftData lightweight migration, VersionedSchema не нужен.

### Приоритет рендера иконки

1. `customIconName` с префиксом `"monogram:"` → текст (2–3 символа) в бейдже
2. `customIconName` (SF Symbol) → `Image(systemName:)`
3. Fallback: тип-based иконка (`CardType.icon`, `InvestmentCategory.icon`, etc.)

### Новые файлы

| Файл | Назначение |
|------|-----------|
| `millio/UI/Services/Finances/Icons/AccountIconSet.swift` | Статический каталог 29 SF Symbols в 5 категориях |
| `millio/UI/Services/Finances/Icons/AccountIconBadgeView.swift` | Reusable view: рендер иконки с цветным фоном |
| `millio/UI/Services/Finances/Icons/AccountIconPickerSheet.swift` | Sheet: Пресеты / Монограмма + color picker |

### Изменяемые файлы

| Файл | Что меняется |
|------|-------------|
| `millio/UI/Services/CardIndex/Card.swift` | +2 поля: `customIconName`, `customIconColor` |
| `millio/UI/Services/Credits/Credit.swift` | +2 поля |
| `millio/UI/Services/Investments/Investment.swift` | +2 поля |
| `millio/UI/Services/Finances/Rows/FinanceRows.swift` | Строки 454, 502: `iconBadge()` → `AccountIconBadgeView`; строка 268: `item.info.icon` учитывает `customIconName` |
| `millio/UI/Services/Finances/Components/FinanceOverviewCardView.swift` | Строки 241, 269, 297, 325, 750, 821: `accountIcon:` → `resolvedIconName` |
| `millio/UI/Services/Finances/Editors/FinanceAddAccountView.swift` | Inline row «Иконка» → `AccountIconPickerSheet` |
| `millio/UI/Services/Finances/CardEditorView.swift` | Та же row в edit-режиме |
| `millio/UI/Services/Finances/CreditEditorView.swift` | Та же row |
| `millio/UI/Services/Finances/InvestmentEditorView.swift` | Та же row |
| `millio/Localizable.xcstrings` | Новые ключи (см. Фазу 5) |

## Каталог иконок (AccountIconSet) — 29 штук

```
Банки / Счета (8):
  building.columns.fill, banknote.fill, creditcard.fill,
  wallet.pass.fill, lock.shield.fill,
  dollarsign.circle.fill, eurosign.circle.fill, rublesign.circle.fill

Инвестиции (7):
  chart.line.uptrend.xyaxis, chart.bar.fill,
  arrow.up.right.circle.fill, bitcoinsign.circle.fill,
  chart.pie.fill, trophy.fill, sparkles

Имущество (5):
  house.fill, car.fill, airplane, briefcase.fill, crown.fill

Сбережения (5):
  heart.fill, leaf.fill, flame.fill, bolt.fill, star.fill

Прочее (4):
  globe, graduationcap.fill, pawprint.fill, flag.fill
```

## Цветовая палитра (12 пресетов + wheel)

```
Синий: #3B82F6 · Голубой: #38BDF8 · Циан: #06B6D4
Зелёный: #10B981 · Лайм: #84CC16
Жёлтый: #F59E0B · Оранжевый: #F97316
Красный: #EF4444 · Розовый: #EC4899
Фиолетовый: #8B5CF6 · Индиго: #6366F1
Серый: #6B7280
```

## Фазы реализации

### Фаза 1 — Data layer [ ]

- [ ] `Card.swift`: добавить `customIconName: String?`, `customIconColor: String?`
- [ ] `Credit.swift`: то же
- [ ] `Investment.swift`: то же
- [ ] `AccountIconSet.swift`: структура с 5 категориями и массивом из 29 иконок

**Gate:** компилируется, тесты не падают.

### Фаза 2a — UI Components [ ]

- [ ] `AccountIconBadgeView.swift`:
  - Параметры: `iconName: String?`, `iconColor: String?`, `fallback: String`, `size: CGFloat`
  - Рендер: monogram-префикс → текст, иначе SF Symbol, иначе fallback
  - Цветной фон бейджа с glassmorphism-стилем (overlay на цвет, `.ultraThinMaterial`)

- [ ] `AccountIconPickerSheet.swift`:
  - Секция «Пресеты»: grid 5/row, 5 категорий с заголовками, tap = выбор + закрытие
  - Секция «Монограмма»: `TextField` (limit 3 chars) + color picker
  - Color picker: 12 цветовых чипов + нативный `ColorPicker` (wheel)
  - Кнопки «Выбрать» / «Отмена»

**Gate:** Preview рендерится корректно для всех режимов.

### Фаза 2b — Фото из галереи (MVP v2, опционально) [ ]

> Реализовывать только после 2a. Можно пропустить в текущей итерации.

- [ ] `Card.swift`, `Credit.swift`, `Investment.swift`: добавить `customIconPhotoData: Data?` (thumbnail 128×128 JPEG ≈ 10–15 KB)
- [ ] `AccountIconBadgeView.swift`: добавить параметр `photoData: Data?`, приоритет выше SF Symbol
- [ ] `AccountIconPickerSheet.swift`: добавить секцию «Фото» с `PhotosUI.PhotosPicker` + ресайз до 128×128

### Фаза 3 — Рендеринг [ ]

Заменить хардкоженные иконки на `AccountIconBadgeView` / `resolvedIconName` в конкретных местах:

- [ ] `FinanceRows.swift:454` — `iconBadge()` → `AccountIconBadgeView(iconName: card.customIconName, fallback: card.cardType.icon, ...)`
- [ ] `FinanceRows.swift:502` — то же для второго `iconBadge()`
- [ ] `FinanceRows.swift:268` — `item.info.icon` → `item.info.resolvedIconName` (вычисляемое свойство `FinanceAccountInfo`)
- [ ] `FinanceOverviewCardView.swift:241` — `accountIcon: info.icon` → `resolvedIconName`
- [ ] `FinanceOverviewCardView.swift:269` — `accountIcon: card.cardType.icon` → `card.resolvedIconName`
- [ ] `FinanceOverviewCardView.swift:297` — `accountIcon: credit.creditType.icon` → `credit.resolvedIconName`
- [ ] `FinanceOverviewCardView.swift:325` — `accountIcon: investment.category.icon` → `investment.resolvedIconName`
- [ ] `FinanceOverviewCardView.swift:750` — `Image(systemName: account.icon)` → `AccountIconBadgeView`
- [ ] `FinanceOverviewCardView.swift:821` — то же

> `resolvedIconName` — computed property на каждой модели: `customIconName ?? typeBasedIcon`

**Gate:** визуально всё выглядит как раньше, ни один тип счёта не сломан.

### Фаза 4 — Интеграция в формы [ ]

- [ ] `FinanceAddAccountView.swift`: добавить `@State var draftIconName: String?` + `@State var draftIconColor: String?`, inline row «Иконка» с превью + шеврон → sheet, при сохранении передавать поля в `init`
- [ ] `CardEditorView.swift`: та же row, биндинг на `card.customIconName` / `card.customIconColor`
- [ ] `CreditEditorView.swift`: то же
- [ ] `InvestmentEditorView.swift`: то же

**Gate:** создание + редактирование работают end-to-end, иконка сохраняется и отображается.

### Фаза 5 — Локализация и self-audit [ ]

**Ключи для `Localizable.xcstrings`:**

```
account.icon_picker.title           = "Иконка" / "Icon" / "图标"
account.icon_picker.tab.presets     = "Пресеты" / "Presets" / "预设"
account.icon_picker.tab.monogram    = "Монограмма" / "Monogram" / "字母"
account.icon_picker.monogram.placeholder = "2–3 символа" / "2–3 chars" / "2–3个字符"
account.icon_picker.section.banking = "Банки / Счета" / "Banking" / "银行"
account.icon_picker.section.invest  = "Инвестиции" / "Investments" / "投资"
account.icon_picker.section.assets  = "Имущество" / "Assets" / "资产"
account.icon_picker.section.savings = "Сбережения" / "Savings" / "储蓄"
account.icon_picker.section.other   = "Прочее" / "Other" / "其他"
```

- [ ] Добавить все ключи в `Localizable.xcstrings`
- [ ] Self-audit: каждый AC из списка покрыт
- [ ] Impact analysis: регрессии в `FinanceRows`, `FinanceOverviewCardView`, SwiftData migration

## Журнал

- 2026-05-15: план создан + прошёл Challenge Loop (3 вопроса)

## Риски

- `FinanceRows.swift` и `FinanceOverviewCardView.swift` — много мест. Строчные ссылки зафиксированы выше, при merge проверить актуальность номеров.
- Фото (2b): `customIconPhotoData: Data?` увеличивает размер CloudKit snapshot на ≈10–15 KB/счёт. Для 50 счетов ≈ 700 KB — допустимо.
