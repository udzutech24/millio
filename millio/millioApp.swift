//
//  millioApp.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData
import UIKit
import FirebaseCore
import OSLog

private enum EarlyFirebaseBootstrap {
    private static var didConfigure = false

    static func ensureConfigured() {
        guard !didConfigure else { return }
        let environment = AppRuntimeEnvironment.current()
        guard !environment.isAnyTesting else { return }
        didConfigure = true

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }
}

@MainActor
enum AppWidgetDeepLinkHandler {
    static func handle(url: URL, appState: AppState) {
        guard let action = CurrencyWidgetShared.deepLinkAction(from: url) else { return }

        switch action {
        case .openConverter:
            appState.pendingOpenConverterService = true
        case .addExpense:
            appState.pendingOpenMainExpenseSheet = true
        case .addIncome:
            appState.pendingOpenMainIncomeSheet = true
        }
    }
}

@main
struct millioApp: App {
    private struct AppDependencyBinding {
        let container: DIContainer
        let financeWarmupUseCase: FinanceStartupWarmupUseCase
        let portfolioSymbolsSyncService: PortfolioSymbolsSyncService
    }

    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var firebaseDelegate
    @State private var appState = AppState()
    @State private var diContainer: DIContainer?
    @State private var lifecycleUseCase: AppLifecycleUseCase?
    @State private var financeStartupWarmupUseCase: FinanceStartupWarmupUseCase?
    @State private var portfolioSymbolsSyncService: PortfolioSymbolsSyncService?
    @State private var authManager = AuthManager()
    @State private var toastCenter = ToastCenter()
    @State private var isBiometricUnlockInProgress = false
    @State private var activeDataScope: DataScope = .guest
    @State private var activeModelContainer: ModelContainer?
    @State private var activeScopeStoreExistedBeforeBinding = false
    @State private var backendRuntime: BackendSessionRuntime?
    @State private var startupCoordinator = StartupCoordinator(initialScope: .guest)
    @State private var appRefreshCoordinator = AppRefreshCoordinator()
    private let appLockCoordinator = AppLockLifecycleCoordinator()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "App")
    private let runtimeEnvironment: AppRuntimeEnvironment

    init() {
        let runtimeEnvironment = AppRuntimeEnvironment.current()
        self.runtimeEnvironment = runtimeEnvironment
        EarlyFirebaseBootstrap.ensureConfigured()
        Self.registerFeatures()
        let initialScope = DataScope.guest
        _activeScopeStoreExistedBeforeBinding = State(initialValue: Self.storeExists(for: initialScope))
        _activeDataScope = State(initialValue: initialScope)
        _activeModelContainer = State(initialValue: Self.makeModelContainer(for: initialScope))
        if runtimeEnvironment.isUITesting {
            let appState = AppState()
            appState.isGuestModeEnabled = true
            appState.isAppLocked = false
            appState.lifecycle = .onboarding
            _appState = State(initialValue: appState)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container = activeModelContainer {
                ZStack {
                    Group {
                        RootViewResolver(appState: appState)
                            .zIndex(0)

                        if appState.isAppLocked && appState.lifecycle == .ready {
                            AppLockScreenView {
                                await unlockWithBiometricsIfEnabled()
                            }
                            .zIndex(1)
                        }

                        GlobalToastHost()
                            .zIndex(2)
                    }
                }
                .id(appState.languageRefreshToken)
                .preferredColorScheme(.dark)
                .environment(appState)
                .environment(authManager)
                .environment(toastCenter)
                .modelContainer(container)
                .environment(\.diContainer, diContainer)
                .environment(\.appRefreshCoordinator, appRefreshCoordinator)
                .environment(\.locale, appState.selectedLanguage.locale ?? Locale.current)
                .task {
                    guard !runtimeEnvironment.isUITesting else { return }
                    await startupCoordinator.runColdStartIfNeeded {
                        await initializeColdStart(using: container)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    triggerBackgroundBackup()
                    appLockCoordinator.handleWillResignActive(appState: appState)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    guard !runtimeEnvironment.isUITesting else { return }
                    Task { @MainActor in
                        await appRefreshCoordinator.refreshSubscriptionIfNeeded(
                            reason: .appDidBecomeActive,
                            appState: appState
                        )
                        CurrencyWidgetSyncService.bootstrapFromStandardDefaults()
                        await appLockCoordinator.handleDidBecomeActive(
                            appState: appState,
                            unlockWithBiometrics: unlockWithBiometricsIfEnabled
                        )

                        await financeStartupWarmupUseCase?.warmupIfNeeded()
                    }
                }
                .onOpenURL { url in
                    AppWidgetDeepLinkHandler.handle(url: url, appState: appState)
                }
            } else {
                ErrorView(
                    error: .unknown(NSError(
                        domain: "App",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to initialize data storage"]
                    )),
                    appState: appState,
                    router: AppRouter()
                )
                .preferredColorScheme(.dark)
                .environment(appState)
            }
        }
    }
    
    @MainActor
    private func initializeColdStart(using container: ModelContainer) async {
        let start = DispatchTime.now()
        let backendRuntime = await resolveBackendRuntimeIfNeeded()

        appLockCoordinator.enforceLockStateOnLaunch(appState: appState, hasPin: AppLockPinStore.shared.hasPin())

        let binding = await prepareDependencyBinding(
            for: container,
            backendRuntime: backendRuntime
        )
        applyDependencyBinding(binding, backendRuntime: backendRuntime)

        let useCase = AppLifecycleUseCase(
            appState: appState,
            backupManager: binding.container.backupManager
        )
        
        self.lifecycleUseCase = useCase
        let initStart = DispatchTime.now()
        await useCase.initialize()
        await authManager.restoreSession()
        await synchronizeDataScope(with: authManager.currentUser)
        await presentRestoreFlowIfNeeded()
        logger.info("AppLifecycleUseCase.initialize finished in \(Double(DispatchTime.now().uptimeNanoseconds - initStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        logger.info("initializeColdStart finished in \(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        
        await runPostStartupRefreshes()
        await scheduleDailyReminderIfNeeded()
    }

    @MainActor
    private func prepareDependencyBinding(
        for modelContainer: ModelContainer,
        backendRuntime: BackendSessionRuntime
    ) async -> AppDependencyBinding {
        let diStart = DispatchTime.now()
        let container = DIContainer.create(
            appState: appState,
            modelContainer: modelContainer,
            backendRuntime: backendRuntime
        )
        let apiClientFactory = APIClientFactory(runtime: backendRuntime)
        await MarketAPIClient.shared.configure(
            authService: container.authService,
            configurationProvider: apiClientFactory.authConfigurationProvider()
        )
        let portfolioSymbolsSyncService = PortfolioSymbolsSyncService(
            snapshotProvider: InvestmentPortfolioHeldSymbolsProvider(modelContext: modelContainer.mainContext),
            apiClient: PortfolioSymbolsAPIClient(
                authService: container.authService,
                configurationProvider: apiClientFactory.authConfigurationProvider()
            ),
            eventBus: EventBus.shared,
            isAuthenticated: { self.authManager.isAuthenticated }
        )
        let financeWarmupUseCase = FinanceStartupWarmupUseCase(
            modelContext: modelContainer.mainContext
        )

        logger.info("DIContainer.create finished in \(Double(DispatchTime.now().uptimeNanoseconds - diStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        return AppDependencyBinding(
            container: container,
            financeWarmupUseCase: financeWarmupUseCase,
            portfolioSymbolsSyncService: portfolioSymbolsSyncService
        )
    }

    @MainActor
    private func applyDependencyBinding(
        _ binding: AppDependencyBinding,
        backendRuntime: BackendSessionRuntime
    ) {
        portfolioSymbolsSyncService?.stop()
        diContainer = binding.container
        financeStartupWarmupUseCase = binding.financeWarmupUseCase
        portfolioSymbolsSyncService = binding.portfolioSymbolsSyncService
        portfolioSymbolsSyncService?.start()
        authManager.configure(service: binding.container.authService)
        authManager.configure(toastCenter: toastCenter)
        authManager.configure(authConfiguration: backendRuntime.authConfiguration)
        authManager.configure(onSessionChanged: { user in
            await synchronizeDataScope(with: user)
            portfolioSymbolsSyncService?.handleAuthenticationStateChanged(
                isAuthenticated: authManager.isAuthenticated
            )
        })
        authManager.configure(onPostLoginBootstrap: { _ in })
    }

    @MainActor
    private func resolveBackendRuntimeIfNeeded() async -> BackendSessionRuntime {
        if let backendRuntime {
            appState.applyBackendRuntime(backendRuntime)
            return backendRuntime
        }

        let resolvedEndpoints: BackendEndpoints
        do {
            resolvedEndpoints = try BackendEndpoints.live(
                environment: ProcessInfo.processInfo.environment,
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            )
        } catch {
            AppLogger.log(.error, category: "Backend", "Failed to resolve backend endpoints: \(error.localizedDescription)")
            let fallbackRuntime = BackendSessionRuntime(
                selectedEndpoint: BackendEndpoint(region: .de, baseURL: URL(string: "https://api.iqdrop.ru/api/v1")!),
                preferredEndpoint: BackendEndpoint(region: .de, baseURL: URL(string: "https://api.iqdrop.ru/api/v1")!),
                fallbackActivated: false,
                forcedOverride: false,
                selectionSource: .configurationFallback,
                detectedCountryCode: SystemCountryCodeResolver.resolve()
            )
            self.backendRuntime = fallbackRuntime
            appState.applyBackendRuntime(fallbackRuntime)
            return fallbackRuntime
        }

        let runtime = await BackendStartupResolver(endpoints: resolvedEndpoints).resolve()
        self.backendRuntime = runtime
        appState.applyBackendRuntime(runtime)
        return runtime
    }

    @MainActor
    private func synchronizeDataScope(with user: AuthUser?) async {
        if authManager.isAuthenticated && appState.isGuestModeEnabled {
            appState.isGuestModeEnabled = false
        }

        let targetScope = DataScope.current(
            isAuthenticated: authManager.isAuthenticated,
            user: user
        )

        await startupCoordinator.switchScopeIfNeeded(to: targetScope) { targetScope in
            await rebindDataScope(to: targetScope)
        }
    }

    @MainActor
    private func rebindDataScope(to targetScope: DataScope) async -> Bool {
        guard targetScope != activeDataScope else { return false }

        let didTargetStoreExistBeforeBinding = Self.storeExists(for: targetScope)
        let targetContainer = Self.makeModelContainer(for: targetScope)
        if let targetContainer {
            migrateExistingStoresIfNeeded(
                into: targetContainer,
                targetScope: targetScope,
                currentScope: activeDataScope
            )
        }

        guard !Task.isCancelled else { return false }

        let binding: AppDependencyBinding?
        if let backendRuntime, let targetContainer {
            let preparedBinding = await prepareDependencyBinding(
                for: targetContainer,
                backendRuntime: backendRuntime
            )
            guard !Task.isCancelled else { return false }
            binding = preparedBinding
        } else {
            binding = nil
        }

        activeDataScope = targetScope
        activeModelContainer = targetContainer
        activeScopeStoreExistedBeforeBinding = didTargetStoreExistBeforeBinding

        if let backendRuntime, let binding {
            applyDependencyBinding(binding, backendRuntime: backendRuntime)
        }
        return true
    }

    @MainActor
    private func runPostStartupRefreshes() async {
        await appRefreshCoordinator.refreshSubscriptionIfNeeded(
            reason: .coldStart,
            appState: appState
        )
        CurrencyWidgetSyncService.bootstrapFromStandardDefaults()

        await appLockCoordinator.handleDidBecomeActive(
            appState: appState,
            unlockWithBiometrics: unlockWithBiometricsIfEnabled
        )

        await financeStartupWarmupUseCase?.warmupIfNeeded()
    }

    @MainActor
    private func scheduleDailyReminderIfNeeded() async {
        guard appState.isDailyReminderEnabled else { return }
        await NotificationManager.shared.scheduleDailyReminder(using: SettingsManager.shared.dailyReminderSettings)
    }

    private static func registerFeatures() {
        CurrencyFeatureRegistration.register()
        CardFeatureRegistration.register()
        CashbackFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
    }

    private static func makeModelContainer(for scope: DataScope) -> ModelContainer? {
        let schema = AppSchema.create()

        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            do {
                try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                AppLogger.log(.error, category: "App", "Failed to create Application Support directory: \(error.localizedDescription)")
            }
        }

        guard let storeURL = storeURL(for: scope) else {
            AppLogger.log(.error, category: "App", "Failed to resolve scoped SwiftData store URL")
            return nil
        }

        let modelConfiguration = ModelConfiguration(
            scope.storeConfigurationName,
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            AppLogger.log(.error, category: "App", "Failed to create ModelContainer: \(error)")
            do {
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                AppLogger.log(.error, category: "App", "Failed to create fallback ModelContainer: \(error)")
                do {
                    return try ModelContainer(for: Schema([]), configurations: [])
                } catch {
                    AppLogger.log(.error, category: "App", "Failed to create empty schema ModelContainer: \(error)")
                    return nil
                }
            }
        }
    }

    private static func storeURL(for scope: DataScope) -> URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let storageDirectoryURL = appSupportURL.appendingPathComponent("SwiftDataScopes", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: storageDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            AppLogger.log(.error, category: "App", "Failed to create scoped SwiftData directory: \(error.localizedDescription)")
            return nil
        }
        return storageDirectoryURL.appendingPathComponent(scope.storeFileName, isDirectory: false)
    }

    private static func storeExists(for scope: DataScope) -> Bool {
        guard let storeURL = storeURL(for: scope) else { return false }
        return FileManager.default.fileExists(atPath: storeURL.path)
    }

    private static func makeLegacyDefaultModelContainer() -> ModelContainer? {
        let schema = AppSchema.create()
        let legacyConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [legacyConfiguration])
        } catch {
            AppLogger.log(.warning, category: "App", "Legacy SwiftData container unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    private func migrateExistingStoresIfNeeded(
        into targetContainer: ModelContainer,
        targetScope: DataScope,
        currentScope: DataScope
    ) {
        guard case .user = targetScope else { return }
        guard Self.exportedModelCount(in: targetContainer) == 0 else { return }
        let targetRepository = DataRepository(
            modelContext: targetContainer.mainContext,
            modelContainer: targetContainer
        )

        let sourceContainers = candidateMigrationSources(
            for: targetScope,
            currentScope: currentScope
        )

        for source in sourceContainers {
            guard Self.exportedModelCount(in: source.container) > 0 else { continue }

            let sourceRepository = DataRepository(
                modelContext: source.container.mainContext,
                modelContainer: source.container
            )

            do {
                let payload = try sourceRepository.exportAllData()
                try targetRepository.importAllData(payload)
                logger.info("Migrated data into user-scoped store from \(source.label, privacy: .public)")
                return
            } catch {
                logger.error("Failed to migrate data from \(source.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func candidateMigrationSources(
        for targetScope: DataScope,
        currentScope: DataScope
    ) -> [(label: String, container: ModelContainer)] {
        var sources: [(label: String, container: ModelContainer)] = []

        if let legacyContainer = Self.makeLegacyDefaultModelContainer() {
            sources.append(("legacy_default", legacyContainer))
        }

        if case .guest = currentScope,
           case .user = targetScope,
           let guestContainer = Self.makeModelContainer(for: .guest) {
            sources.append(("guest_scope", guestContainer))
        }

        return sources
    }

    private static func exportedModelCount(in container: ModelContainer) -> Int {
        let repository = DataRepository(
            modelContext: container.mainContext,
            modelContainer: container
        )
        guard
            let payload = try? repository.exportAllData(),
            let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let models = json["models"] as? [[String: Any]]
        else {
            return 0
        }
        return models.count
    }
    
    private func triggerBackgroundBackup() {
        guard appState.isBackupEnabled,
              appState.isAutoBackupEnabled,
              let diContainer = diContainer else { return }

        Task {
            let policy = AutoBackupPolicy.everyTwentyFourHours
            let versions = await diContainer.backupManager.listBackupVersions()
            let latestAutoBackupDate = versions.first(where: { !$0.isPinned })?.date
            guard policy.shouldRun(lastBackupDate: latestAutoBackupDate, now: Date()) else {
                return
            }

            do {
                try await diContainer.backupManager.backupNow()
            } catch {
                AppLogger.log(.error, category: "App", "Background backup failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func presentRestoreFlowIfNeeded() async {
        guard let diContainer, let activeModelContainer else { return }

        let localDataCount = Self.exportedModelCount(in: activeModelContainer)
        let latestBackupInfo = await diContainer.backupManager.lastBackupInfo()
        let recoveryDecision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: appState.lifecycle,
                hasCompletedOnboarding: lifecycleUseCase?.checkOnboardingStatus() ?? false,
                didLocalStoreExistBeforeLaunch: activeScopeStoreExistedBeforeBinding,
                localDataCount: localDataCount,
                latestBackupInfo: latestBackupInfo
            )
        )

        guard recoveryDecision.shouldPresentRestore else { return }
        appState.isICloudAvailable = await diContainer.backupManager.isAvailable()
        appState.lastBackupDate = latestBackupInfo?.date
        appState.lifecycle = .restoring
    }

    @MainActor
    private func unlockWithBiometricsIfEnabled() async -> Bool {
        guard appState.isAppLockEnabled, appState.isBiometricUnlockEnabled, !isBiometricUnlockInProgress else {
            return false
        }
        isBiometricUnlockInProgress = true
        defer { isBiometricUnlockInProgress = false }
        let success = await AppLockBiometricAuth.authenticate(reason: "Unlock access to app data")
        if success {
            appState.isAppLocked = false
        }
        return success
    }
}
