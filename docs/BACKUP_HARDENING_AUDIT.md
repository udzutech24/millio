# Backup Hardening Audit

Дата: 2026-03-14

## Цель

Разобрать, почему после установки новой версии или повторной установки на том же устройстве пользователь может увидеть пустые локальные данные и экран с сообщением, что backup не найден, хотя старые копии в iCloud фактически существуют.

## Как backup работает сейчас

### Локальное хранилище

- Данные приложения живут локально в SwiftData.
- Store теперь выбирается по `DataScope`:
  - guest store: `millio_guest.store`
  - user store: `millio_user_<hash(userID)>.store`
- Переключение scope происходит после восстановления auth session.

Код:
- [/Users/alekseya/millio/millio/millioApp.swift#L31](file:///Users/alekseya/millio/millio/millioApp.swift#L31)
- [/Users/alekseya/millio/millio/millioApp.swift#L82](file:///Users/alekseya/millio/millio/millioApp.swift#L82)
- [/Users/alekseya/millio/millio/millioApp.swift#L277](file:///Users/alekseya/millio/millio/millioApp.swift#L277)

### Облачный backup

- Backup не хранится в iCloud Drive.
- Backup хранится в CloudKit Private DB.
- Есть два класса записей:
  - pinned snapshots: отдельные immutable `AppBackup`
  - auto-backup: один legacy record `latest_backup`
- Для UI поддерживается `backup_index`, но он задуман как best-effort cache.

Код:
- [/Users/alekseya/millio/millio/Core/Backup/CloudBackupStore.swift#L143](file:///Users/alekseya/millio/millio/Core/Backup/CloudBackupStore.swift#L143)
- [/Users/alekseya/millio/millio/Core/Backup/CloudBackupStore.swift#L260](file:///Users/alekseya/millio/millio/Core/Backup/CloudBackupStore.swift#L260)
- [/Users/alekseya/millio/millio/Core/Backup/CloudBackupStore.swift#L321](file:///Users/alekseya/millio/millio/Core/Backup/CloudBackupStore.swift#L321)

### Шифрование

- Если `SettingsManager.isEncryptionEnabled == true`, backup по умолчанию шифруется device key.
- Device key хранится в Keychain как `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Такой ключ не переживает перенос между устройствами и может не пережить reinstall/restore сценарии.
- Passphrase mode есть, но не является безопасным default.

Код:
- [/Users/alekseya/millio/millio/Core/Backup/BackupManager.swift#L757](file:///Users/alekseya/millio/millio/Core/Backup/BackupManager.swift#L757)
- [/Users/alekseya/millio/millio/Core/Security/BackupEncryption.swift#L19](file:///Users/alekseya/millio/millio/Core/Security/BackupEncryption.swift#L19)
- [/Users/alekseya/millio/millio/Core/Security/BackupEncryption.swift#L85](file:///Users/alekseya/millio/millio/Core/Security/BackupEncryption.swift#L85)
- [/Users/alekseya/millio/docs/BACKUP_RESTORE_SCHEMA.md#L160](file:///Users/alekseya/millio/docs/BACKUP_RESTORE_SCHEMA.md#L160)

### Restore

- Авто-restore при старте приложения не используется.
- Restore есть только как явное пользовательское действие.
- Если локальный store оказался пустым после смены scope, приложение не пытается автоматически восстановиться из CloudKit.

Код:
- [/Users/alekseya/millio/millio/Core/UseCases/AppLifecycleUseCase.swift#L53](file:///Users/alekseya/millio/millio/Core/UseCases/AppLifecycleUseCase.swift#L53)
- [/Users/alekseya/millio/millio/UI/Restore/RestoreView.swift#L332](file:///Users/alekseya/millio/millio/UI/Restore/RestoreView.swift#L332)

## Главные слабые точки

### 1. Device-key backup не подходит как основной режим для disaster recovery

Это главный архитектурный просчет.

- Ключ шифрования создается локально и хранится как `ThisDeviceOnly`.
- После reinstall или на другом устройстве backup может быть физически в CloudKit, но расшифровать его уже нельзя.
- Это прямо противоречит пользовательскому ожиданию от слова "backup".

Доказательство:
- [/Users/alekseya/millio/millio/Core/Security/BackupEncryption.swift#L85](file:///Users/alekseya/millio/millio/Core/Security/BackupEncryption.swift#L85)
- [/Users/alekseya/millio/docs/BACKUP_RESTORE_SCHEMA.md#L162](file:///Users/alekseya/millio/docs/BACKUP_RESTORE_SCHEMA.md#L162)

Вердикт:
- Для восстановления после reinstall device-key нельзя считать надежным backup.
- Это надо либо убрать из default path, либо жестко маркировать как "локально-восстановимый, не переносимый".

### 2. Смена локального store по `DataScope` может визуально выглядеть как потеря данных

Сейчас приложение стартует в guest scope, а потом после auth session переключается в user scope.

- Если раньше данные лежали в другом store, пользователь видит пустую базу.
- Миграция предусмотрена только из legacy default store в новый user-scoped store.
- Нет миграции:
  - guest -> user
  - user(old hash/source) -> user(new source)
  - reinstall/new install -> auto restore из CloudKit

Доказательство:
- [/Users/alekseya/millio/millio/millioApp.swift#L82](file:///Users/alekseya/millio/millio/millioApp.swift#L82)
- [/Users/alekseya/millio/millio/millioApp.swift#L116](file:///Users/alekseya/millio/millio/millioApp.swift#L116)
- [/Users/alekseya/millio/millio/millioApp.swift#L277](file:///Users/alekseya/millio/millio/millioApp.swift#L277)
- [/Users/alekseya/millio/millio/millioApp.swift#L387](file:///Users/alekseya/millio/millio/millioApp.swift#L387)

Вердикт:
- Даже без поломки CloudKit пользователь может получить "пустое приложение" просто из-за смены store scope.

### 3. Авто-backup хранится в одном слоте `latest_backup`

Это слишком хрупко.

- Один битый или перезаписанный `latest_backup` убивает весь авто-backup history.
- Retention для авто-бэкапа отсутствует.
- Если пользователь не создавал pinned versions, восстановление зависит от одного record.

Доказательство:
- [/Users/alekseya/millio/millio/Core/Backup/CloudBackupStore.swift#L321](file:///Users/alekseya/millio/millio/Core/Backup/CloudBackupStore.swift#L321)
- [/Users/alekseya/millio/docs/BACKUP_RESTORE_SCHEMA.md#L41](file:///Users/alekseya/millio/docs/BACKUP_RESTORE_SCHEMA.md#L41)

Вердикт:
- Один слот для autobackup недопустим для "очень качественного" восстановления.

### 4. UI легко может показать "нет backup", хотя проблема на самом деле в таймауте/неуспевшем query

В `RestoreView` поиск backup ограничен 3 секундами.

- Если CloudKit query медленный, UI просто получает `nil`.
- Это визуально выглядит как "backup не найден".
- После создания новой версии пользователь мог увидеть старые версии просто потому, что query наконец-то отработал или изменился index/cache state.

Доказательство:
- [/Users/alekseya/millio/millio/UI/Restore/RestoreView.swift#L336](file:///Users/alekseya/millio/millio/UI/Restore/RestoreView.swift#L336)
- [/Users/alekseya/millio/millio/UI/Restore/RestoreView.swift#L342](file:///Users/alekseya/millio/millio/UI/Restore/RestoreView.swift#L342)

Вердикт:
- Таймаут в 3 секунды для disaster recovery UX слишком агрессивный.
- Пользователь получает ложный отрицательный результат.

### 5. Экран backup-management кэширует статус по `lastBackupDate`, что может скрывать реальное состояние

Если backup включен, но уже есть `isICloudAvailable == true` и `lastBackupDate != nil`, повторный refresh по умолчанию не идет.

Доказательство:
- [/Users/alekseya/millio/millio/UI/Profile/BackupManagementView.swift#L688](file:///Users/alekseya/millio/millio/UI/Profile/BackupManagementView.swift#L688)

Вердикт:
- Для обычного UI это ок, для recovery UX это слабое место.
- Пользователь должен видеть реальный live-state, а не кеш.

### 6. Passphrase хранится локально в Keychain, но UX не разделяет "portable secret" и "local convenience copy"

Сейчас passphrase mode лучше device-key mode, но:

- passphrase автоматически сохраняется локально;
- нет recovery confirmation flow "я реально сохранил фразу вне приложения";
- нет обязательной проверки восстановления после создания protected backup.

Доказательство:
- [/Users/alekseya/millio/millio/UI/Profile/BackupManagementView.swift#L839](file:///Users/alekseya/millio/millio/UI/Profile/BackupManagementView.swift#L839)
- [/Users/alekseya/millio/millio/UI/Profile/BackupManagementView.swift#L952](file:///Users/alekseya/millio/millio/UI/Profile/BackupManagementView.swift#L952)

Вердикт:
- С точки зрения UX это все еще слишком оптимистично и провоцирует ложное ощущение надежности.

### 7. Нет сквозного "backup health" статуса

Система не считает и не показывает:

- есть ли вообще хоть один переносимый backup;
- есть ли хотя бы один свежий backup;
- какая доля backup-ов реально decryptable на этом устройстве;
- проходил ли restore smoke-test хотя бы раз.

Вердикт:
- Без health model пользователь не понимает, защищен он или нет.

### 8. Нет launch-time recovery orchestration

Сейчас есть только pieces:

- детекция наличия backup;
- ручной restore;
- событие restoreCompleted;
- rollback.

Но нет orchestration уровня приложения:

- "локальных данных нет, зато есть cloud backup" -> предложить восстановление сразу;
- "локальный store сменился и пуст" -> попытаться сопоставить прошлый store;
- "нашли только device-key snapshots, которые не читаются" -> честно показать причину.

Вердикт:
- Система умеет восстанавливать технически, но не умеет вести пользователя через recovery сценарий.

## Наиболее вероятное объяснение описанного бага

Наиболее правдоподобная цепочка выглядит так:

1. После новой версии приложение открыло другой локальный SwiftData store из-за `DataScope`.
2. Пользователь увидел пустые локальные данные.
3. Авто-restore на старте не сработал, потому что его нет.
4. Экран restore/backup-management сначала не показал старые backup-ы из-за CloudKit query delay, fallback path или UI timeout.
5. После создания новой backup-версии CloudKit записи/индекс/UI перечитались, и старые snapshots стали видны.
6. Если старые backup-ы были device-key encrypted, часть из них могла быть физически в CloudKit, но практически непригодна для восстановления после reinstall.

Это не один баг. Это комбинация:

- хрупкий recovery UX
- спорная стратегия шифрования по умолчанию
- смена локального store без recovery orchestration
- слишком слабая наблюдаемость состояния backup

## План сделать backup действительно надежным

### Фаза 0. Немедленные меры

1. Перестать считать device-key режим полноценным backup по умолчанию.
2. В UI переименовать его в "Only this device".
3. Новым пользователям по умолчанию предлагать только:
   - passphrase backup
   - или unencrypted backup, если это допустимо по product/security policy
4. Добавить явное предупреждение:
   - device-key mode не гарантирует restore после reinstall и на другом устройстве.

### Фаза 1. Исправить модель хранения

1. Убрать single-slot auto-backup.
2. Хранить ring buffer авто-снимков, например:
   - 7 ежедневных
   - 4 weekly
   - pinned без автоудаления
3. Хранить metadata отдельно и query-friendly:
   - `backupDate`
   - `schemaVersion`
   - `producerVersion`
   - `protectionMode`
   - `isRestorableOnCurrentDevice`
   - `originDeviceID`
4. `backup_index` оставить только как cache или вообще удалить из critical path.

### Фаза 2. Добавить recovery orchestrator

1. На старте приложения вычислять состояние:
   - локальные данные есть/нет
   - cloud backup есть/нет
   - какой backup decryptable
   - есть ли portable backup
2. Если локальный store пуст, а backup есть:
   - автоматически открывать recovery flow
   - не прятать пользователя в пустое приложение
3. Если найден только device-key backup:
   - показывать конкретную причину, а не "backup not found"
4. Если сменился `DataScope`:
   - пробовать import из legacy default store
   - пробовать import из guest store
   - логировать результат миграции

### Фаза 3. Усилить UX и доверие

1. Ввести backup health score:
   - `protected`
   - `portable`
   - `recent`
   - `verified`
2. После первого создания backup запускать verify flow:
   - распаковать
   - валидировать metadata
   - dry-run import в temp container
3. Показывать пользователю:
   - последняя успешная upload date
   - последняя verified restore date
   - режим защиты
   - переносимость

### Фаза 4. Усилить наблюдаемость

1. Добавить structured telemetry:
   - backup upload success/failure
   - query latency
   - restore candidate count
   - decryptable candidate count
   - empty-local-store-on-launch
   - scope-switch migration result
2. В Crashlytics и логах различать:
   - no backup found
   - backup exists but query timed out
   - backup exists but not decryptable
   - backup exists but schema incompatible

### Фаза 5. Тесты, без которых выпускать нельзя

Добавить unit/integration tests на:

1. reinstall-like scenario:
   - локальный keychain key потерян
   - CloudKit backup есть
   - UI честно показывает "backup найден, но не может быть расшифрован"
2. scope migration:
   - guest -> user
   - legacy default -> scoped user
   - пустой target store + непустой guest store
3. cold start recovery:
   - local store empty + cloud snapshot exists
4. CloudKit slow query:
   - UI не показывает ложное "backup not found"
5. auto-backup retention:
   - несколько автобэкапов, сортировка, cleanup
6. portable backup verification:
   - export/import roundtrip в temp container

## Рекомендованный целевой контракт

Если сформулировать жестко, "качественный backup" для Millio должен гарантировать:

1. Backup не теряется визуально из-за UI timeout или cache.
2. После reinstall пользователь либо восстанавливается, либо получает точную причину, почему нет.
3. В системе всегда есть больше одной автоматической recovery point.
4. Пользователь всегда понимает, переносим его backup или нет.
5. Перед релизом есть тесты на reinstall, scope migration и restore verification.

## Что делать первым

Если идти по приоритету риска, то порядок такой:

1. сменить default protection mode с device-key на portable mode
2. добавить launch-time recovery flow
3. заменить single-slot `latest_backup` на retention из нескольких авто-снимков
4. добавить backup verification и health status
5. закрыть тестами reinstall/scope migration/slow CloudKit

## Жесткий вывод

Сейчас backup в проекте нельзя считать пуленепробиваемым.

Причина не в одном дефекте, а в архитектурной комбинации:

- backup и restore разорваны с lifecycle приложения
- default encryption mode не соответствует recovery expectations
- локальный store routing может имитировать потерю данных
- auto-backup слишком хрупкий
- UI слишком легко говорит "копии нет", когда истина сложнее

Если цель действительно "очень качественно", то надо перестать думать о backup как о кнопке в профиле и начать думать о нем как о recovery subsystem.
