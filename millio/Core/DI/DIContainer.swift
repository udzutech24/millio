//
//  DIContainer.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Dependency Injection Container для ядра приложения
final class DIContainer {
    let appState: AppState
    let modelContainer: ModelContainer
    let dataRepository: DataRepositoryProtocol
    let backupManager: BackupManagerProtocol
    let recoveryCoordinator: RecoveryCoordinator
    let recoveryScopeToken: RecoveryScopeToken
    let authService: any AuthServiceProtocol
    let apiClientFactory: APIClientFactory
    let sheetsExportService: any SheetsExportServiceProtocol
    let sheetsExportTrigger: SheetsExportTrigger

    init(
        appState: AppState,
        modelContainer: ModelContainer,
        dataRepository: DataRepositoryProtocol,
        backupManager: BackupManagerProtocol,
        recoveryCoordinator: RecoveryCoordinator,
        recoveryScopeToken: RecoveryScopeToken,
        authService: any AuthServiceProtocol,
        apiClientFactory: APIClientFactory,
        sheetsExportService: any SheetsExportServiceProtocol,
        sheetsExportTrigger: SheetsExportTrigger
    ) {
        self.appState = appState
        self.modelContainer = modelContainer
        self.dataRepository = dataRepository
        self.backupManager = backupManager
        self.recoveryCoordinator = recoveryCoordinator
        self.recoveryScopeToken = recoveryScopeToken
        self.authService = authService
        self.apiClientFactory = apiClientFactory
        self.sheetsExportService = sheetsExportService
        self.sheetsExportTrigger = sheetsExportTrigger
    }
    
    @MainActor
    static func create(
        appState: AppState,
        modelContainer: ModelContainer,
        backendRuntime: BackendSessionRuntime,
        scopeIdentifier: String
    ) -> DIContainer {
        let runtimeEnvironment = AppRuntimeEnvironment.current()
        let modelContext = modelContainer.mainContext
        do {
            try DataIntegrityCleaner.runIfNeeded(modelContext: modelContext)
            try DataIntegrityCleaner.revertBadArchiveMigrationIfNeeded(modelContext: modelContext, scopeIdentifier: scopeIdentifier)
            try DataIntegrityCleaner.archiveZeroQuantityInvestmentsIfNeeded(modelContext: modelContext, scopeIdentifier: scopeIdentifier)
            // Без одноразового флага — гоняется на каждом create() (guest и user scope,
            // на каждый rebindDataScope), см. комментарий на dedupeCashflowCustomCategoriesOnLaunch.
            try DataIntegrityCleaner.dedupeCashflowCustomCategoriesOnLaunch(modelContext: modelContext)
            try DataIntegrityCleaner.dedupeCashbackCustomCategoriesOnLaunch(modelContext: modelContext)
            try DataIntegrityCleaner.dedupeBudgetCategoryLimitsOnLaunch(modelContext: modelContext)
        } catch {
            AppLogger.log(.error, category: "Integrity", "Data integrity cleanup failed: \(error.localizedDescription)")
        }
        let dataRepository = DataRepository(
            modelContext: modelContext,
            modelContainer: modelContainer
        )
        
        let disabledBackupManager: BackupManagerProtocol = MockBackupManager()
        let backupManager: BackupManagerProtocol
        if runtimeEnvironment.isAnyTesting {
            backupManager = disabledBackupManager
        } else {
            // Self-heal после restore: если бэкап вернул до-AccountsCore-стор (легаси без ядра),
            // прогоняем идемпотентную легаси→core миграцию сразу — без ожидания перезапуска.
            // GroupsMigrator здесь НЕ вызываем: он гейтится собственным (безусловно выставляемым) флагом,
            // после restore этот флаг stale → гарантированный no-op, а его поля групп (favorite/color/
            // priority) косметические и не относятся к багу невидимых счетов.
            let enabledBackupManager: BackupManagerProtocol = BackupManager(
                dataRepository: dataRepository,
                historicalValuationScopeID: scopeIdentifier,
                onDidReplaceStore: {
                    let readiness = HistoricalValuationReadinessCoordinator.shared
                    readiness.begin(scopeID: scopeIdentifier, operation: .revisionMigration)
                    let summary = LegacyAccountsMigrator(modelContext: modelContext)
                        .migrateIfNeeded(scopeIdentifier: scopeIdentifier)
                    guard summary.failures == 0 else {
                        readiness.fail(
                            scopeID: scopeIdentifier,
                            operation: .revisionMigration,
                            reasonCode: "legacy_product_migration_failed"
                        )
                        appState.lifecycle = .error(.incompatibleSchemaVersion)
                        return
                    }
                    do {
                        let evidence = LegacyProductEvidenceCollector.collect(
                            in: modelContainer.mainContext
                        )
                        _ = try AccountProductIdentityMigrator.migratePersistedAccounts(
                            in: modelContainer,
                            verifiedEvidenceByCoreAccountID: evidence
                        )
                        readiness.complete(scopeID: scopeIdentifier, operation: .revisionMigration)
                    } catch {
                        readiness.fail(
                            scopeID: scopeIdentifier,
                            operation: .revisionMigration,
                            reasonCode: "product_classification_failed"
                        )
                        appState.lifecycle = .error(.incompatibleSchemaVersion)
                        AppLogger.log(.error, category: "AccountsCore", "Post-restore product classification failed: \(error.localizedDescription)")
                    }
                }
            )
            backupManager = SwitchingBackupManager(
                appState: appState,
                enabled: enabledBackupManager,
                disabled: disabledBackupManager
            )
        }
        let apiClientFactory = APIClientFactory(runtime: backendRuntime)
        let authService: any AuthServiceProtocol = apiClientFactory.makeAuthService()
        let sheetsExportService = apiClientFactory.makeSheetsExportService(authService: authService)
        let sheetsExportTrigger = apiClientFactory.makeSheetsExportTrigger(exportService: sheetsExportService)
        let recoveryScopeToken = RecoveryScopeToken(
            kind: scopeIdentifier == DataScope.guest.storeConfigurationName ? .guest : .authenticated,
            generation: 0
        )
        let recoveryCoordinator = RecoveryCoordinator(
            backupManager: backupManager,
            localModelCount: {
                guard let payload = try? dataRepository.exportAllData(),
                      let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                      let models = object["models"] as? [[String: Any]] else { return nil }
                return models.count
            },
            isScopeCurrent: { $0 == recoveryScopeToken }
        )

        return DIContainer(
            appState: appState,
            modelContainer: modelContainer,
            dataRepository: dataRepository,
            backupManager: backupManager,
            recoveryCoordinator: recoveryCoordinator,
            recoveryScopeToken: recoveryScopeToken,
            authService: authService,
            apiClientFactory: apiClientFactory,
            sheetsExportService: sheetsExportService,
            sheetsExportTrigger: sheetsExportTrigger
        )
    }
}
