# Swift Project Configuration

## Язык общения
**ВАЖНО: всегда отвечай на русском языке.**
Комментарии в коде — на русском. Объяснения, документация и обсуждение — только на русском.

## Принципы разработки

### KISS (Keep It Simple, Stupid)
- Простота превыше всего
- Избегай избыточной абстракции
- Не создавай сложности «на будущее»
- Один метод/класс = одна ответственность
- Если можно решить просто — решай просто
- Рефакторинг только при необходимости

### SOLID принципы

**S — Single Responsibility Principle**
```swift
// ✅ ViewModel отвечает только за логику списка пользователей
final class UserListViewModel: ObservableObject {
    @Published private(set) var users: [User] = []
    private let service: UserServiceProtocol

    func loadUsers() async { }
}

// ✅ Service отвечает только за работу с API
final class UserService: UserServiceProtocol {
    func fetchUsers() async throws -> [User] { }
}
```

**O — Open/Closed Principle**
```swift
// ✅ Расширяемость через протоколы
protocol DataSource {
    func fetch() async throws -> [Item]
}

class APIDataSource: DataSource { }
class CacheDataSource: DataSource { }
```

**L — Liskov Substitution Principle**
```swift
// ✅ Mock может заменить реальный сервис
let viewModel = UserListViewModel(service: MockUserService())
```

**I — Interface Segregation Principle**
```swift
// ✅ Разделенные протоколы
protocol UserFetcher {
    func fetchUsers() async throws -> [User]
}

protocol UserDeleter {
    func delete(userId: String) async throws
}

// ViewModel использует только нужные протоколы
final class UserListViewModel: ObservableObject {
    private let fetcher: UserFetcher
}
```

**D — Dependency Inversion Principle**
```swift
// ✅ Зависимость от абстракции
final class ViewModel: ObservableObject {
    private let service: ServiceProtocol
}
```

---

## Проектные правила (кратко)

- **Offline-first:** SwiftData — единственный источник истины
- **CloudKit только для backup/restore**
- **Snapshot-restore:** без merge, восстановление полностью заменяет локальные данные
- **Навигация:** глобально через `AppState`/`AppRouter`, локальные переходы допустимы `NavigationLink`
- **Concurrency:** `async/await`, без GCD
- **Dark Mode only**
- **Локализация:** все строки в `.xcstrings`

Полный список правил: `docs/CORE_RULES.md`.

---

## Backup/Restore — фактическое поведение

- Backup запускается **руками** в профиле.
- Backup хранится в **CloudKit Private DB** (`AppBackup` / `latest_backup`).
- Restore запускается **вручную** из профиля (экран `RestoreView`).
- Авто-restore при старте **не используется** (есть задел в `AppLifecycleUseCase`).
- В профиле есть экран управления backup: включение, статус, ручной backup/restore, выбор режима шифрования.
- Шифрование backup поддерживает режимы **device-key** (Keychain) и **passphrase** (переносимый backup).
- В Release ошибки backup/restore отправляются как non-fatal в Crashlytics через `CrashReporting.record(error:)`.

Подробнее: `docs/BACKUP_RESTORE_SCHEMA.md`.

---

## Документация

- `docs/CORE_RULES.md` — архитектурные принципы
- `docs/CORE_STATUS.md` — текущее состояние и компромиссы
- `docs/BACKUP_RESTORE_SCHEMA.md` — backup/restore
- `docs/FINANCE_DATA_STORAGE.md` — хранение данных по финансам
