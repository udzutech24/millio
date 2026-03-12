# Backup/Restore Schema

Документ фиксирует текущий контракт backup/restore в Millio после усиления формата envelope, смены source of truth в CloudKit и пересмотра правил совместимости.

**Версия:** 2.3  
**Дата:** 2026-03-06

---

## 1. Инварианты

- Backup всегда является полным snapshot всех локальных данных SwiftData.
- Restore всегда заменяет локальные данные целиком. Merge-restore не поддерживается.
- Source of truth в CloudKit: immutable snapshot records типа `AppBackup`.
- `backup_index` больше не считается источником истины. Это best-effort cache, который можно потерять или пересобрать.
- `latest_backup` сохраняется только как legacy fallback и совместимость.

---

## 2. CloudKit Storage Model

### 2.0. Окружения schema

- Локальная debug-разработка обычно бьёт в CloudKit Development schema.
- TestFlight и App Store используют CloudKit Production schema.
- Любой новый record type / field для backup (`AppBackup`, `AppBackupIndex`, новые поля snapshot-а) обязан быть задеплоен в Production до релиза.
- Если schema не выкачена, backup в production-сборках падает с серверной ошибкой вида `Cannot create new type AppBackup in production schema` или `CloudKit production schema is missing record type 'AppBackup'`.

### 2.1. Записи

- `AppBackup`:
  - immutable snapshot record
  - содержит `backupData`, `backupDate`, `backupVersion`, `backupSize`, `isPinned`
- `backup_index`:
  - кэш списка snapshot-ов для совместимости/UI
  - не должен ломать backup/restore при повреждении или конфликте записи
- `latest_backup`:
  - legacy fallback record
  - используется только если snapshot records отсутствуют или недоступны

### 2.2. Правила retention

- Автобэкап хранится в одном перезаписываемом record `latest_backup`.
- Автобэкап обновляется не чаще одного раза в 3 дня, когда приложение уходит в фон и backup включён.
- Сохранённые пользователем версии создаются как отдельные snapshot records.
- Закреплённые (`isPinned == true`) snapshot-ы не удаляются автоматически и остаются в истории до явного удаления пользователем.
- Retention считается по snapshot records, а не по `backup_index`.

### 2.3. Требования к отказоустойчивости

- Ошибка записи `backup_index` не должна отменять успешный backup snapshot-а.
- Ошибка пересборки `backup_index` после delete не должна откатывать удаление snapshot-а.
- Повреждённый `backup_index` не должен скрывать валидные snapshot records.
- Частично битые snapshot records должны игнорироваться, если рядом есть валидные.

---

## 3. Envelope Format

### 3.1. Поддерживаемые версии

- `v1`:
  - legacy envelope
  - layout: `UInt32 headerLength` + `headerJSON` + `payload`
  - без magic bytes
  - без checksum
- `v2`:
  - current envelope
  - layout: `magic("MBKP")` + `UInt32 headerLength` + `headerJSON` + `payload`
  - payload checksum обязателен

### 3.2. Header

`BackupEnvelopeHeader` содержит:

- `formatVersion`
- `metadata`
- `compression`
- `encryption`
- `payloadChecksumSHA256Base64` для `v2+`

### 3.3. Payload pipeline

1. `DataRepository.exportAllDataAsync()` сериализует `metadata + models`
2. опционально применяется LZFSE, только если payload становится меньше
3. опционально применяется шифрование:
   - `aesgcm-keychain`
   - `aesgcm-passphrase`
4. payload пакуется в envelope

### 3.4. Валидация

- `looksLikeEnvelope()` распознаёт и `v1`, и `v2`
- `unpack()`:
  - для `v2` проверяет magic bytes и checksum
  - для `v1` поддерживает только legacy parsing
- checksum mismatch трактуется как `backupCorrupted`

---

## 4. Restore Candidate Policy

### 4.1. Выбор кандидатов

`CloudBackupStore.listBackupRecordNamesForRestore()` возвращает:

1. snapshot records, отсортированные по `backupDate` от новых к старым
2. `latest_backup` как legacy fallback

Restore больше не зависит от `backup_index` для выбора кандидатов.

### 4.2. Auto restore (`restoreLatest`)

Auto restore обязан пробовать older snapshot при следующих ошибках:

- corrupted envelope / checksum mismatch
- incompatible schema
- unknown model types
- недоступный keychain key на этом устройстве

Auto restore не должен silently пропускать:

- backup, требующий passphrase, если passphrase не передан
- rollback failure
- pre-restore snapshot failure

### 4.3. Explicit restore (`restoreVersion`)

При явном выборе версии пользователем restore блокируется на первой критической ошибке. Переход на older snapshot не выполняется.

---

## 5. Compatibility Contract

### 5.1. Что определяет совместимость

Совместимость restore определяется `BackupMetadata.schemaVersion`, а не `BackupVersion` приложения.

- `BackupVersion`:
  - informational metadata о сборке/producer version
  - не используется как import gate
- `schemaVersion`:
  - источник истины для restore compatibility

### 5.2. Правило

`schemaVersion` парсится как `major.minor`.

- одинаковый `major` => схема считается совместимой
- другой `major` => `incompatibleSchemaVersion`
- непарсибельный `schemaVersion` => `incompatibleSchemaVersion`

Это значит:

- backup от другой app version допустим, если schema совместима
- breaking changes данных должны сопровождаться bump `schemaVersion.major`

---

## 6. Encryption Modes

### 6.1. `aesgcm-keychain`

- ключ хранится локально в iOS Keychain
- backup может быть нерасшифруем на новом устройстве или после reinstall
- в `restoreLatest` такой snapshot можно пропустить в пользу older compatible candidate
- в `restoreVersion` это блокирующая ошибка

### 6.2. `aesgcm-passphrase`

- ключ derive-ится через PBKDF2(HMAC-SHA256)
- backup переносим между устройствами
- отсутствие passphrase при restore считается блокирующей ошибкой

---

## 7. Rollback Contract

Перед restore текущие локальные данные сохраняются во временный pre-restore snapshot.

- если import нового backup не удался, выполняется rollback
- если rollback не удался, restore завершается критической ошибкой
- restore не считается успешным, пока импорт и post-import cleanup не завершены

---

## 8. Что тестами уже покрыто

- fallback на older snapshot при corrupted envelope
- fallback при checksum mismatch
- fallback при unknown model types
- fallback при keychain-unavailable snapshot в `restoreLatest`
- block при keychain-unavailable в `restoreVersion`
- source of truth на snapshot records при corrupted `backup_index`
- success path при падении cache-update `backup_index`
- delete path при падении resync `backup_index`
- игнор malformed snapshot records
- backward compatibility envelope `v1`
- current envelope `v2` roundtrip + checksum validation

---

## 9. Что остаётся рискованным

- race/conflict между несколькими устройствами при почти одновременной записи snapshot records всё ещё ограничивается поведением CloudKit query/save и не имеет отдельного merge-протокола
- header checksum пока не добавлен; сейчас защищён payload, но не отдельная целостность header сверх JSON decode
- часть UI/integration suite вне backup-подсистемы периодически виснет в `xcodebuild`, что мешает полной сквозной верификации

---

## 10. UI Contract (compact security flow)

- Экран управления backup должен оставаться компактным: целевой сценарий `toggle -> protection mode -> create/restore`.
- На основном экране используются единые control-паттерны для действий создания и восстановления (без смешения слайдера и обычных кнопок).
- Подробные и второстепенные данные (список сохранённых версий) должны быть сворачиваемыми и не раздувать первый экран по высоте.
- Тексты в status/protection/action блоках должны быть короткими и операционными (что сделать сейчас), а не длинными объяснениями.
