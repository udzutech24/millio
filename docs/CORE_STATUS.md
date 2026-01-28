# Статус ядра — Millio

**Дата обновления:** 2026-01-27

## ✅ Реализовано в коде

- **DIContainer** — централизованное создание зависимостей (`Core/DI`)
- **AppSchema + ModelTypeRegistry** — динамическая схема SwiftData и регистрация моделей
- **Backup/Restore** через CloudKit (`Core/Backup`)
- **Backup metadata/versioning** (`BackupMetadata`, `BackupVersion`, `BackupInfo`)
- **Опциональное шифрование backup** (AES-GCM + Keychain)
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

1. **Core знает бизнес-сущности**
   - `DataRepository` использует явные типы (`Card`, `Cashback`, `FinanceGroup` и т.д.) для экспорта/очистки.

2. **SwiftUI в Core**
   - `RootViewResolver` и `AppRouter` находятся в Core и зависят от SwiftUI.
   - `ViewModelProtocol` использует `ObservableObject`.

3. **ModelContext в View слое**
   - Во многих экранах `ModelContext` используется для инициализации ViewModel/репозиториев
     (например, `ProfileView`, `RestoreView`, `FinancesView`).

4. **Restore не запускается автоматически**
   - Экран восстановления открывается вручную из профиля.
   - `checkRestoreNeeded()` есть, но сейчас не используется.

5. **UI для шифрования отсутствует**
   - Флаг есть в `SettingsManager`, но отдельного тоггла нет.

6. **BackupMonitor не подключен к UI**
   - Монитор реализован, но прогресс/статусы в интерфейсе не отображаются.

## 📌 Открытые улучшения (если захотите развивать)

- Вынести явные зависимости Core → Feature модели (унифицировать экспорт/очистку)
- Добавить UI для ручного backup и переключателя шифрования
- Подключить `BackupMonitor` к интерфейсу
- Решить вопрос автоматического restore при старте (или убрать `restoring` из lifecycle)

---

**Итог:** ядро функционально и соответствует основным принципам, но есть несколько сознательных компромиссов и незакрытых UI-частей.
