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
import CryptoKit

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

private enum DataScope: Equatable {
    case guest
    case user(id: String)

    var storeConfigurationName: String {
        switch self {
        case .guest:
            return "millio_guest"
        case .user(let id):
            return "millio_user_\(Self.hash(id))"
        }
    }

    var storeFileName: String {
        "\(storeConfigurationName).store"
    }

    static func current(isAuthenticated: Bool, user: AuthUser?) -> DataScope {
        guard
            isAuthenticated,
            let rawUserID = user?.id.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawUserID.isEmpty
        else {
            return .guest
        }
        return .user(id: rawUserID)
    }

    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@main
struct millioApp: App {
    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var firebaseDelegate
    @State private var appState = AppState()
    @State private var diContainer: DIContainer?
    @State private var lifecycleUseCase: AppLifecycleUseCase?
    @State private var financeStartupWarmupUseCase: FinanceStartupWarmupUseCase?
    @State private var authManager = AuthManager()
    @State private var toastCenter = ToastCenter()
    @State private var isBiometricUnlockInProgress = false
    @State private var activeDataScope: DataScope = .guest
    @State private var activeModelContainer: ModelContainer?
    @State private var didRestoreAuthSession = false
    @State private var backendRuntime: BackendSessionRuntime?
    private let appLockCoordinator = AppLockLifecycleCoordinator()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "App")

    init() {
        Self.registerFeatures()
        let initialScope = DataScope.guest
        _activeDataScope = State(initialValue: initialScope)
        _activeModelContainer = State(initialValue: Self.makeModelContainer(for: initialScope))
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
                .environment(\.locale, appState.selectedLanguage.locale ?? Locale.current)
                .task(id: activeDataScope) {
                    await initializeApp(
                        container: container,
                        restoreSession: !didRestoreAuthSession
                    )

                    if !didRestoreAuthSession {
                        didRestoreAuthSession = true
                    }

                    // Восстанавливаем расписание уведомлений, если они включены
                    if appState.isDailyReminderEnabled {
                        await NotificationManager.shared.scheduleDailyReminder(using: SettingsManager.shared.dailyReminderSettings)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    triggerBackgroundBackup()
                    appLockCoordinator.handleWillResignActive(appState: appState)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    Task { @MainActor in
                        // Обновляем статус подписки при возврате из фона
                        await SubscriptionManager.shared.checkSubscriptionStatus()
                        appState.applySubscriptionSnapshot(SubscriptionManager.shared.snapshot)
                        CurrencyWidgetSyncService.bootstrapFromStandardDefaults()
                        await appLockCoordinator.handleDidBecomeActive(
                            appState: appState,
                            unlockWithBiometrics: unlockWithBiometricsIfEnabled
                        )

                        await financeStartupWarmupUseCase?.warmupIfNeeded()
                    }
                }
                .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated && appState.isGuestModeEnabled {
                        appState.isGuestModeEnabled = false
                    }
                    Task { @MainActor in
                        await switchToDataScopeIfNeeded(for: authManager.currentUser)
                    }
                }
                .onChange(of: authManager.currentUser?.id) { _, _ in
                    Task { @MainActor in
                        await switchToDataScopeIfNeeded(for: authManager.currentUser)
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
    private func initializeApp(container: ModelContainer, restoreSession: Bool) async {
        let start = DispatchTime.now()
        let backendRuntime = await resolveBackendRuntimeIfNeeded()

        appLockCoordinator.enforceLockStateOnLaunch(appState: appState, hasPin: AppLockPinStore.shared.hasPin())

        // Фичи уже зарегистрированы при создании ModelContainer
        
        // Используем DIContainer для создания зависимостей
        let diStart = DispatchTime.now()
        let container = DIContainer.create(
            appState: appState,
            modelContainer: container,
            backendRuntime: backendRuntime
        )
        self.diContainer = container
        authManager.configure(service: container.authService)
        authManager.configure(toastCenter: toastCenter)
        authManager.configure(onSessionChanged: { user in
            await switchToDataScopeIfNeeded(for: user)
        })
        let apiClientFactory = APIClientFactory(runtime: backendRuntime)
        await MarketAPIClient.shared.configure(
            authService: container.authService,
            configurationProvider: apiClientFactory.authConfigurationProvider()
        )
        self.financeStartupWarmupUseCase = FinanceStartupWarmupUseCase(
            modelContext: container.modelContainer.mainContext
        )
        logger.info("DIContainer.create finished in \(Double(DispatchTime.now().uptimeNanoseconds - diStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        
        // Создаем UseCase через DI Container
        let useCase = AppLifecycleUseCase(
            appState: appState,
            backupManager: container.backupManager
        )
        
        self.lifecycleUseCase = useCase
        let initStart = DispatchTime.now()
        await useCase.initialize()
        if restoreSession {
            await authManager.restoreSession()
        }
        logger.info("AppLifecycleUseCase.initialize finished in \(Double(DispatchTime.now().uptimeNanoseconds - initStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        logger.info("initializeApp finished in \(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        
        Task { @MainActor in
            await SubscriptionManager.shared.checkSubscriptionStatus()
            appState.applySubscriptionSnapshot(SubscriptionManager.shared.snapshot)
            CurrencyWidgetSyncService.bootstrapFromStandardDefaults()

            await appLockCoordinator.handleDidBecomeActive(
                appState: appState,
                unlockWithBiometrics: unlockWithBiometricsIfEnabled
            )

            await financeStartupWarmupUseCase?.warmupIfNeeded()
        }
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
                selectedEndpoint: BackendEndpoint(region: .de, baseURL: URL(string: "https://api.udzutech.com/api/v1")!),
                preferredEndpoint: BackendEndpoint(region: .de, baseURL: URL(string: "https://api.udzutech.com/api/v1")!),
                fallbackActivated: false,
                forcedOverride: false
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
    private func switchToDataScopeIfNeeded(for user: AuthUser?) async {
        let targetScope = DataScope.current(
            isAuthenticated: authManager.isAuthenticated,
            user: user
        )
        guard targetScope != activeDataScope else { return }

        let targetContainer = Self.makeModelContainer(for: targetScope)
        if let targetContainer {
            migrateLegacyStoreIfNeeded(
                into: targetContainer,
                targetScope: targetScope
            )
        }

        activeDataScope = targetScope
        activeModelContainer = targetContainer
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
    private func migrateLegacyStoreIfNeeded(into targetContainer: ModelContainer, targetScope: DataScope) {
        guard case .user = targetScope else { return }
        guard Self.exportedModelCount(in: targetContainer) == 0 else { return }
        guard let legacyContainer = Self.makeLegacyDefaultModelContainer() else { return }
        guard Self.exportedModelCount(in: legacyContainer) > 0 else { return }

        let legacyRepository = DataRepository(
            modelContext: legacyContainer.mainContext,
            modelContainer: legacyContainer
        )
        let targetRepository = DataRepository(
            modelContext: targetContainer.mainContext,
            modelContainer: targetContainer
        )

        do {
            let payload = try legacyRepository.exportAllData()
            try targetRepository.importAllData(payload)
            logger.info("Migrated legacy SwiftData store to user-scoped store")
        } catch {
            logger.error("Failed to migrate legacy SwiftData store: \(error.localizedDescription, privacy: .public)")
        }
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
              let diContainer = diContainer else { return }

        Task {
            let policy = AutoBackupPolicy.everyThreeDays
            let latestInfo = await diContainer.backupManager.lastBackupInfo()
            guard policy.shouldRun(lastBackupDate: latestInfo?.date, now: Date()) else {
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
