//
//  DataRepository.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

protocol DataRepositoryProtocol {
    func exportAllData() throws -> Data
    func importAllData(_ data: Data) throws
    func clearAllData() throws
    
    func exportAllDataAsync() async throws -> Data
    func importAllDataAsync(_ data: Data) async throws
    func clearAllDataAsync() async throws
}

final class DataRepository: DataRepositoryProtocol {
    private let modelContext: ModelContext
    private let modelContainer: ModelContainer
    private let worker: DataRepositoryWorker
    
    init(modelContext: ModelContext, modelContainer: ModelContainer) {
        self.modelContext = modelContext
        self.modelContainer = modelContainer
        self.worker = DataRepositoryWorker(modelContainer: modelContainer)
    }
    
    func exportAllData() throws -> Data {
        try Self.exportAllData(from: modelContext)
    }
    
    func exportAllDataAsync() async throws -> Data {
        try await MainActor.run {
            try modelContext.save()
        }
        return try await worker.exportAllData()
    }
    
    static func exportAllData(from context: ModelContext) throws -> Data {
        let metadata = BackupMetadata(
            version: .current,
            timestamp: Date(),
            schemaVersion: BackupMetadata.currentSchemaVersion,
            modelCount: 0
        )
        
        var modelsData: [[String: Any]] = []
        let registeredTypes = ModelTypeRegistry.shared.getExportableTypes()
        let typeNames = registeredTypes.keys.sorted()
        
        for typeName in typeNames {
            guard let exporter = ModelTypeRegistry.shared.getBackupExporter(for: typeName) else { continue }
            modelsData.append(contentsOf: try exporter(context))
        }
        
        // Обновляем metadata с реальным количеством моделей
        let updatedMetadata = BackupMetadata(
            version: metadata.version,
            timestamp: metadata.timestamp,
            schemaVersion: metadata.schemaVersion,
            modelCount: modelsData.count
        )
        
        let exportDict: [String: Any] = [
            "metadata": try metadataToDict(updatedMetadata),
            "models": modelsData
        ]
        
        return try JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted)
    }
    
    static func metadataToDict(_ metadata: BackupMetadata) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw AppError.backupFailed("Не удалось сериализовать metadata для backup")
        }
        return dict
    }
    
    func importAllData(_ data: Data) throws {
        try Self.importAllData(data, into: modelContext)
    }
    
    func importAllDataAsync(_ data: Data) async throws {
        try await worker.importAllData(data)
    }
    
    static func importAllData(_ data: Data, into context: ModelContext) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsData = json["models"] as? [[String: Any]] else {
            throw AppError.backupCorrupted
        }
        
        guard let metadataDict = json["metadata"] as? [String: Any] else {
            throw AppError.backupCorrupted
        }
        let decoder = JSONDecoder()
        guard let metadataData = try? JSONSerialization.data(withJSONObject: metadataDict),
              let metadata = try? decoder.decode(BackupMetadata.self, from: metadataData) else {
            throw AppError.backupCorrupted
        }
        
        if metadata.schemaVersion != BackupMetadata.currentSchemaVersion {
            throw AppError.incompatibleSchemaVersion
        }
        if !metadata.version.isCompatible(with: .current) {
            throw AppError.incompatibleSchemaVersion
        }
        if metadata.modelCount != modelsData.count {
            throw AppError.backupCorrupted
        }
        
        var unknownTypes: Set<String> = []
        var typedModels: [(priority: Int, typeName: String, data: [String: Any], importer: ModelImporter.Type)] = []
        typedModels.reserveCapacity(modelsData.count)
        
        for modelData in modelsData {
            guard let typeName = modelData["_type"] as? String else {
                throw AppError.backupCorrupted
            }
            guard let importer = ModelTypeRegistry.shared.getImporter(for: typeName) else {
                unknownTypes.insert(typeName)
                continue
            }
            typedModels.append((priority: importer.importPriority, typeName: typeName, data: modelData, importer: importer))
        }
        
        if !unknownTypes.isEmpty {
            let types = unknownTypes.sorted().joined(separator: ", ")
            throw AppError.restoreFailed("Неизвестные типы моделей в backup: \(types)")
        }
        
        typedModels.sort { $0.priority < $1.priority }
        
        var currentPriority: Int? = nil
        
        for item in typedModels {
            if currentPriority != item.priority {
                if currentPriority != nil {
                    try context.save()
                }
                currentPriority = item.priority
            }
            
            try item.importer.`import`(from: item.data, context: context)
        }
        
        try context.save()
    }
    
    func clearAllData() throws {
        try Self.clearAllData(in: modelContext)
    }
    
    func clearAllDataAsync() async throws {
        try await worker.clearAllData()
    }
    
    static func clearAllData(in context: ModelContext) throws {
        let registeredTypes = ModelTypeRegistry.shared.getExportableTypes()
        let typeNames = registeredTypes.keys.sorted { lhs, rhs in
            let lhsPriority = ModelTypeRegistry.shared.getImporter(for: lhs)?.importPriority ?? 100
            let rhsPriority = ModelTypeRegistry.shared.getImporter(for: rhs)?.importPriority ?? 100
            if lhsPriority != rhsPriority {
                return lhsPriority > rhsPriority
            }
            return lhs > rhs
        }
        
        for typeName in typeNames {
            guard let clearer = ModelTypeRegistry.shared.getBackupClearer(for: typeName) else { continue }
            try clearer(context)
        }
        
        try context.save()
    }
}

actor DataRepositoryWorker {
    private let modelContainer: ModelContainer
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    private func makeContext() -> ModelContext {
        ModelContext(modelContainer)
    }
    
    func exportAllData() throws -> Data {
        let modelContext = makeContext()
        return try DataRepository.exportAllData(from: modelContext)
    }
    
    func importAllData(_ data: Data) throws {
        let modelContext = makeContext()
        try DataRepository.importAllData(data, into: modelContext)
    }
    
    func clearAllData() throws {
        let modelContext = makeContext()
        try DataRepository.clearAllData(in: modelContext)
    }
}
