# Spec: ReminderMeta — единая модель напоминаний для счетов AccountsCore

**Date:** 2026-07-05
**Stage:** 2 / Spec
**Research:** только чтение веток `develop` + `feature/accounts-core` (файлы кода на `develop` не существуют — читались через `git show feature/accounts-core:<path>`, само ядро правится только на своей ветке)
**Родитель:** открытый вопрос №5 в `specs/2026-07-05-account-detail-per-type.md` (строка 220 плана: «Единый ReminderMeta — одно решение вместо четырёх»)

## Problem

Сейчас у 4 из 6 meta-структур в `millio/Core/AccountsCore/AccountMeta.swift` есть **сиротские** поля-намёки на напоминания, каждое — само по себе, без единой модели и без единого механизма планирования:

- `DepositMeta.remindEnd: Bool` — есть, но экран деталей счёта его **не показывает** («мёртвый тумблер», см. план account-detail-per-type §вклад).
- `LoanMeta.paymentDay: Int?` — есть день платежа, но нет флага/семантики «напомнить об этом дне».
- `DebtMeta` — нет вообще никакого поля напоминания (спека прямо требует `remindDaysBefore`, без него UI не показывает контрол).
- `ManualAssetMeta.revalReminderMonths: Int?` — есть и **работает**, но только как in-app `StalenessBadge» — не как push-уведомление.

Ни одно из этих полей не подключено к `NotificationManager`: единственный рабочий пример push-уведомления по финансовому объекту — `scheduleDepositMaturityNotification` в `NotificationManager.swift:375`, но он относится к **легаси** `Investment`-модели (вызывается из `InvestmentViewModel.swift`), не к `AccountsCore.Account`. Для нового ядра планирования нет вообще.

Если для каждого из 4 типов продукта проектировать напоминание отдельно — получим 4 разных enum, 4 разных набора identifiers для `UNNotificationRequest`, 4 разных места отмены/переноса при архивации/восстановлении/бэкапе. Это не абстракция ради абстракции — это тот случай, когда **одинаковая по форме проблема** (когда сработать, что показать, как отменить) решается 4 раза с гарантированным дрейфом логики.

## Goal

Одна value-структура `ReminderMeta` (Codable, Equatable), один enum триггера, один сервис планирования в `NotificationManager`, используемые всеми 4 типами счетов, которым нужны напоминания.

## Scope

- Структура `ReminderMeta` с enum `ReminderTrigger` (см. Decision 2).
- Размещение поля `reminder: ReminderMeta?` в `Account` (см. Decision 3 — не в каждой meta-структуре).
- Сериализация в `exportDict()/init?(exportDict:)` по паттерну существующих meta (Decimal-строки, Date → `timeIntervalSince1970`, enum → `rawValue`).
- Расширение `NotificationManagerProtocol` методами `scheduleAccountReminder(for:)` / `cancelAccountReminder(for:)`, использующими единый identifier-namespace `account_reminder_<uuid>`.
- Правила пересчёта/отмены триггера: создание счёта, редактирование reminder-полей, архивация, восстановление из архива, полный restore из CloudKit-бэкапа, смена скоупа guest→user (см. Decision 6).
- Миграция существующих полей: `DepositMeta.remindEnd`, `ManualAssetMeta.revalReminderMonths` — что происходит с ними при введении `ReminderMeta` (см. Decision 7).

## Non-Goals

- UI-реализация (Picker/Toggle в `AccountEditSheet`) — это Фаза после стабилизации V5-схемы, согласно плану account-detail-per-type (строка 27). Эта спека фиксирует только модель и контракт сервиса.
- Push-уведомления для легаси `Investment`-модели — не трогаем, `scheduleDepositMaturityNotification` остаётся как есть до момента полного перехода на AccountsCore.
- Server-side / silent push — весь механизм остаётся локальным `UNUserNotificationCenter`, как и всё остальное в `NotificationManager`.
- Snooze / повторные напоминания с интерактивными действиями (`UNNotificationAction`) — не в этой итерации.

## Decisions

### 1. Структура `ReminderMeta`

```swift
/// Единая модель напоминания для счёта нового ядра. Одна структура вместо
/// четырёх разрозненных полей (DepositMeta.remindEnd, LoanMeta.paymentDay-флага,
/// DebtMeta.remindDaysBefore, ManualAssetMeta.revalReminderMonths).
struct ReminderMeta: Codable, Equatable {
    var trigger: ReminderTrigger
    /// Пользователь мог один раз выключить напоминание, не потеряв настройки (день/срок) —
    /// повторное включение не требует re-input.
    var isEnabled: Bool
    /// UNNotificationRequest не хранит состояние — если permission не выдан или напоминание
    /// не удалось запланировать (см. Edge Cases), это фиксируем здесь, а не гадаем по системе.
    var lastScheduledAt: Date?
}

/// Момент/правило срабатывания напоминания. Один enum на все 4 сценария счёта.
enum ReminderTrigger: Codable, Equatable {
    /// Кредит: напомнить в конкретный день каждого месяца (paymentDay из LoanMeta).
    case dayOfMonth(day: Int)
    /// Вклад: напомнить в фиксированную дату (termEnd из DepositMeta).
    case fixedDate(Date)
    /// Долг: напомнить за N дней до целевой даты (dueDate из DebtMeta).
    case daysBefore(days: Int, target: Date)
    /// Ручной актив: периодическое напоминание о переоценке, интервал в месяцах.
    case periodic(intervalMonths: Int, anchor: Date)
}
```

**Обоснование:** каждый casus — это ровно то, что уже описано в 4 полях-сиротах, просто объединённое в одну сериализуемую форму. Никаких новых сценариев не добавляется — только унификация существующих намерений из спеки экрана.

### 2. Где живёт поле — `Account.reminder`, НЕ внутри каждой meta

Рекомендация: **одно поле `var reminder: ReminderMeta?` на уровне `Account`**, не по одному внутри `DepositMeta`/`LoanMeta`/`DebtMeta`/`ManualAssetMeta`.

Почему:
- `NotificationManager` работает по идентификатору счёта (`account.id`), а не по типу meta — планировщику всё равно, кредит это или долг, ему нужны `trigger` + `isEnabled` + `account.id` для текста уведомления (`account.name`, `account.kind`).
- Если размазать `ReminderMeta` по 4 meta-структурам — это ровно тот дрейф, который мы устраняем: 4 разных пути чтения одного и того же поля, 4 разных места, откуда `AccountEditSheet` должен доставать reminder-контрол.
- `Account.participates(on:)` уже показывает паттерн: общие для всех типов свойства (`includeInTotal`, `archivedAt`) живут на `Account`, а не дублируются в meta. `reminder` — по своей природе общее свойство (у всех 4 типов одна и та же семантика «включено/выключено + когда»), просто с разным `ReminderTrigger` внутри.
- `MarketMeta` и `CardMeta` не получают `reminder` — там его никто не просит (не в scope спеки экрана), а enum `ReminderTrigger` не заставляет их иметь фиктивный кейс.

Компромисс: поле `reminder: ReminderMeta?` на `Account` вместо энергии в каждой meta-структуре не создаёт лишней абстракции — это ровно один optional-поле, аналогичный по цене `note: String?`.

### 3. Сериализация — по паттерну существующих meta

`Account.export()`/импорт уже собирает словарь верхнего уровня из всех полей meta. `ReminderMeta` добавляется туда же, тем же способом:

```swift
extension ReminderMeta {
    func exportDict() -> [String: Any] {
        var dict: [String: Any] = ["isEnabled": isEnabled]
        if let lastScheduledAt { dict["lastScheduledAt"] = lastScheduledAt.timeIntervalSince1970 }
        dict["trigger"] = trigger.exportDict()
        return dict
    }
    init?(exportDict dict: [String: Any]) {
        guard let isEnabled = dict["isEnabled"] as? Bool,
              let triggerDict = dict["trigger"] as? [String: Any],
              let trigger = ReminderTrigger(exportDict: triggerDict) else { return nil }
        self.init(trigger: trigger,
                  isEnabled: isEnabled,
                  lastScheduledAt: (dict["lastScheduledAt"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) })
    }
}
```

`ReminderTrigger.exportDict()` — тегированный словарь `["kind": "dayOfMonth", "day": 5]` и т.п., даты — `timeIntervalSince1970` (тот же паттерн, что `termEnd`/`dueDate` в существующих meta), никаких Decimal здесь нет (только Int/Date), так что проблема двойного `JSONSerialization`-бриджинга Decimal→Double из комментария в `AccountMeta.swift` этой структуры не касается.

### 4. Расширение `NotificationManagerProtocol`

```swift
protocol NotificationManagerProtocol {
    // ...существующие методы...
    func scheduleAccountReminder(accountID: UUID, accountName: String, kind: AccountKind, reminder: ReminderMeta) async
    func cancelAccountReminder(accountID: UUID)
}
```

Identifier: `"account_reminder_" + accountID.uuidString` — единый namespace, аналогично `depositNotificationPrefix` в существующем коде. **Один identifier на счёт**, не на trigger-кейс: у счёта не может быть двух активных напоминаний одновременно (upsert = cancel + reschedule).

`.periodic` — единственный кейс, требующий **повторяющегося** триггера. `UNCalendarNotificationTrigger(dateMatching:repeats:)` с `repeats: true` не поддерживает интервалы в месяцах кроме через `dateComponents` без `year` (компонент `day`+`month` без `year` повторяется ежегодно, не ежемесячно/ежеквартально). Поэтому `.periodic` реализуется **не как repeats-триггер**, а как **одноразовый триггер на ближайшую дату + self-rescheduling**: при доставке уведомления (или при каждом открытии счёта, если проще — см. Decision 6) следующее напоминание переппланируется на `anchor + intervalMonths`. Это решение переиспользует существующий паттерн `nextOccurrenceDate` из `buildScheduledReminderPayloads` (Cashflow scheduled reminders уже решают ту же задачу «следующая дата по интервалу»).

### 5. Текст уведомлений

Как и `scheduleDepositMaturityNotification`, текст — через `Localizable.xcstrings`, новые ключи:
- `accounts_core.reminder.loan.body` — «Платёж по «%@» — %@» (день месяца)
- `accounts_core.reminder.deposit.body` — «Вклад «%@» заканчивается %@»
- `accounts_core.reminder.debt.body` — «Через %d дн. срок возврата по «%@»»
- `accounts_core.reminder.manual_asset.body` — «Пора переоценить «%@»»

RU/EN/zh-Hans — все три сразу, не откладывать (правило проекта: raw-литералы в UI запрещены, `RestoreView` уже release-blocker по этой причине, повторять паттерн нельзя).

### 6. Когда планируем/перепланируем/отменяем

| Событие | Действие |
|---|---|
| `createAccount` с уже заполненным `reminder.isEnabled == true` | `scheduleAccountReminder` сразу после `try modelContext.save()` |
| Редактирование reminder-полей в `AccountEditSheet` (day/date/isEnabled) | `cancelAccountReminder` → если `isEnabled` → `scheduleAccountReminder` (upsert, не diff) |
| `archiveAccount` | `cancelAccountReminder` — заархивированный счёт не должен напоминать о платеже/переоценке |
| `restoreAccount` | если `reminder.isEnabled` и trigger-дата ещё не прошла → `scheduleAccountReminder`; если прошла (см. Edge Cases) → не планировать, оставить `isEnabled` как есть, дать пользователю увидеть stale-состояние в UI |
| `physicallyDelete` | `cancelAccountReminder` (до `modelContext.delete`) |
| Полный CloudKit restore (`RestoreView`) | После snapshot-restore пройтись по всем неархивным `Account` с `reminder.isEnabled == true` и **переппланировать все** — pending `UNNotificationRequest` на старом устройстве/до переустановки не переживают restore, это не merge, а полная замена локальных данных (инвариант backup/restore), поэтому все локальные OS-scheduled notifications состояние не наследуют и их нужно пересобрать с нуля из данных |
| Смена скоупа guest→user (после входа) | `AccountsCoreService`, судя по коду, не хранит explicit guest/userID scope на `Account` (в отличие от некоторых других моделей) — id счёта не меняется при смене скоупа, поэтому reminder identifiers остаются валидными, **действие не требуется**. Если ресёрч Фазы реализации найдёт scope-поле на `Account` (не увиденное в этом чтении) — пересмотреть |

### 7. Миграция существующих полей

- `DepositMeta.remindEnd: Bool` — **удалить** при введении `ReminderMeta` (сейчас не используется нигде в UI/логике — «мёртвый тумблер», подтверждено планом). Не мигрировать значение: поле никогда не выставлялось пользователем осмысленно (контрол не показывался), миграция данных не нужна.
- `ManualAssetMeta.revalReminderMonths: Int?` — **оставить как есть** для in-app `StalenessBadge` (не зависит от push, используется отдельным расчётом «сколько месяцев с последней переоценки»), но **добавить** `Account.reminder = ReminderMeta(trigger: .periodic(intervalMonths: revalReminderMonths, anchor: lastRevaluationDate), isEnabled: true)` как надстройку для push, синхронизируемую при каждом изменении `revalReminderMonths` в `AccountEditSheet`. Два поля не дублируют друг друга: `revalReminderMonths` — источник правды для конфигурации интервала (форма редактирования его и показывает), `reminder` — производное представление для планировщика.
- `LoanMeta.paymentDay` / `DebtMeta.dueDate` — уже существуют, ничего не меняется, `reminder` использует их как исходные данные при создании `ReminderTrigger`, не дублирует их напрямую (trigger хранит собственную копию на момент upsert — обоснование в Edge Cases, «расхождение при последующем редактировании исходного поля»).

## Acceptance Criteria

- [ ] `ReminderMeta`/`ReminderTrigger` компилируются, `Codable`+`Equatable`, `exportDict()`/`init?(exportDict:)` следуют паттерну существующих meta-структур (Decimal-строки не нужны — только Int/Date/enum rawValue).
- [ ] `NotificationManagerProtocol` расширен `scheduleAccountReminder`/`cancelAccountReminder`, один identifier-namespace на счёт (upsert, не накопление pending-запросов).
- [ ] `.periodic` реализован через одноразовый триггер + self-rescheduling (не `repeats: true` с потерей точности интервала).
- [ ] Все 6 lifecycle-точек из таблицы Decision 6 покрыты вызовами schedule/cancel.
- [ ] Restore из CloudKit-бэкапа переппланирует ВСЕ активные reminder заново (не полагается на survive pending-запросов).
- [ ] Новые локализационные ключи добавлены в RU/EN/zh-Hans одновременно, без raw-литералов.
- [ ] `DepositMeta.remindEnd` удалено, migration path задокументирован (не требует backward-совместимого чтения старых бэкапов с этим полем — экспорт никогда не читал его наружу для действия).

## Constraints

- **Стек:** Swift Concurrency (async/await) — `scheduleAccountReminder` асинхронный, как существующие методы `NotificationManagerProtocol`.
- **Offline-first:** вся модель — локальный SwiftData `Account.reminder`, без сетевых зависимостей. `UNUserNotificationCenter` — системный локальный API, не CloudKit.
- **UI-токены/локализация:** не в scope этой спеки (UI — отдельная фаза), но новые строки для body уведомлений заводятся сразу по правилам локализации проекта.

## Edge Cases

- **Прошедшая дата при создании/восстановлении** (`dueDate` долга уже в прошлом, `termEnd` вклада уже прошёл) — `scheduleAccountReminder` не должен падать или создавать триггер «в прошлое» (`UNCalendarNotificationTrigger` с прошедшей датой не сработает, но и не должен тихо проглатываться — логировать `logger.warning` и не создавать request, дать UI отдельно показать «просрочено» badge).
- **Часовые пояса** — `fireDate`/`dueDate` хранятся как `Date` (абсолютный момент, UTC-based), `UNCalendarNotificationTrigger` строится из `calendar.dateComponents` в **текущем** календаре устройства (как уже делает `NotificationManager` для daily reminder) — при смене таймзоны пользователем между созданием и восстановлением напоминание сдвинется вместе с локальным временем устройства; это ожидаемое поведение (совпадает с текущим `scheduleDepositMaturityNotification`), не регрессия.
- **Permission отключён** — `scheduleAccountReminder` вызывает `requestAuthorization()` (как существующий `scheduleDepositMaturityNotification`), при `false` — no-op, `reminder.isEnabled` в модели остаётся `true` (это желание пользователя, не разрешение системы) — UI должен отдельно показывать баннер «уведомления выключены в системе», не путать эти два состояния.
- **Restore на новом устройстве** — см. Decision 6 таблица; все reminders должны быть переппланированы, т.к. `UNUserNotificationCenter` — per-device, а не часть CloudKit backup payload.
- **Редактирование исходного поля без переппланирования** (например, пользователь поменял `paymentDay` в `LoanMeta`, но `AccountEditSheet` не вызвал upsert reminder) — это баг в UI-слое (Фаза после этой спеки), а не в модели; спека фиксирует контракт «reminder меняется вместе с исходным полем в одной транзакции формы», проверяется тестом на уровне ViewModel в фазе реализации UI.

## Open Questions

1. **Периодичность self-rescheduling для `.periodic`** — планировать следующее напоминание при доставке через `UNUserNotificationCenterDelegate` (надёжнее, но требует delegate-хука, которого сейчас нет ни у одного flow в `NotificationManager`) или пересчитывать/чинить `nextOccurrenceDate` при каждом открытии `AccountDetailView` (проще, использует существующий паттерн, но если пользователь не открывает счёт месяцами — напоминание не пересоздастся вовремя после первого срабатывания). Рекомендация: открытие экрана (проще, соответствует KISS, реальный риск «не открыл счёта после переоценки» — приемлем для periodic-сценария, где просрочка на пару дней не критична) — но решение фиксирует владелец.
2. **Нужен ли отдельный digest-режим** (одно уведомление в день со списком всех должных сегодня напоминаний) вместо N отдельных пушей, если у пользователя много кредитов/долгов с совпадающими датами? Не покрыто этой спекой — если владелец считает это важным для UX, нужна отдельная итерация после MVP.
