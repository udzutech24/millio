//
//  ModelTypeRegistry.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Протокол для импорта моделей из backup
protocol ModelImporter {
    static func importType() -> String
    static func `import`(from data: [String: Any], context: ModelContext) throws
}

/// Регистрация типов моделей для экспорта/импорта
/// Позволяет фичам регистрировать свои типы без изменения ядра
protocol ModelTypeRegistryProtocol {
    func register<T: Persistable>(_ type: T.Type, typeName: String)
    func registerImporter<T: ModelImporter>(_ importer: T.Type)
    func getExportableTypes() -> [String: any Persistable.Type]
    func getImporter(for typeName: String) -> ModelImporter.Type?
}

final class ModelTypeRegistry: ModelTypeRegistryProtocol {
    static let shared = ModelTypeRegistry()
    
    private var registeredTypes: [String: any Persistable.Type] = [:]
    private var importers: [String: ModelImporter.Type] = [:]
    private let queue = DispatchQueue(label: "com.millio.modelTypeRegistry", attributes: .concurrent)
    
    private init() {
        // Регистрируем базовые типы ядра
        register(Item.self, typeName: "Item")
        registerImporter(ItemImporter.self)
    }
    
    func register<T: Persistable>(_ type: T.Type, typeName: String) {
        queue.async(flags: .barrier) {
            self.registeredTypes[typeName] = type
        }
    }
    
    func registerImporter<T: ModelImporter>(_ importer: T.Type) {
        let typeName = importer.importType()
        // Приводим к базовому типу и сохраняем в словарь напрямую через sync
        // чтобы избежать проблем с Sendable в async closure
        queue.sync(flags: .barrier) {
            self.importers[typeName] = importer as ModelImporter.Type
        }
    }
    
    func getExportableTypes() -> [String: any Persistable.Type] {
        queue.sync {
            return registeredTypes
        }
    }
    
    func getImporter(for typeName: String) -> ModelImporter.Type? {
        queue.sync {
            return importers[typeName]
        }
    }
    
    /// Получить все зарегистрированные типы как PersistentModel.Type
    func getRegisteredTypes() -> [String: any Persistable.Type] {
        return getExportableTypes()
    }
}

// MARK: - Item Importer

struct ItemImporter: ModelImporter {
    static func importType() -> String {
        "Item"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let timestampInterval = data["timestamp"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        let timestamp = Date(timeIntervalSince1970: timestampInterval)
        let item = Item(timestamp: timestamp)
        context.insert(item)
    }
}
