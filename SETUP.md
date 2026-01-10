# Инструкция по настройке

## Обязательные шаги

### 1. CloudKit Capability

1. Откройте проект в Xcode
2. Выберите проект → Target `millio` → вкладка **Signing & Capabilities**
3. Нажмите **+ Capability**
4. Добавьте **CloudKit**
5. Убедитесь, что выбран Container (по умолчанию используется default container)

### 2. Bundle Identifier

Убедитесь, что Bundle Identifier настроен в проекте:
- Текущий: `com.millio.millio`
- Измените при необходимости в настройках Target

### 3. Signing

Настройте Team для подписи приложения (требуется для CloudKit)

### 4. Info.plist

Файл `Info.plist` уже настроен для темной темы. Если используете `GENERATE_INFOPLIST_FILE = YES`, добавьте в настройки проекта:
- `UIUserInterfaceStyle` = `Dark`

## Тестирование

### Backup/Restore

1. Запустите приложение на устройстве или симуляторе
2. Войдите в iCloud на устройстве
3. Создайте некоторые данные в приложении
4. Закройте приложение (background backup сработает автоматически)
5. Удалите приложение
6. Установите заново
7. При первом запуске должен появиться экран восстановления

### Offline режим

1. Отключите iCloud в настройках устройства
2. Приложение должно работать стабильно
3. Backup будет недоступен, но приложение не должно крашиться

## Известные ограничения

- Импорт данных в `DataRepository.importAllData()` требует регистрации импортеров через `ModelTypeRegistry`
- Экспорт работает для всех зарегистрированных типов через `ModelTypeRegistry`

## Расширение ядра

### Добавление новой модели

```swift
// 1. Создайте модель
@Model
final class MyModel: Persistable {
    var name: String
    
    func export() throws -> Data {
        let dict = ["name": name]
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    static func `import`(_ data: Data) throws {
        // Импорт через ModelImporter
    }
}

// 2. Создайте импортер
struct MyModelImporter: ModelImporter {
    static func importType() -> String { "MyModel" }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let name = data["name"] as? String else {
            throw AppError.backupCorrupted
        }
        let model = MyModel(name: name)
        context.insert(model)
    }
}

// 3. Зарегистрируйте модель и импортер
ModelTypeRegistry.shared.register(MyModel.self, typeName: "MyModel")
ModelTypeRegistry.shared.registerImporter(MyModelImporter.self)
```

### Добавление нового экрана

1. Создайте View в папке `UI/`
2. Добавьте route в `AppRoute` enum
3. Обновите `RootViewResolver` для обработки нового route
