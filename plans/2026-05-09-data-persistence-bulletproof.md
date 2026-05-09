# Plan: Bulletproof Data Persistence

**Date:** 2026-05-09
**Status:** РЕАЛИЗОВАН
**Spec:** [`specs/2026-05-09-data-persistence-bulletproof.md`](../specs/2026-05-09-data-persistence-bulletproof.md)
**Branch:** `develop` (hotfix + phases 1–4 на develop напрямую — критический баг)

---

## Диагноз (зафиксирован перед планом)

| # | Root Cause | Файл | Статус |
|---|-----------|------|--------|
| A | `Cashback.self` в `ModelTypeRegistry` но не в `AppMigrationPlan` → store rebuilt empty in DEBUG | `AppSchemaVersions.swift` | Uncommitted fix готов (git diff) |
| B | Auth-restore fail → scope → `.guest` → пустой store | `millioApp.swift` `DataScope.swift` | Требует верификации |
| C | Нет теста/assertion на синхронность схем | — | Не сделано |

**Главный риск на сегодня:** Root Cause A. Uncommitted diff (`Cashback.self`) правильный, но не коммитнут. Если пользователь запустит старый билд снова — данные снова потеряются.

---

## Phase 0 — Hotfix (1 сессия, СРОЧНО) `[x]`

**Цель:** остановить кровотечение; сохранить что можно.

### 0.1 — Проверить `.bak.store` на симуляторе/девайсе
```bash
# Найти .bak файлы:
find ~/Library/Developer/CoreSimulator -name "*.bak.store" 2>/dev/null
# На реальном девайсе — в Xcode → Devices → Download Container
```
- Если `.bak.store` есть → данные **живые**, можно восстановить
- Если нет → данные утеряны, двигаемся дальше

### 0.2 — Закоммитить uncommitted fix
Файл `AppSchemaVersions.swift` (добавляет `Cashback.self` в V1/V2/makeContainer).
```
git add millio/Core/Schema/AppSchemaVersions.swift
git commit -m "fix(schema): add Cashback.self to V1/V2/makeContainer — was missing causing store rebuild"
```

### 0.3 — Убедиться что `AppSchema.create()` и `AppMigrationPlan.makeContainer` теперь синхронны
Временный DEBUG-лог при запуске (удалить после фазы 1):
```swift
// в initializeColdStart, после makeModelContainer:
#if DEBUG
let schemaTypes = Set(AppSchema.create().entities.map { $0.name })
let planTypes: Set<String> = ["Item", "CashflowTransaction", /* ... все из makeContainer */]
let diff = schemaTypes.symmetricDifference(planTypes)
if !diff.isEmpty {
    AppLogger.log(.critical, category: "Schema", "⚠️ Schema/MigrationPlan mismatch: \(diff)")
}
#endif
```

### 0.4 — Билд и smoke-тест
- Запустить на симуляторе (или девайсе)
- Добавить несколько транзакций
- Перезапустить приложение → данные должны сохраниться
- Установить новый билд (Cmd+R без Clean) → данные должны сохраниться

**Gate:** данные переживают перезапуск и re-build.

---

## Phase 1 — Single Source of Truth (1 сессия) `[x]`

**Цель:** устранить архитектурную причину (два независимых списка моделей).

### Проблема
Сейчас есть три независимых источника модельного состава:
1. `ModelTypeRegistry.getExportableTypes()` → используется в `AppSchema.create()`
2. `AppSchemaV2.models` (+ V1) — версионированные схемы
3. `AppMigrationPlan.makeContainer` — хардкодированный variadic список

Все три должны совпадать, но механизма синхронизации нет.

### 1.1 — Рефакторинг `AppMigrationPlan.makeContainer`

Заменить хардкодированный variadic список на динамический из `AppSchemaV2.models`:

```swift
// БЫЛО (опасно — расходится с реальной схемой):
static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
    try ModelContainer(for: Item.self, CashflowTransaction.self, /* ... 17 типов */ ...)
}

// СТАНЕТ:
static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
    // AppSchemaV2.models — единственный источник правды для текущей схемы
    let schema = Schema(AppSchemaV2.models, version: AppSchemaV2.versionIdentifier)
    return try ModelContainer(
        for: schema,
        migrationPlan: AppMigrationPlan.self,
        configurations: configuration
    )
}
```

> **Примечание:** Проверить API — `ModelContainer(for: Schema, migrationPlan:, configurations:)` может требовать другую сигнатуру. Если variadic форма обязательна — сгенерировать её из `AppSchemaV2.models` через `@_disfavoredOverload` или extension.

### 1.2 — Рефакторинг `AppSchema.create()`

```swift
// БЫЛО: берёт типы из ModelTypeRegistry (динамически, может расходиться)
// СТАНЕТ: берёт из AppSchemaV2.models (= тот же источник что и AppMigrationPlan)
struct AppSchema {
    static func create() -> Schema {
        Schema(AppSchemaV2.models, version: AppSchemaV2.versionIdentifier)
    }
}
```

Если `ModelTypeRegistry` нужен для других целей (репозитории, фичи) — оставить, но исключить из пути создания схемы.

### 1.3 — Удалить временный DEBUG-лог из 0.3
После того как оба источника синхронизированы, лог больше не нужен.

### 1.4 — Добавить `typealias AppSchemaCurrent = AppSchemaV2`
```swift
// В AppSchemaVersions.swift:
typealias AppSchemaCurrent = AppSchemaV2
```
При добавлении следующей версии меняется только этот typealias.

**Gate:** `AppSchema.create()` и `AppMigrationPlan.makeContainer` используют один источник.

---

## Phase 2 — Auth/Scope Resilience (1 сессия) `[x]`

**Цель:** не сбрасываться в `.guest` при временном сбое auth.

### 2.1 — Верифицировать Root Cause B
Добавить лог в `synchronizeDataScope`:
```swift
AppLogger.log(.info, category: "App", 
    "ScopeSync: isAuthenticated=\(authManager.isAuthenticated) userID=\(user?.id ?? "nil") → scope=\(targetScope.storeConfigurationName)")
```
Если после нового билда лог показывает `scope=millio_guest` — причина B подтверждена.

### 2.2 — Кэшировать последний успешный scope
```swift
// ScopeCache.swift (новый, ~30 строк)
enum ScopeCache {
    private static let key = "last_data_scope_name"
    
    static func save(_ scope: DataScope) {
        UserDefaults.standard.set(scope.storeConfigurationName, forKey: key)
    }
    
    static func lastKnown() -> String? {
        UserDefaults.standard.string(forKey: key)
    }
}
```

### 2.3 — Использовать кэш при auth-неопределённости

В `synchronizeDataScope`:
```swift
let targetScope = DataScope.current(isAuthenticated: authManager.isAuthenticated, user: user)

// Если auth не определён (не authenticated, нет userID) — используем кэш
let resolvedScope: DataScope
if case .guest = targetScope, let cached = ScopeCache.lastKnown(), cached != "millio_guest" {
    // Auth-restore вернул гостя, но последний scope был пользовательский
    // Это признак временного сбоя auth — используем кэш
    // NOTE: В этом случае lifecycle остаётся .ready, данные доступны
    // Следующий успешный auth-refresh синхронизирует scope
    AppLogger.log(.warning, category: "App", "Auth unclear — using cached scope: \(cached)")
    // resolvedScope = попытка открыть cached scope
    // ...
} else {
    resolvedScope = targetScope
}
ScopeCache.save(resolvedScope)
```

> **Осторожно:** логика должна НЕ применяться при logout (явном). Нужен дополнительный флаг `SettingsManager.didExplicitlyLogout`.

### 2.4 — Тест
Проверить поведение при: `isAuthenticated = false`, `lastKnownScope = .user(...)`.

**Gate:** При auth-failure приложение открывает пользовательский store (если он существует), а не гостевой.

---

## Phase 3 — Schema Consistency Tests (1 сессия) `[x]`

**Цель:** любое будущее расхождение схем → красный тест.

### 3.1 — `SchemaConsistencyTests`

```swift
// millioTests/SchemaConsistencyTests.swift
final class SchemaConsistencyTests: XCTestCase {
    
    func testCurrentSchemaMatchesMigrationPlan() {
        // AppSchemaCurrent.models и AppMigrationPlan открывают одну схему
        let schemaTypes = Set(AppSchemaCurrent.models.map { String(describing: $0) })
        
        // Для проверки AppMigrationPlan — открываем in-memory container и сравниваем entities
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! AppMigrationPlan.makeContainer(configuration: config)
        let planTypes = Set(container.schema.entities.map { $0.name })
        
        // Сравниваем имена типов
        let schemaNames = Set(AppSchemaCurrent.models.map { 
            String(describing: $0).components(separatedBy: ".").last! 
        })
        XCTAssertEqual(schemaNames, planTypes, 
            "AppSchemaCurrent.models и AppMigrationPlan содержат разные модели: \(schemaNames.symmetricDifference(planTypes))")
    }
    
    func testAllSchemaVersionsAreSuperset() {
        // V2 должна содержать все модели из V1 (плюс новые)
        let v1Names = Set(AppSchemaV1.models.map { String(describing: $0) })
        let v2Names = Set(AppSchemaV2.models.map { String(describing: $0) })
        XCTAssertTrue(v1Names.isSubset(of: v2Names), 
            "V1 содержит модели отсутствующие в V2: \(v1Names.subtracting(v2Names))")
    }
}
```

### 3.2 — `SchemaMigrationTests` (уже существует, расширить)

```swift
// Добавить тест: создать store V1 (без UserSubscription),
// открыть через AppMigrationPlan, убедиться что данные V1 живы
func testV1toV2MigrationPreservesData() throws {
    // 1. Создать V1 store с тестовыми данными
    let v1Container = try makeV1Container()
    let context = v1Container.mainContext
    // вставить CashflowTransaction, Card, Cashback, ...
    try context.save()
    let storeURL = v1Container.configurations.first!.url
    
    // 2. Открыть через AppMigrationPlan (V1→V2)
    let config = ModelConfiguration("test", url: storeURL, cloudKitDatabase: .none)
    let v2Container = try AppMigrationPlan.makeContainer(configuration: config)
    
    // 3. Убедиться что данные на месте
    let txCount = try v2Container.mainContext.fetchCount(FetchDescriptor<CashflowTransaction>())
    XCTAssertGreaterThan(txCount, 0)
}
```

**Gate:** `SchemaConsistencyTests` красный при добавлении модели без обновления плана.

---

## Phase 4 — Safer DEBUG Rebuild (0.5 сессии) `[x]`

**Цель:** когда `rebuildStorePreservingData` всё же срабатывает — разработчик сразу видит это.

### 4.1 — Prominent warning

В `rebuildStorePreservingData`:
```swift
AppLogger.log(.critical, category: "Schema", """
⚠️⚠️⚠️ DATA LOSS: Store rebuilt from scratch!
Old store backed up to: \(backupURL.path)
To recover: copy .bak file, rename to .store, relaunch.
Check AppMigrationPlan — a model type may be missing.
""")
```

### 4.2 — Push notification на симуляторе (опционально)

Отправить local notification "Schema mismatch — data rebuilt" чтобы разработчик не пропустил.

### 4.3 — Auto-backup попытка перед rebuild

```swift
// В makeModelContainer, перед вызовом rebuildStorePreservingData:
#if DEBUG
if let backupManager = /* как достать? — static, через shared? */ {
    try? await backupManager.backupNow()
    AppLogger.log(.info, category: "App", "Pre-rebuild backup attempted")
}
#endif
return Self.rebuildStorePreservingData(...)
```

> **Заметка:** `makeModelContainer` — static, backupManager — instance. Нужно продумать как передать. Возможно, проще просто сделать prominent log (4.1) и не добавлять сложность.

**Gate:** Rebuild в логах виден как `[CRITICAL]` сразу при открытии Xcode console.

---

## Правило обновления схемы (зафиксировать в CLAUDE.md и docs/)

При добавлении любого нового `@Model`:
1. Добавить в `AppSchemaCurrent.models` (= `AppSchemaV_N.models`)
2. Создать `AppSchemaV_{N+1}` с новым типом
3. Добавить `MigrationStage.lightweight(from: V_N, to: V_{N+1})`
4. Обновить `AppSchemaCurrent = AppSchemaV_{N+1}`
5. Запустить `SchemaConsistencyTests` — должны быть зелёные
6. Profit

---

## Журнал сессий

| Дата | Фаза | Результат |
|------|------|-----------|
| 2026-05-09 | Диагноз + Spec + Plan | Root Cause A подтверждён, план создан |
| 2026-05-09 | Phase 0 | Cashback.self добавлен в V1/V2/makeContainer — коммит `8d537d53` |
| 2026-05-09 | Phase 1 | AppSchemaCurrent typealias + AppSchema.create() от V2.models — коммит `6caf0062` |
| 2026-05-09 | Phase 2 | ScopeCache + synchronizeDataScope guard + logout clear — коммит `6caf0062` |
| 2026-05-09 | Phase 3 | SchemaConsistencyTests (3 теста) — коммит `6caf0062` |
| 2026-05-09 | Phase 4 | CRITICAL log в rebuildStorePreservingData с путём .bak — коммит `6caf0062` |
