# Предложения по улучшению архитектуры и кодовой базы

Анализ на основе CORE_RULES.md, IMPROVEMENTS.md и текущей реализации.

## Критические улучшения (высокий приоритет)

### 1. Использование DIContainer в millioApp

**Проблема:** `DIContainer` создан, но не используется. Зависимости создаются напрямую в `millioApp.swift`.

**Текущее состояние:**
```swift
// millioApp.swift - дублирование логики создания зависимостей
private func initializeApp() async {
    let dataRepository = DataRepository(...)
    let manager: BackupManagerProtocol? = ...
    let useCase = AppLifecycleUseCase(...)
}
```

**Решение:**
```swift
@main
struct millioApp: App {
    @State private var appState = AppState()
    @State private var diContainer: DIContainer?
    
    var sharedModelContainer: ModelContainer = { ... }()
    
    var body: some Scene {
        WindowGroup {
            RootViewResolver(appState: appState)
                .environment(appState)
                .environment(\.diContainer, diContainer)
                .task {
                    await initializeApp()
                }
        }
    }
    
    private func initializeApp() async {
        let container = DIContainer.create(
            appState: appState,
            modelContainer: sharedModelContainer
        )
        self.diContainer = container
        
        let useCase = AppLifecycleUseCase(
            appState: appState,
            backupManager: container.backupManager
        )
        await useCase.initialize()
    }
}
```

**Преимущества:**
- Единая точка создания зависимостей
- Легче тестировать
- Соответствует принципу DI

---

### 2. Вынос схемы SwiftData из millioApp

**Проблема:** Схема определена в `millioApp`, что нарушает принцип "ядро не знает бизнес-сущности". При добавлении новых моделей нужно менять `millioApp`.

**Текущее состояние:**
```swift
// millioApp.swift
var sharedModelContainer: ModelContainer = {
    let schema = Schema([Item.self]) // Жестко закодировано
    ...
}()
```

**Решение:**
```swift
// Core/Schema/AppSchema.swift
struct AppSchema {
    static func create() -> Schema {
        var modelTypes: [any PersistentModel.Type] = []
        
        // Базовые типы ядра
        modelTypes.append(Item.self)
        
        // Типы из ModelTypeRegistry
        let registeredTypes = ModelTypeRegistry.shared.getRegisteredTypes()
        for (_, type) in registeredTypes {
            if let persistentType = type as? any PersistentModel.Type {
                modelTypes.append(persistentType)
            }
        }
        
        return Schema(modelTypes)
    }
}

// millioApp.swift
var sharedModelContainer: ModelContainer = {
    let schema = AppSchema.create()
    ...
}()
```

**Преимущества:**
- Ядро не знает конкретные типы
- Фичи регистрируют свои модели через ModelTypeRegistry
- Не нужно менять millioApp при добавлении фич

---

### 3. Устранение fatalError в millioApp

**Проблема:** `fatalError` нарушает принцип fail-safe. Приложение крашится вместо graceful degradation.

**Текущее состояние:**
```swift
do {
    return try ModelContainer(for: schema, configurations: [modelConfiguration])
} catch {
    fatalError("Could not create ModelContainer: \(error)")
}
```

**Решение:**
```swift
var sharedModelContainer: ModelContainer? = {
    let schema = AppSchema.create()
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    
    do {
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
        AppLogger.log(.error, category: "App", "Failed to create ModelContainer: \(error.localizedDescription)")
        // Можно создать in-memory контейнер как fallback
        do {
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [fallbackConfig])
        } catch {
            return nil
        }
    }
}()

var body: some Scene {
    WindowGroup {
        if let container = sharedModelContainer {
            RootViewResolver(appState: appState)
                .environment(\.modelContainer, container)
        } else {
            ErrorView(
                error: .unknown(NSError(domain: "App", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось инициализировать хранилище данных"])),
                appState: appState,
                router: AppRouter()
            )
        }
    }
}
```

**Преимущества:**
- Fail-safe поведение
- Graceful degradation
- Логирование ошибок

---

### 4. Использование ModelTypeRegistry в DataRepository

**Проблема:** `DataRepository` жестко привязан к `Item`, хотя `ModelTypeRegistry` уже создан.

**Текущее состояние:**
```swift
// DataRepository.swift
let itemDescriptor = FetchDescriptor<Item>()
let items = try modelContext.fetch(itemDescriptor)
// TODO: Использовать ModelTypeRegistry
```

**Решение:**
```swift
func exportAllData() throws -> Data {
    var modelsData: [[String: Any]] = []
    let registeredTypes = ModelTypeRegistry.shared.getExportableTypes()
    
    for (typeName, type) in registeredTypes {
        // Используем рефлексию для получения всех экземпляров типа
        // Это требует более сложной реализации с использованием ModelContainer.schema
        if let fetchableType = type as? any Fetchable.Type {
            let descriptor = fetchableType.createFetchDescriptor()
            let instances = try modelContext.fetch(descriptor)
            
            for instance in instances {
                if let exportable = instance as? Exportable {
                    let data = try exportable.export()
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var itemDict = json
                        itemDict["_type"] = typeName
                        modelsData.append(itemDict)
                    }
                }
            }
        }
    }
    
    // ... остальная логика
}
```

**Альтернативное решение (проще):**
```swift
// Протокол для регистрации импортеров
protocol ModelImporter {
    static func importType() -> String
    static func import(from data: [String: Any], context: ModelContext) throws
}

// ModelTypeRegistry расширяется
protocol ModelTypeRegistryProtocol {
    func register<T: Persistable>(_ type: T.Type, typeName: String)
    func registerImporter<T: ModelImporter>(_ importer: T.Type)
    func getImporter(for typeName: String) -> ModelImporter.Type?
}

// DataRepository использует импортеры
func importAllData(_ data: Data) throws {
    // ...
    for modelData in modelsData {
        guard let type = modelData["_type"] as? String,
              let importer = ModelTypeRegistry.shared.getImporter(for: type) else {
            continue
        }
        try importer.import(from: modelData, context: modelContext)
    }
}
```

---

## Важные улучшения (средний приоритет)

### 5. Введение ViewModel слоя

**Проблема:** Views напрямую обращаются к `AppState` и `AppRouter`, что нарушает MVVM.

**Текущее состояние:**
```swift
struct MainAppView: View {
    @Bindable var router: AppRouter
    // Прямой доступ к router.push()
}
```

**Решение:**
```swift
// Core/ViewModels/BaseViewModel.swift
@MainActor
protocol ViewModelProtocol: ObservableObject {
    associatedtype State
    associatedtype Action
    
    var state: State { get }
    func handle(_ action: Action)
}

// UI/Main/MainAppViewModel.swift
@MainActor
final class MainAppViewModel: ViewModelProtocol {
    @Published var state = MainAppState()
    
    private let router: AppRouter
    
    init(router: AppRouter) {
        self.router = router
    }
    
    enum Action {
        case navigateToService(AppRoute)
        case navigateToProfile
        case navigateToSubscription
    }
    
    func handle(_ action: Action) {
        switch action {
        case .navigateToService(let route):
            router.push(route)
        case .navigateToProfile:
            router.push(.profile)
        case .navigateToSubscription:
            router.push(.subscription)
        }
    }
}

// UI/Main/MainAppView.swift
struct MainAppView: View {
    @StateObject private var viewModel: MainAppViewModel
    
    init(router: AppRouter) {
        _viewModel = StateObject(wrappedValue: MainAppViewModel(router: router))
    }
    
    var body: some View {
        // Используем viewModel.handle(.navigateToService(.finances))
    }
}
```

**Преимущества:**
- Чистый MVVM
- Тестируемость ViewModels
- Разделение ответственности

---

### 6. Структурированная обработка ошибок с Recovery

**Проблема:** Ошибки обрабатываются, но нет стратегий восстановления.

**Решение:**
```swift
// Core/Error/ErrorRecovery.swift
protocol ErrorRecoveryStrategy {
    func canRecover(from error: AppError) -> Bool
    func recover(from error: AppError) async throws
}

enum ErrorRecoveryAction {
    case retry
    case fallback
    case ignore
    case showError
}

struct ErrorRecoveryManager {
    private let strategies: [ErrorRecoveryStrategy]
    
    func handle(_ error: AppError) async -> ErrorRecoveryAction {
        for strategy in strategies {
            if strategy.canRecover(from: error) {
                do {
                    try await strategy.recover(from: error)
                    return .retry
                } catch {
                    continue
                }
            }
        }
        return .showError
    }
}

// Пример стратегии для сетевых ошибок
struct NetworkErrorRecoveryStrategy: ErrorRecoveryStrategy {
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0
    
    func canRecover(from error: AppError) -> Bool {
        error == .networkUnavailable || error == .iCloudUnavailable
    }
    
    func recover(from error: AppError) async throws {
        for attempt in 1...maxRetries {
            try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            // Проверка доступности сети
            if await checkNetworkAvailability() {
                return
            }
        }
        throw error
    }
}
```

---

### 7. Расширенное логирование с контекстом

**Проблема:** Логирование простое, нет структурированных логов и метрик.

**Решение:**
```swift
// Core/Logging/StructuredLogger.swift
struct LogContext {
    let category: String
    let function: String
    let file: String
    let line: Int
    let metadata: [String: Any]?
}

struct StructuredLogger {
    static func log(
        _ level: LogLevel,
        message: String,
        context: LogContext,
        error: Error? = nil
    ) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: context.category)
        
        var logMessage = message
        if let metadata = context.metadata {
            logMessage += " | Metadata: \(metadata)"
        }
        if let error = error {
            logMessage += " | Error: \(error.localizedDescription)"
        }
        
        switch level {
        case .debug:
            logger.debug("\(logMessage)")
        case .info:
            logger.info("\(logMessage)")
        case .error:
            logger.error("\(logMessage)")
        }
    }
}

// Макрос для удобства
@freestanding(expression)
macro log(_ level: LogLevel, _ message: String, metadata: [String: Any]? = nil) = #externalMacro(module: "LoggingMacros", type: "LogMacro")
```

---

### 8. Retry механизм для сетевых операций

**Проблема:** Нет автоматических повторов при сетевых ошибках.

**Решение:**
```swift
// Core/Network/RetryPolicy.swift
struct RetryPolicy {
    let maxAttempts: Int
    let delay: TimeInterval
    let backoffMultiplier: Double
    
    static let `default` = RetryPolicy(maxAttempts: 3, delay: 1.0, backoffMultiplier: 2.0)
}

func withRetry<T>(
    policy: RetryPolicy = .default,
    operation: @escaping () async throws -> T
) async throws -> T {
    var lastError: Error?
    var currentDelay = policy.delay
    
    for attempt in 1...policy.maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            
            if attempt < policy.maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                currentDelay *= policy.backoffMultiplier
            }
        }
    }
    
    throw lastError ?? NSError(domain: "Retry", code: -1)
}

// Использование в BackupManager
func backupNow() async throws {
    try await withRetry {
        try await cloudBackupStore.save(backupData)
    }
}
```

---

### 9. Мониторинг состояния backup

**Проблема:** Нет централизованного мониторинга состояния backup.

**Решение:**
```swift
// Core/Backup/BackupMonitor.swift
@MainActor
protocol BackupMonitorProtocol: ObservableObject {
    var lastBackupDate: Date? { get }
    var backupSize: Int64? { get }
    var isBackupInProgress: Bool { get }
    var lastBackupError: AppError? { get }
}

@MainActor
final class BackupMonitor: BackupMonitorProtocol {
    @Published var lastBackupDate: Date?
    @Published var backupSize: Int64?
    @Published var isBackupInProgress: Bool = false
    @Published var lastBackupError: AppError?
    
    private let backupManager: BackupManagerProtocol
    
    init(backupManager: BackupManagerProtocol) {
        self.backupManager = backupManager
    }
    
    func updateStatus() async {
        isBackupInProgress = true
        defer { isBackupInProgress = false }
        
        if let info = await backupManager.lastBackupInfo() {
            lastBackupDate = info.date
            backupSize = info.size
            lastBackupError = nil
        }
    }
}
```

---

### 10. Опциональное шифрование backup

**Решение:**
```swift
// Core/Security/BackupEncryption.swift
protocol BackupEncryptionProtocol {
    func encrypt(_ data: Data) throws -> Data
    func decrypt(_ data: Data) throws -> Data
}

final class KeychainBackupEncryption: BackupEncryptionProtocol {
    private let keychain = Keychain(service: "com.millio.backup")
    private let keyTag = "backup.encryption.key"
    
    func encrypt(_ data: Data) throws -> Data {
        let key = try getOrCreateKey()
        // Используем CryptoKit для шифрования
        // ...
    }
    
    func decrypt(_ data: Data) throws -> Data {
        let key = try getKey()
        // Расшифровка
        // ...
    }
    
    private func getOrCreateKey() throws -> SymmetricKey {
        // Получение/создание ключа из Keychain
    }
}

// Использование в BackupManager
if SettingsManager.shared.isEncryptionEnabled {
    let encryption = KeychainBackupEncryption()
    backupData = try encryption.encrypt(backupData)
}
```

---

## Улучшения производительности

### 11. Потоковая сериализация для больших backup

**Решение:**
```swift
// Core/Backup/StreamingBackup.swift
func exportAllDataStreaming() async throws -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                // Экспорт порциями
                let batchSize = 100
                let registeredTypes = ModelTypeRegistry.shared.getExportableTypes()
                
                for (typeName, type) in registeredTypes {
                    // Экспорт по батчам
                    // continuation.yield(batchData)
                }
                
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

---

### 12. Сжатие backup

**Решение:**
```swift
import Compression

func compress(_ data: Data) throws -> Data {
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
    defer { buffer.deallocate() }
    
    data.copyBytes(to: buffer, count: data.count)
    
    let compressed = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
    defer { compressed.deallocate() }
    
    let compressedSize = compression_encode_buffer(
        compressed, data.count,
        buffer, data.count,
        nil,
        COMPRESSION_LZFSE
    )
    
    return Data(bytes: compressed, count: compressedSize)
}
```

---

## Архитектурные улучшения

### 13. Event Bus для слабой связанности

**Решение:**
```swift
// Core/Events/EventBus.swift
protocol AppEvent {}
enum BackupEvent: AppEvent {
    case started
    case completed(Date)
    case failed(AppError)
}

@MainActor
final class EventBus {
    private var subscribers: [UUID: (AppEvent) -> Void] = [:]
    
    func subscribe(_ handler: @escaping (AppEvent) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        return id
    }
    
    func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
    
    func publish(_ event: AppEvent) {
        for handler in subscribers.values {
            handler(event)
        }
    }
}
```

---

### 14. Feature Module Registration

**Решение:**
```swift
// Core/Features/FeatureRegistry.swift
protocol FeatureModule {
    func registerModels(in registry: ModelTypeRegistryProtocol)
    func registerRoutes(in router: AppRouter)
    func configureDependencies(in container: DIContainer)
}

final class FeatureRegistry {
    private var features: [FeatureModule] = []
    
    func register(_ feature: FeatureModule) {
        features.append(feature)
    }
    
    func configureAll() {
        for feature in features {
            feature.registerModels(in: ModelTypeRegistry.shared)
            // ...
        }
    }
}
```

---

## Приоритизация

### Критично (сделать сейчас):
1. ✅ Использование DIContainer
2. ✅ Вынос схемы SwiftData
3. ✅ Устранение fatalError
4. ✅ Использование ModelTypeRegistry в DataRepository

### Важно (следующий спринт):
5. ViewModel слой
6. Структурированная обработка ошибок
7. Retry механизм
8. Мониторинг backup

### Желательно (по мере необходимости):
9. Шифрование backup
10. Потоковая сериализация
11. Сжатие backup
12. Event Bus
13. Feature Module Registration

---

## Рекомендации

1. **Начните с критических улучшений** - они исправляют архитектурные нарушения
2. **ViewModel слой** - добавьте постепенно, начиная с самых сложных экранов
3. **Error Recovery** - добавьте для критических операций (backup/restore)
4. **Мониторинг** - важен для production, но можно отложить до beta

Ядро уже хорошо структурировано, но эти улучшения сделают его более масштабируемым и надежным.
