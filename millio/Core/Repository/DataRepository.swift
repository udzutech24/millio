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
    static let unknownModelTypesErrorPrefix = "Неизвестные типы моделей в backup: "

    private let modelContext: ModelContext
    private let worker: DataRepositoryWorker
    
    init(modelContext: ModelContext, modelContainer: ModelContainer) {
        self.modelContext = modelContext
        self.worker = DataRepositoryWorker(modelContainer: modelContainer)
    }
    
    func exportAllData() throws -> Data {
        try Self.exportAllData(from: modelContext)
    }
    
    func exportAllDataAsync() async throws -> Data {
        try await MainActor.run {
            if modelContext.hasChanges {
                try modelContext.save()
            }
        }
        return try await worker.exportAllData()
    }
    
    /// - Parameter excludedTypeNames: типы, исключаемые из экспорта (по умолчанию — ни одного,
    ///   поведение полного backup не меняется). Единственный вызывающий с непустым значением —
    ///   `ScopeMergeReader.readGuestInput` (Track B reconciliation): new-core типы (Account/
    ///   AccountEvent/AccountGroup/AccountDailySnapshot) имеют свой выделенный merge-путь
    ///   (`ScopeMergeDedup.copyNewCore`) и не должны попадать сюда — иначе reconciliation
    ///   импортирует их дважды двумя независимыми путями (см. `ScopeMergeReader.newCoreTypeNames`).
    static func exportAllData(from context: ModelContext, excluding excludedTypeNames: Set<String> = []) throws -> Data {
        let metadata = BackupMetadata(
            version: .current,
            timestamp: Date(),
            schemaVersion: BackupMetadata.currentSchemaVersion,
            modelCount: 0
        )

        var modelsData: [[String: Any]] = []
        let registeredTypes = ModelTypeRegistry.shared.getExportableTypes()
        let typeNames = registeredTypes.keys
            .filter { !excludedTypeNames.contains($0) }
            .sorted()

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
            throw BackupFailureCode.metadataSerializationFailed.appError
        }
        return dict
    }
    
    // @MainActor: единственный вызывающий (millioApp.migrateExistingStoresIfNeeded) сам
    // @MainActor — dedupeAll ниже MainActor-изолирован (SwiftData modelContext).
    @MainActor
    func importAllData(_ data: Data) throws {
        try Self.importAllData(data, into: modelContext)
        // Синхронный путь используется, в частности, legacy→scope миграцией
        // (millioApp.migrateExistingStoresIfNeeded → importAllData) — без этого вызова
        // дубли CashflowCustomCategory из старого стора копируются в новый без очистки.
        try DataIntegrityCleaner.dedupeAll(modelContext: modelContext)
    }

    func importAllDataAsync(_ data: Data) async throws {
        try await MainActor.run {
            try Self.importAllData(data, into: modelContext)
            try DataIntegrityCleaner.dedupeAll(modelContext: modelContext)
        }
    }
    
    /// - Parameter save: по умолчанию `true` (поведение restore не меняется). Reconciliation (Track B)
    ///   передаёт `false`: весь merge идёт в одном дочернем контексте с ЕДИНСТВЕННЫМ save в конце
    ///   (митигация B1b №5) — промежуточный save здесь сломал бы атомарность.
    static func importAllData(_ data: Data, into context: ModelContext, save: Bool = true) throws {
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
        
        if !metadata.isCompatibleWithCurrentSchema() {
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
            throw AppError.restoreFailed("\(Self.unknownModelTypesErrorPrefix)\(types)")
        }
        
        typedModels.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.typeName < rhs.typeName
        }
        
        for item in typedModels {
            try item.importer.`import`(from: item.data, context: context)
        }

        if save {
            try context.save()
        }
    }
    
    func clearAllData() throws {
        try Self.clearAllData(in: modelContext)
    }
    
    func clearAllDataAsync() async throws {
        try await MainActor.run {
            try Self.clearAllData(in: modelContext)
        }
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
}
