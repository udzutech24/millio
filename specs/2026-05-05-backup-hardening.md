# Spec: backup-hardening

**Date:** 2026-05-05
**Stage:** 2 / Spec
**Research:** [`thoughts/research/2026-05-05-backup-hardening.md`](../thoughts/research/2026-05-05-backup-hardening.md)
**Plan:** [`plans/2026-05-05-backup-hardening.md`](../plans/2026-05-05-backup-hardening.md) (создаётся следующим шагом)

---

## Problem

Четыре доказанных проблемы recovery subsystem, блокирующих качество продукта:

1. **Default mode = device-key** → `restore_decryptable_rate` < 50% при переустановке / смене устройства. Backup физически в CloudKit, но расшифровать нельзя (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
2. **UI не честен** → warning о device-key ограничении доступен только в раскрытой секции «Защита», не на главном экране backup.
3. **RestoreView: 2 hardcoded EN строки** → `.restoreFailed("Backup lookup timed out. iCloud may still be syncing. Try again.")` не локализованы — release-blocker для zh-Hans.
4. **Launch-time recovery без таймаута** → `presentRestoreFlowIfNeeded()` вызывает `lastBackupInfo()` без ограничения времени; медленный CloudKit → зависание при старте.

---

## Goal

Сделать backup честным и надёжным: пользователь по умолчанию получает переносимый backup, видит ясное предупреждение о рисках device-key, приложение не зависает при старте и полностью локализовано.

---

## Scope

### Phase 0.1 — Default mode: device-key → passphrase

- Изменить `@State private var encryptionMode: BackupEncryptionMode = .deviceKey` → `.passphrase` в `BackupManagementView.swift`.
- Изменить `onAppear` логику: если `isEncryptionEnabled == true` и сохранённый режим не определён явно → предложить passphrase как default для новых пользователей.
- Добавить явное хранение выбранного режима (отдельный ключ в `SettingsManager` или UserDefaults), чтобы не перетирать выбор пользователя при каждом `onAppear`.
- Для существующих пользователей с `isEncryptionEnabled == true` (device-key) — показать одноразовый migration notice с предложением перейти на passphrase.

### Phase 0.2 — UI warning для device-key

- Добавить inline warning-баннер в `BackupManagementView` на главном экране (вне picker-а), видимый когда `encryptionMode == .deviceKey && appState.isBackupEnabled`.
- Обновить текст `backup.encryption.mode.device.risk` в L10n: явно указать «не переносимый», не «may fail».
- Переименовать заголовок device-key в L10n: текущий `"This iPhone only"` → уточнить до `"This Device Only"`.

### Phase 0.3 — RestoreView локализация (2 hardcoded EN строки)

- Заменить оба `.restoreFailed("Backup lookup timed out...")` на `BackupL10n.tr("backup.restore.error.lookup_timeout", fallback: "...")`.
- Добавить ключ `backup.restore.error.lookup_timeout` в `Localizable.xcstrings` для RU/EN/zh-Hans.

### Phase 0.4 — Launch-time recovery timeout

- Обернуть вызов `lastBackupInfo()` в `presentRestoreFlowIfNeeded()` в `millioApp.swift` в `withTimeout`.
- Таймаут: 10 секунд (консервативно; паттерн уже есть в `RestoreView.withTimeout`).
- При timeout → не показывать RestoreView (не блокировать старт приложения).

---

## Non-Goals

- Ring buffer backup (7 daily + 4 weekly) — Phase 1.1, отдельная задача.
- Backup health score / verified restore flow — Phase 1.5, отдельная задача.
- Structured telemetry на backup/restore операции — Phase 1.7, отдельная задача.
- Добавление режима `.unencrypted` — не включается в Phase 0 (требует отдельной security оценки).
- Passphrase recovery / хранение вне устройства — Phase 1+.
- Смена CloudKit query таймаута в `RestoreView` (уже 8s — достаточно для Phase 0).
- Какие-либо изменения в `CashflowViewModel` или `FinanceViewModel`.

---

## Acceptance Criteria

### Phase 0.1

- [ ] Новый пользователь, впервые открывающий backup-экран, видит **passphrase** как выбранный режим по умолчанию (не device-key).
- [ ] Существующий пользователь с включённым backup в device-key режиме при следующем открытии backup-экрана видит одноразовый migration notice.
- [ ] Выбор режима сохраняется между сессиями явно в `SettingsManager` / UserDefaults (не вычисляется из `isEncryptionEnabled` каждый `onAppear`).
- [ ] Unit-тест: при `isEncryptionEnabled == true` и отсутствии явно сохранённого режима — computed default = `.passphrase`.

### Phase 0.2

- [ ] При `encryptionMode == .deviceKey && appState.isBackupEnabled` на главном экране backup виден inline warning (отдельный от picker-а).
- [ ] Текст риска device-key не содержит «may fail» — явно указывает «не переносимый backup».
- [ ] Warning отображается на RU, EN и zh-Hans (проверяется через preview с явной locale).

### Phase 0.3

- [ ] `RestoreView.swift` не содержит ни одного hardcoded строкового литерала (EN или RU), не обёрнутого в `BackupL10n.tr()` или `String(localized:)`.
- [ ] Ключ `backup.restore.error.lookup_timeout` добавлен в `Localizable.xcstrings` со значениями для `ru`, `en`, `zh-Hans`.
- [ ] Существующий тест локализации (если есть) проходит без изменений; при отсутствии — добавить smoke-тест на отсутствие raw RU/EN в RestoreView.

### Phase 0.4

- [ ] `presentRestoreFlowIfNeeded()` в `millioApp.swift` не зависает: при медленном CloudKit (> 10s) функция возвращает управление без вызова `.restoring`.
- [ ] Unit-тест `LaunchRecoveryPolicy`: при `latestBackupInfo == nil` (timeout или отсутствие) → решение `.skip(.noBackupAvailable)`.
- [ ] Регрессия: нормальный запуск (с backup, CloudKit быстрый) → `presentRestore` срабатывает как раньше.

---

## Constraints

- **Стек:** Swift · SwiftUI · SwiftData · CloudKit · StoreKit 2 · iOS 17+
- **Безопасность:** не понижать уровень шифрования существующих backup-ов; passphrase не хранить в UserDefaults plain text (только в Keychain).
- **Обратная совместимость:** пользователи с device-key backup-ами должны по-прежнему мочь их восстановить (не ломаем decrypt path).
- **Локализация:** все новые строки — через `BackupL10n.tr()` + `Localizable.xcstrings`, не hardcoded.
- **Размер задачи:** Phase 0 = M (3–10 файлов). Каждая phase — отдельный коммит.

---

## Edge Cases

- **Пользователь задал passphrase, сохранил, удалил приложение** → при reinstall: режим = passphrase (default), backup в CloudKit есть → RestoreView показывает backup → пользователь вводит passphrase → decryptable. ✓
- **Пользователь создал device-key backup, сменил устройство** → RestoreView показывает backup → попытка decrypt → `keychainKeyMissingOnDevice` → явная ошибка с объяснением. Нужен информативный error text (уже есть `RestoreFailureCode.keychainKeyMissingOnDevice`?).
- **Миграция: isEncryptionEnabled == true, нет явно сохранённого режима** → не перетирать device-key молча; показать notice «рекомендуем перейти на passphrase».
- **CloudKit timeout при запуске + пустой store** → не показывать RestoreView (пользователь попадёт в пустое приложение); добавить баннер «Проверьте iCloud» на главном экране.
- **Passphrase mode default → пользователь нажал «создать backup» без ввода passphrase** → существующий guard уже блокирует (строки 217–223 BackupManagementView); убедиться, что он работает с новым default.

---

## Open Questions

1. **Хранение режима:** добавить `backupEncryptionMode: String` в `SettingsManager` или использовать отдельный `@AppStorage`? — решение влияет на migration logic.
2. **Migration notice для device-key:** показывать alert или inline banner? Должен ли он блокировать backup до выбора режима?
3. **Timeout для `presentRestoreFlowIfNeeded`:** 10s — достаточно? Или сделать configurable/testable через injection?
4. **Что показать пользователю при CloudKit timeout в launch flow** (пустой store, но backup не найден из-за timeout)? Текущее решение — просто не показывать RestoreView. Нужен ли баннер на главном экране?
5. **Grandfathering device-key пользователей:** сколько у них времени до принудительной миграции? Или миграция только по согласию?
