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
    static var importPriority: Int { get }
    static func `import`(from data: [String: Any], context: ModelContext) throws
}

extension ModelImporter {
    static var importPriority: Int { 100 }
}

/// Регистрация типов моделей для экспорта/импорта
/// Позволяет фичам регистрировать свои типы без изменения ядра
protocol ModelTypeRegistryProtocol {
    func register<T: Persistable>(_ type: T.Type, typeName: String)
    func registerImporter<T: ModelImporter>(_ importer: T.Type)
    func getExportableTypes() -> [String: any Persistable.Type]
    func getImporter(for typeName: String) -> ModelImporter.Type?
    func registerBackupExporter(_ typeName: String, exporter: @escaping (ModelContext) throws -> [[String: Any]])
    func registerBackupClearer(_ typeName: String, clearer: @escaping (ModelContext) throws -> Void)
    func getBackupExporter(for typeName: String) -> ((ModelContext) throws -> [[String: Any]])?
    func getBackupClearer(for typeName: String) -> ((ModelContext) throws -> Void)?
}

final class ModelTypeRegistry: ModelTypeRegistryProtocol {
    static let shared = ModelTypeRegistry()
    
    private var registeredTypes: [String: any Persistable.Type] = [:]
    private var importers: [String: ModelImporter.Type] = [:]
    private var backupExporters: [String: (ModelContext) throws -> [[String: Any]]] = [:]
    private var backupClearers: [String: (ModelContext) throws -> Void] = [:]
    private let queue = DispatchQueue(label: "com.millio.modelTypeRegistry", attributes: .concurrent)
    
    private init() {
        // Регистрируем базовые типы ядра
        register(Item.self, typeName: "Item")
        registerImporter(ItemImporter.self)
    }
    
    func register<T: Persistable>(_ type: T.Type, typeName: String) {
        queue.sync(flags: .barrier) {
            self.registeredTypes[typeName] = type
            
            if self.backupExporters[typeName] == nil {
                self.backupExporters[typeName] = { context in
                    let descriptor = FetchDescriptor<T>()
                    let items = try context.fetch(descriptor)
                    
                    var exported: [[String: Any]] = []
                    exported.reserveCapacity(items.count)
                    
                    for item in items {
                        let data = try item.export()
                        if var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            json["_type"] = typeName
                            exported.append(json)
                        }
                    }
                    
                    return exported
                }
            }
            
            if self.backupClearers[typeName] == nil {
                self.backupClearers[typeName] = { context in
                    let descriptor = FetchDescriptor<T>()
                    let items = try context.fetch(descriptor)
                    for item in items {
                        context.delete(item)
                    }
                }
            }
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
    
    func registerBackupExporter(_ typeName: String, exporter: @escaping (ModelContext) throws -> [[String: Any]]) {
        queue.sync(flags: .barrier) {
            self.backupExporters[typeName] = exporter
        }
    }
    
    func registerBackupClearer(_ typeName: String, clearer: @escaping (ModelContext) throws -> Void) {
        queue.sync(flags: .barrier) {
            self.backupClearers[typeName] = clearer
        }
    }
    
    func getBackupExporter(for typeName: String) -> ((ModelContext) throws -> [[String: Any]])? {
        queue.sync {
            return backupExporters[typeName]
        }
    }
    
    func getBackupClearer(for typeName: String) -> ((ModelContext) throws -> Void)? {
        queue.sync {
            return backupClearers[typeName]
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
