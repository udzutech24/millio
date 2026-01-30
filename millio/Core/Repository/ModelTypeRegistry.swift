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
    private let lock = NSLock()
    
    struct State {
        let registeredTypes: [String: any Persistable.Type]
        let importers: [String: ModelImporter.Type]
        let backupExporters: [String: (ModelContext) throws -> [[String: Any]]]
        let backupClearers: [String: (ModelContext) throws -> Void]
    }
    
    private init() {
        // Регистрируем базовые типы ядра
        register(Item.self, typeName: "Item")
        registerImporter(ItemImporter.self)
    }
    
    func captureState() -> State {
        lock.lock()
        defer { lock.unlock() }
        return State(
            registeredTypes: registeredTypes,
            importers: importers,
            backupExporters: backupExporters,
            backupClearers: backupClearers
        )
    }
    
    func restoreState(_ state: State) {
        lock.lock()
        defer { lock.unlock() }
        registeredTypes = state.registeredTypes
        importers = state.importers
        backupExporters = state.backupExporters
        backupClearers = state.backupClearers
    }
    
    func register<T: Persistable>(_ type: T.Type, typeName: String) {
        lock.lock()
        defer { lock.unlock() }
        
        registeredTypes[typeName] = type
        
        if backupExporters[typeName] == nil {
            backupExporters[typeName] = { context in
                let descriptor = FetchDescriptor<T>()
                let items = try context.fetch(descriptor)
                
                var exported: [[String: Any]] = []
                exported.reserveCapacity(items.count)
                
                for item in items {
                    let data = try item.export()
                    var json = try BackupJSON.decodeExportedDict(data, typeName: typeName)
                    json["_type"] = typeName
                    exported.append(json)
                }
                
                return exported
            }
        }
        
        if backupClearers[typeName] == nil {
            backupClearers[typeName] = { context in
                let descriptor = FetchDescriptor<T>()
                let items = try context.fetch(descriptor)
                for item in items {
                    context.delete(item)
                }
            }
        }
    }
    
    func registerImporter<T: ModelImporter>(_ importer: T.Type) {
        let typeName = importer.importType()
        lock.lock()
        defer { lock.unlock() }
        importers[typeName] = importer as ModelImporter.Type
    }
    
    func getExportableTypes() -> [String: any Persistable.Type] {
        lock.lock()
        defer { lock.unlock() }
        return registeredTypes
    }
    
    func getImporter(for typeName: String) -> ModelImporter.Type? {
        lock.lock()
        defer { lock.unlock() }
        return importers[typeName]
    }
    
    func registerBackupExporter(_ typeName: String, exporter: @escaping (ModelContext) throws -> [[String: Any]]) {
        lock.lock()
        defer { lock.unlock() }
        backupExporters[typeName] = exporter
    }
    
    func registerBackupClearer(_ typeName: String, clearer: @escaping (ModelContext) throws -> Void) {
        lock.lock()
        defer { lock.unlock() }
        backupClearers[typeName] = clearer
    }
    
    func getBackupExporter(for typeName: String) -> ((ModelContext) throws -> [[String: Any]])? {
        lock.lock()
        defer { lock.unlock() }
        return backupExporters[typeName]
    }
    
    func getBackupClearer(for typeName: String) -> ((ModelContext) throws -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return backupClearers[typeName]
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
