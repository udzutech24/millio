## Находки (баги/риски)
- **DIContainer “застывает” в MockBackupManager**: если backup выключен на старте, в DI сохраняется `MockBackupManager` и после включения в UI фоновые backup не начнут работать, т.к. `triggerBackgroundBackup()` дергает уже созданный `diContainer.backupManager`. См. [DIContainer.swift](file:///Users/sidorkin/xcode/millio/millio/Core/DI/DIContainer.swift#L30-L49), [millioApp.swift](file:///Users/sidorkin/xcode/millio/millio/millioApp.swift#L128-L141).
- **Неатомарная замена записи в CloudKit**: `uploadBackup` делает delete, затем save — при падении между ними можно потерять последний backup. См. [CloudBackupStore.uploadBackup](file:///Users/sidorkin/xcode/millio/millio/Core/Backup/CloudBackupStore.swift#L39-L68).
- **Passphrase-режим может создать plaintext backup**: в UI `.passphrase` при пустом поле передается `nil`, и backup создаётся без шифрования. См. [BackupManagementView.createBackupNow](file:///Users/sidorkin/xcode/millio/millio/UI/Profile/BackupManagementView.swift#L319-L326), [BackupManager.backupNow](file:///Users/sidorkin/xcode/millio/millio/Core/Backup/BackupManager.swift#L55-L105).
- **Выбор шифрования кэшируется в init BackupManager**: `SettingsManager.shared.isEncryptionEnabled` читается в `init(dataRepository:)`; переключения в UI могут не влиять на уже созданный менеджер/DI. См. [BackupManager.swift](file:///Users/sidorkin/xcode/millio/millio/Core/Backup/BackupManager.swift#L38-L45).
- **Envelope/legacy ветка в restore может маскировать порчу**: если `unpack` не удался, код уходит в legacy-путь, который “угадывает” формат; это ухудшает диагностику corruption. См. [BackupManager.restoreLatest](file:///Users/sidorkin/xcode/millio/millio/Core/Backup/BackupManager.swift#L137-L179), [BackupEnvelope.unpack](file:///Users/sidorkin/xcode/millio/millio/Core/Backup/BackupEnvelope.swift#L44-L57).
- **Compression/encryption метаданные не валидируются**: при `header.compression != nil` всегда пытаемся LZFSE, игнорируя `algorithm`, `originalSize` не используется. См. [BackupManager.swift](file:///Users/sidorkin/xcode/millio/millio/Core/Backup/BackupManager.swift#L164-L166), [BackupEnvelope.swift](file:///Users/sidorkin/xcode/millio/millio/Core/Backup/BackupEnvelope.swift#L3-L26).
- **Retry ретраит “неповторяемые” ошибки**: `withRetry` сейчас повторяет всё, включая `incompatibleSchemaVersion` или “backup не найден”. См. [RetryPolicy.swift](file:///Users/sidorkin/xcode/millio/millio/Core/Network/RetryPolicy.swift#L22-L42).
- **Restore UX**: до недавнего фиксика “Продолжить” не делал pop. Сейчас уже добавлен `dismiss()`. Дополнительно: restore в принципе можно разрешить даже при `isBackupEnabled == false` (разовая операция восстановления не обязана включать фоновые backup). См. [RestoreView.swift](file:///Users/sidorkin/xcode/millio/millio/UI/Restore/RestoreView.swift#L53-L64).
- **ActionButton использует UIKit**: сейчас `UIImage(systemName:)` требует `import UIKit`. Это ок для iOS, но можно убрать UIKit-зависимость, используя `Image(systemName:)` без проверки (или отдельный параметр `iconKind`). См. [ActionButton.swift](file:///Users/sidorkin/xcode/millio/millio/UI/Shared/ActionButton.swift#L8-L22).

## Предлагаемые улучшения (приоритет)
### P0 (желательно сразу)
1) **Сделать backupManager в DI “динамическим”**
   - Вариант A: в DIContainer хранить `realBackupManager` + `mockBackupManager`, а наружу отдавать computed `var backupManager: BackupManagerProtocol { appState.isBackupEnabled ? real : mock }`.
   - Вариант B: хранить фабрику/провайдер, чтобы каждый вызов получал актуальную реализацию.
2) **Сделать CloudKit upload атомарным**
   - Вместо delete+create: fetch record (если есть) → update asset/metadata → save; либо save поверх recordID.
3) **Зафиксировать passphrase UX/безопасность**
   - В режиме passphrase: запретить “Создать backup”, пока фраза пустая; показать явное предупреждение “без неё восстановление невозможно”.

### P1 (надёжность/качество ошибок)
4) **Ужесточить отличение corrupted envelope от legacy**
   - Если `headerLength` невалиден/JSON не декодится — возвращать `backupCorrupted` с понятным сообщением, а legacy-путь включать только при явном “legacy magic” (например, по сигнатуре/версии, если добавим).
5) **Валидация compression/encryption метаданных**
   - Проверять `compression.algorithm == "lzfse"`; `originalSize` использовать как sanity-check.
6) **Retry только для transient ошибок**
   - Добавить `shouldRetry(error)` и исключить ошибки схемы/отсутствия backup.

### P2 (полировка)
7) **Restore UX**
   - Разрешить restore даже если backup выключен (не завязывать на тумблер), либо предложить кнопку “Включить backup и продолжить”.
8) **ActionButton без UIKit (по желанию)**
   - Упростить API: либо отдельный enum для иконки (asset vs SF Symbol), либо всегда использовать `Image(systemName:)` для SF-строк по договорённости.

## План работ (что именно сделаю после подтверждения)
1) Переработаю DIContainer так, чтобы включение backup в UI сразу влияло на фоновые backup (без перезапуска приложения).
2) Переделаю `CloudBackupStore.uploadBackup` на update-запись без delete-window.
3) Добавлю в `BackupManagementView` валидацию passphrase и блокировку кнопки при пустом значении.
4) Усилю обработку envelope/legacy и валидацию compression метаданных в `BackupManager`.
5) Добавлю фильтрацию для `withRetry` в backup/restore путях.
6) Прогоню `xcodebuild test` и добавлю точечные unit-тесты на новые ветки (DI behavior, corrupted envelope, retry policy).

Если ок, подтверждай — выйду из plan mode и начну правки.