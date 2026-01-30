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
}

final class DataRepository: DataRepositoryProtocol {
    private let modelContext: ModelContext
    private let modelContainer: ModelContainer
    
    init(modelContext: ModelContext, modelContainer: ModelContainer) {
        self.modelContext = modelContext
        self.modelContainer = modelContainer
    }
    
    func exportAllData() throws -> Data {
        let metadata = BackupMetadata(
            version: .current,
            timestamp: Date(),
            schemaVersion: "2.0",
            modelCount: 0
        )
        
        var modelsData: [[String: Any]] = []
        let registeredTypes = ModelTypeRegistry.shared.getExportableTypes()
        let typeNames = registeredTypes.keys.sorted()
        
        for typeName in typeNames {
            guard let exporter = ModelTypeRegistry.shared.getBackupExporter(for: typeName) else { continue }
            modelsData.append(contentsOf: try exporter(modelContext))
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
    
    private func metadataToDict(_ metadata: BackupMetadata) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    
    func importAllData(_ data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsData = json["models"] as? [[String: Any]] else {
            throw AppError.backupCorrupted
        }
        
        // Проверяем версию backup
        if let metadataDict = json["metadata"] as? [String: Any] {
            let decoder = JSONDecoder()
            if let metadataData = try? JSONSerialization.data(withJSONObject: metadataDict),
               let metadata = try? decoder.decode(BackupMetadata.self, from: metadataData) {
                // Проверяем совместимость версий
                if !metadata.version.isCompatible(with: .current) {
                    throw AppError.incompatibleSchemaVersion
                }
            }
        }
        let typedModels: [(priority: Int, typeName: String, data: [String: Any], importer: ModelImporter.Type)] = modelsData.compactMap { modelData in
            guard let typeName = modelData["_type"] as? String,
                  let importer = ModelTypeRegistry.shared.getImporter(for: typeName) else {
                return nil
            }
            return (priority: importer.importPriority, typeName: typeName, data: modelData, importer: importer)
        }
        .sorted { $0.priority < $1.priority }
        
        var currentPriority: Int? = nil
        
        for item in typedModels {
            if currentPriority != item.priority {
                if currentPriority != nil {
                    try modelContext.save()
                }
                currentPriority = item.priority
            }
            
            try item.importer.`import`(from: item.data, context: modelContext)
        }
        
        try modelContext.save()
    }
    
    func clearAllData() throws {
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
            try clearer(modelContext)
        }
        
        try modelContext.save()
    }
}
