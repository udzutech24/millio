# Research: backup-hardening

**Date:** 2026-05-05
**Stage:** 1 / Deep Research (read-only)
**Related:** [`specs/2026-05-05-backup-hardening.md`](../../specs/2026-05-05-backup-hardening.md)

## Задача исследования

Проверить реальное состояние backup/restore в кодовой базе по 4 критическим проблемам из `MILLIO_DEEP_ANALYSIS_2026-04-27.md` и `BACKUP_HARDENING_AUDIT.md`: default mode = device-key, UI-честность, локализация RestoreView, launch-time recovery flow.

---

## Findings from codebase

### Current State — Default encryption mode

**Файл:** `millio/Core/Security/BackupEncryption.swift`

- `KeychainBackupEncryption` использует Keychain с атрибутом `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (строка 85).
- Ключ хранится в сервисе `com.millio.backup`, тег `backup.encryption.key`.
- Ключ **не переживает** reinstall / переход на другое устройство — это архитектурный факт, доказан аудитом.

**Файл:** `millio/UI/Profile/BackupExperienceModels.swift`

- `BackupEncryptionMode` enum: два кейса — `.deviceKey` и `.passphrase`.
- `restoreRisk` для `.deviceKey`: `"If you delete the app or move to another device, restore may fail"` — строка через `BackupL10n.tr`.
- Нет третьего кейса `.unencrypted` / `.none`.

**Файл:** `millio/UI/Profile/BackupManagementView.swift:27`

```swift
@State private var encryptionMode: BackupEncryptionMode = .deviceKey
```

- Default при создании View — `.deviceKey`. Это hard-coded.

**Файл:** `millio/UI/Profile/BackupManagementView.swift:301`

```swift
let isDeviceKeyEnabled = SettingsManager.shared.isEncryptionEnabled
encryptionMode = isDeviceKeyEnabled ? .deviceKey : .passphrase
```

- При `onAppear` читает `SettingsManager.shared.isEncryptionEnabled`.
- Если `isEncryptionEnabled == false` → режим `.passphrase` (это контринтуитивно: "не зашифровано" → passphrase).
- Если `isEncryptionEnabled == true` → режим `.deviceKey`.
- Значение `isEncryptionEnabled` по умолчанию в `SettingsManager` — **нужно проверить**, но аудит говорит: device-key по умолчанию.

**Файл:** `millio/Core/Backup/BackupManager.swift:761`

```swift
guard usesSettingsEncryption, SettingsManager.shared.isEncryptionEnabled else { ... }
return KeychainBackupEncryption()
```

- Backup создаётся с `KeychainBackupEncryption` когда `isEncryptionEnabled == true`.

**Вывод:** default mode = device-key подтверждён. `restore_decryptable_rate` < 50% при смене устройства/reinstall — обоснованно.

---

### Current State — UI-честность (device-key warning)

**Файл:** `BackupManagementView.swift:1205–1207`

```swift
Text(mode.restoreRisk)
    .foregroundStyle(mode == .passphrase ? AppColors.textTertiary : AppColors.warning)
```

- Warning-текст для device-key отображается цветом `AppColors.warning` — но только в блоке выбора режима защиты при раскрытом `isProtectionExpanded`.
- `isProtectionExpanded` по умолчанию = `BackupProtectionDisclosureStore.load()` — состояние сохраняется между сессиями.
- **Проблема:** если пользователь не раскрыл секцию «Защита» или уже сохранил настройки, warning недоступен в основном UI.
- Нет явного inline-предупреждения на главном экране backup при активном device-key режиме (только в picker-е при смене режима).

---

### Current State — RestoreView локализация

**Файл:** `millio/UI/Restore/RestoreView.swift` (446 строк)

- Практически все строки идут через `BackupL10n.tr("backup.restore.*", fallback: "...")` — это правильно.
- **Обнаружены два hardcoded EN literal** (строки 358, 369):
  ```swift
  restoreError = .restoreFailed("Backup lookup timed out. iCloud may still be syncing. Try again.")
  ```
  — передаётся напрямую в `.restoreFailed()`, не через L10n.
- Аудит ссылался на `RestoreView.swift:336/342` (старые номера строк из архивной версии файла).
- Текущий файл — **уже частично переработан** и использует `BackupL10n.tr`, но два места остались нелокализованными.
- Нет raw RU literals — анализ 2026-04-27 опирался на более раннюю версию файла.

---

### Current State — Launch-time recovery flow

**Файл:** `millio/Core/Backup/LaunchRecoveryPolicy.swift` (79 строк)

- Политика полностью реализована: `LaunchRecoveryPolicy.evaluate()` возвращает `.presentRestore` или `.skip(reason)`.
- Условия для `presentRestore`:
  - `hasCompletedOnboarding == true`
  - `lifecycle == .ready`
  - `!didLocalStoreExistBeforeLaunch`
  - `localDataCount == 0`
  - `latestBackupInfo != nil`

**Файл:** `millio/millioApp.swift:558`

```swift
private func presentRestoreFlowIfNeeded() async {
    ...
    let latestBackupInfo = await diContainer.backupManager.lastBackupInfo()
    let recoveryDecision = LaunchRecoveryPolicy.evaluate(...)
    guard recoveryDecision.shouldPresentRestore else { return }
    appState.lifecycle = .restoring
}
```

- Функция вызывается при `onAppear` (строка 192).
- **Launch-time recovery уже существует** — это противоречит анализу 2026-04-27, где говорилось «нет launch-time recovery orchestration».
- **Проблема остаётся:** `lastBackupInfo()` не имеет таймаута в самом `presentRestoreFlowIfNeeded`. Если CloudKit медленный — функция зависнет или вернёт `nil`.

---

### Current State — CloudKit timeout

**Файл:** `millio/UI/Restore/RestoreView.swift:353–376`

- `refreshBackupStatusIfNeeded` использует `withTimeout(seconds: 8)` — **уже 8 секунд**, не 3.
- Аудит от 14.03.2026 ссылался на 3 секунды (строки 336/342 старого файла).
- Текущая версия файла уже улучшена до 8 секунд.
- **Оставшаяся проблема:** `presentRestoreFlowIfNeeded()` в `millioApp.swift` не имеет таймаута при вызове `lastBackupInfo()`.

---

### Структура — ключевые файлы

| Файл | Роль | Строк |
|------|------|-------|
| `millio/Core/Security/BackupEncryption.swift` | KeychainBackupEncryption, kSecAttrAccessibleWhenUnlockedThisDeviceOnly | ~148 |
| `millio/Core/Backup/BackupManager.swift` | performBackup, encryptionKey() → KeychainBackupEncryption | 846 |
| `millio/Core/Backup/LaunchRecoveryPolicy.swift` | политика recovery при запуске | 79 |
| `millio/Core/Backup/CloudBackupStore.swift` | CloudKit запросы | 843 |
| `millio/UI/Profile/BackupExperienceModels.swift` | BackupEncryptionMode enum, UI-строки | ~250 |
| `millio/UI/Profile/BackupManagementView.swift` | UI backup, default = .deviceKey | ~1200 |
| `millio/UI/Restore/RestoreView.swift` | launch-time RestoreView, 2 hardcoded EN строки | 446 |
| `millio/millioApp.swift` | presentRestoreFlowIfNeeded | >500 |

---

### Зависимости

- `SettingsManager.shared.isEncryptionEnabled` — контролирует активацию device-key шифрования
- `BackupEncryptionMode` в `BackupExperienceModels.swift` — центральная точка для изменения enum
- `KeychainBackupEncryption` в `BackupEncryption.swift` — реализация device-key
- `PassphraseBackupEncryption` в `BackupManager.swift:168` — уже существует для passphrase
- `BackupL10n.tr(...)` — локализация, уже применяется в большинстве мест RestoreView

---

### Тесты

- Нет тестов на `BackupEncryptionMode` default value в `BackupManagementView`.
- `LaunchRecoveryPolicy` — логика чистая, легко покрывается unit-тестами.
- Нет тестов на поведение при `lastBackupInfo()` timeout в launch flow.

---

## Alternatives

### Проблема 1: Default encryption mode

**Вариант A: Сменить default на `.passphrase`**
- **Плюсы:** максимальная переносимость; `restore_decryptable_rate` → ~99%; пользователь явно задаёт секрет.
- **Минусы:** UX-барьер при первом включении backup (надо задать фразу); passphrase можно забыть.
- **Трудоёмкость:** S — одна строка изменения + UI flow для обязательного ввода пассфразы.

**Вариант B: Добавить третий режим `.unencrypted` как default**
- **Плюсы:** нет барьера входа; portability = 100%.
- **Минусы:** backup в CloudKit без шифрования; риски безопасности; нужно новый кейс в enum и UI.
- **Трудоёмкость:** M.

**Вариант C: Оставить `.deviceKey` как default, добавить обязательный onboarding-choice**
- **Плюсы:** существующие пользователи не ломаются; выбор при первом включении.
- **Минусы:** не решает проблему для уже включённых backup-ов; сложнее UX.
- **Трудоёмкость:** M.

**Recommendation:** Вариант A для новых пользователей + migration notice для существующих device-key backup-ов.

---

### Проблема 2: UI warning для device-key

**Вариант A: Inline warning-баннер на главном экране при активном device-key**
- Показывать предупреждение если `encryptionMode == .deviceKey && appState.isBackupEnabled`.
- **Трудоёмкость:** S.

**Вариант B: Переименование + warning только в picker-е (текущее состояние)**
- Уже есть `restoreRisk` текст с `AppColors.warning` цветом.
- **Трудоёмкость:** XS (только изменить текст через L10n).

**Recommendation:** Вариант A — inline warning + улучшение текста в `restoreRisk`.

---

### Проблема 3: RestoreView hardcoded EN strings

**Решение:** заменить 2 вхождения `.restoreFailed("Backup lookup timed out...")` на `BackupL10n.tr("backup.restore.error.lookup_timeout", fallback: "...")`.
- **Трудоёмкость:** XS — 2 строки кода + 1 ключ в L10n.

---

### Проблема 4: Launch-time recovery timeout

**Решение:** добавить `withTimeout` вокруг `lastBackupInfo()` в `presentRestoreFlowIfNeeded()`.
- **Трудоёмкость:** S — паттерн уже есть в RestoreView.

---

## Recommendation

**Выбраны:** A (passphrase default) + A (inline warning) + XS fix (L10n) + S fix (timeout).

**Почему:**
1. Passphrase default — единственное решение, которое делает backup настоящим backup (переносимым).
2. Inline warning убирает ложное ощущение надёжности для существующих device-key пользователей.
3. L10n fix и timeout fix — минимальная трудоёмкость, критичны для zh-Hans и надёжности recovery flow.

**Что учесть при имплементации:**
- Нужна миграция UX для пользователей с `isEncryptionEnabled == true`: при следующем открытии backup-экрана показать notice «Ваш режим изменён» + предложить задать passphrase.
- `isEncryptionEnabled` в `SettingsManager` — единственная точка хранения режима; нужно решить, хранить ли новый режим через этот флаг или через новый `backupEncryptionMode: BackupEncryptionMode` в UserDefaults/AppStorage.
- Passphrase confirmation flow уже реализован в `BackupManagementView` — переиспользовать.
