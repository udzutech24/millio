# Статус ядра — Millio

**Дата обновления:** 2026-01-30

## ✅ Реализовано в коде

- **DIContainer** — централизованное создание зависимостей (`Core/DI`)
- **AppSchema + ModelTypeRegistry** — динамическая схема SwiftData и регистрация моделей
- **Backup/Restore** через CloudKit (`Core/Backup`)
- **Backup metadata/versioning** (`BackupMetadata`, `BackupVersion`, `BackupInfo`)
- **Опциональное шифрование backup**:
  - `aesgcm-keychain` (device-only, ключ в Keychain)
  - `aesgcm-passphrase` (PBKDF2 + парольная фраза, переносимо)
- **Сжатие backup** (Compression LZFSE)
- **Retry механизм** для сетевых операций (`RetryPolicy`, `withRetry`)
- **ErrorRecoveryManager** со стратегиями восстановления
- **EventBus** для слабой связанности
- **FeatureRegistry** для регистрации фич
- **AppState + AppLifecycleUseCase**
- **AppRouter + RootViewResolver** для навигации
- **Мультиязычность** (String Catalog + LanguageManager)
- **Subscription/Notification менеджеры** на уровне Core

## ✅ Соответствие CORE_RULES.md (в целом)

- **Offline-First** — данные локальные, сеть не обязательна
- **SwiftData = source of truth** — все CRUD через SwiftData
- **CloudKit только для backup/restore** — используется только в `Core/Backup`
- **Snapshot backup** — без merge
- **Fail-safe поведение** — ошибки логируются, приложение продолжает работу

## ⚠️ Компромиссы и отступления

1. **SwiftUI в Core**
   - `RootViewResolver` и `AppRouter` находятся в Core и зависят от SwiftUI.
   - `ViewModelProtocol` использует `ObservableObject`.

2. **ModelContext в View слое**
   - Во многих экранах `ModelContext` используется для инициализации ViewModel/репозиториев
     (например, `ProfileView`, `RestoreView`, `FinancesView`).

3. **Restore не запускается автоматически**
   - Экран восстановления открывается вручную из профиля.
   - `checkRestoreNeeded()` есть, но сейчас не используется.

4. **UI для шифрования не завершен**
   - Нет UI-тоггла режима шифрования (keychain/passphrase).
   - В `RestoreView` есть ввод парольной фразы для passphrase-backup.

5. **BackupMonitor не подключен к UI**
   - Монитор реализован, но прогресс/статусы в интерфейсе не отображаются.

## 📌 Открытые улучшения (если захотите развивать)

- Добавить UI для ручного backup и переключателя режима шифрования
- Подключить `BackupMonitor` к интерфейсу
- Решить вопрос автоматического restore при старте (или убрать `restoring` из lifecycle)

---

**Итог:** ядро функционально и соответствует основным принципам, но есть несколько сознательных компромиссов и незакрытых UI-частей.
