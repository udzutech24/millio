//
//  millioApp.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData
import UIKit
import SQLite3
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

/// Идентичность корневого дерева: меняется при смене языка ИЛИ скоупа данных.
/// Смена любой компоненты пересоздаёт RootTabView и его VM на актуальном modelContext.
private struct RootSceneIdentity: Hashable {
    let language: UUID
    let scope: Int
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
    // A2 (фикс race guest→user): токен скоупа входит в .id корневого дерева.
    // Бампится в rebindDataScope ПОСЛЕ свопа контейнера → SwiftUI пересоздаёт RootTabView
    // и его FinanceViewModel/CashflowViewModel на новом modelContext (иначе VM навсегда
    // остаются на guest-контейнере, снятом в let при первом монтировании).
    @State private var scopeIdentityToken: Int = 0
    // Оверлей «Переключение профиля…» на время рантайм-смены скоупа (login/logout/force-signout).
    @State private var isSwitchingScope = false
    // Track B: оверлей «Восстанавливаю данные…» на время merge guest→user (reconciliation).
    @State private var isReconciling = false
    @State private var scopeReconciliationService = ScopeReconciliationService()
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
        if runtimeEnvironment.isScreenshotMode {
            let appState = AppState()
            appState.isGuestModeEnabled = true
            appState.isAppLocked = false
            appState.lifecycle = .ready
            appState.subscriptionAccessSource = .subscription
            // Locale-aware currency for screenshots: EN → USD, others → RUB (default)
            if (Locale.preferredLanguages.first ?? "").hasPrefix("en") {
                appState.primaryCurrencyCode = "USD"
            }
            // Show backup as enabled so the backup screen looks meaningful
            appState.isBackupEnabled = true
            appState.isAutoBackupEnabled = true
            appState.isICloudAvailable = true
            _appState = State(initialValue: appState)
        } else if runtimeEnvironment.isUITesting {
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
                    // .id внутри ZStack: при бампе scopeIdentityToken пересоздаётся только
                    // контентная группа (на новом modelContainer), а оверлей-sibling переживает
                    // пересоздание и продолжает перекрывать мигание данных.
                    .id(RootSceneIdentity(language: appState.languageRefreshToken, scope: scopeIdentityToken))

                    if isSwitchingScope {
                        ScopeSwitchOverlayView()
                            .zIndex(10)
                    }

                    if isReconciling {
                        ScopeSwitchOverlayView(messageKey: "reconciliation.overlay.restoring")
                            .zIndex(11)
                    }
                }
                .preferredColorScheme(.dark)
                .environment(appState)
                .environment(authManager)
                .environment(toastCenter)
                .modelContainer(container)
                .environment(\.diContainer, diContainer)
                .environment(\.appRefreshCoordinator, appRefreshCoordinator)
                .environment(
                    \.locale,
                    LocalizationSupport.resolvedLocale(
                        for: appState.selectedLanguage,
                        fallbackLocale: .current
                    )
                )
                .task {
                    guard !runtimeEnvironment.isUITesting else { return }
                    if runtimeEnvironment.isScreenshotMode {
                        await ScreenshotDataSeeder.seed(into: container.mainContext)
                        return
                    }
                    await startupCoordinator.runColdStartIfNeeded {
                        await initializeColdStart(using: container)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    triggerBackgroundBackup()
                    appLockCoordinator.handleWillResignActive(appState: appState)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    guard !runtimeEnvironment.isUITesting, !runtimeEnvironment.isScreenshotMode else { return }
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
                    if url.pathExtension == "millio-backup" {
                        appState.pendingIncomingBackupURL = url
                    } else {
                        AppWidgetDeepLinkHandler.handle(url: url, appState: appState)
                    }
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
            backendRuntime: backendRuntime,
            scopeIdentifier: activeDataScope.storeConfigurationName
        )
        applyDependencyBinding(binding, backendRuntime: backendRuntime)

        let useCase = AppLifecycleUseCase(
            appState: appState,
            backupManager: binding.container.backupManager
        )
        
        self.lifecycleUseCase = useCase
        let initStart = DispatchTime.now()
        // A1 (фикс race guest→user): сессия восстанавливается и скоуп синхронизируется
        // ДО перевода приложения в .ready. lifecycle = .ready выставляется внутри
        // useCase.initialize() из замыкания onScopeResolved — уже ПОСЛЕ свопа контейнера,
        // поэтому RootTabView (и его FinanceViewModel/CashflowViewModel) монтируется сразу
        // на финальном (user) контейнере, а не на guest с последующим пересозданием.
        // presentRestoreFlow по-прежнему выполняется последним и видит lifecycle == .ready
        // (LaunchRecoveryPolicy требует .ready) — порядок restore-флоу сохранён (риск №5).
        await authManager.restoreSession()
        AppLogger.log(.info, category: "App", "Auth restored — isAuthenticated=\(authManager.isAuthenticated) userID=\(authManager.currentUser?.id ?? "nil")")
        await synchronizeDataScope(with: authManager.currentUser) {
            await useCase.initialize()
        }
        AppLogger.log(.info, category: "App", "Active scope after sync: \(activeDataScope.storeConfigurationName), storeExisted=\(activeScopeStoreExistedBeforeBinding)")
        logger.info("AppLifecycleUseCase.initialize finished in \(Double(DispatchTime.now().uptimeNanoseconds - initStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        logger.info("initializeColdStart finished in \(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")

        #if DEBUG
        await debugImportBackupIfNeeded()
        #endif

        await runPostStartupRefreshes()
        await scheduleDailyReminderIfNeeded()
    }

    @MainActor
    private func prepareDependencyBinding(
        for modelContainer: ModelContainer,
        backendRuntime: BackendSessionRuntime,
        scopeIdentifier: String
    ) async -> AppDependencyBinding {
        let diStart = DispatchTime.now()
        let container = DIContainer.create(
            appState: appState,
            modelContainer: modelContainer,
            backendRuntime: backendRuntime,
            scopeIdentifier: scopeIdentifier
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
            CrashReporting.setUserID(user?.id)
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
    private func synchronizeDataScope(
        with user: AuthUser?,
        onScopeResolved: (@MainActor () async -> Void)? = nil
    ) async {
        if authManager.isAuthenticated && appState.isGuestModeEnabled {
            appState.isGuestModeEnabled = false
        }

        let targetScope = DataScope.current(
            isAuthenticated: authManager.isAuthenticated,
            user: user
        )

        // Auth/Scope resilience: если auth restore вернул .guest (сбой сети или токена),
        // но в кэше есть user ID и соответствующий стор существует на диске —
        // открываем пользовательский стор вместо пустого гостевого.
        // Кэш сбрасывается при явном logout (ScopeCache.clearUserID()), поэтому
        // намеренный выход не перехватывается этой логикой.
        let resolvedScope: DataScope
        if case .guest = targetScope,
           let cachedUserID = ScopeCache.lastKnownUserID() {
            let cachedScope = DataScope.user(id: cachedUserID)
            if Self.storeExists(for: cachedScope) {
                AppLogger.log(.warning, category: "App",
                    "Auth restore returned guest but cached user store exists — using cached scope '\(cachedScope.storeConfigurationName)'")
                resolvedScope = cachedScope
            } else {
                resolvedScope = targetScope
            }
        } else {
            resolvedScope = targetScope
        }

        await startupCoordinator.switchScopeIfNeeded(to: resolvedScope) { resolvedScope in
            let switched = await rebindDataScope(to: resolvedScope)
            if switched, case .user = resolvedScope {
                ScopeCache.save(resolvedScope)
            }
            return switched
        }
        // Cold start: помечаем .ready только когда контейнер уже свопнут (RootTabView
        // смонтируется на финальном контейнере), но ДО presentRestoreFlow — политике
        // восстановления нужен lifecycle == .ready. В рантайме (login/logout) onScopeResolved
        // == nil, порядок не меняется.
        await onScopeResolved?()
        // Track B: reconciliation guest→user ПОСЛЕ свопа контейнера и .ready, но ДО restore-флоу —
        // чтобы restore видел уже слитый (непустой) user-стор. Не блокирует .ready (идёт off-main,
        // детектор-скрининг дёшев при отсутствии расхождения).
        await reconcileScopeIfNeeded(resolvedScope: resolvedScope)
        await presentRestoreFlowIfNeeded()
    }

    /// Track B: сливает данные, записанные в guest-стор после first-login, в канонический user-стор.
    /// Идемпотентно (done-маркер по scope), дёшево при отсутствии расхождения (детектор-скрининг).
    @MainActor
    private func reconcileScopeIfNeeded(resolvedScope: DataScope) async {
        guard case .user = resolvedScope else { return }
        guard !ScopeMergeMarker.isDone(userScopeKey: resolvedScope.storeConfigurationName) else { return }
        guard let userContainer = activeModelContainer else { return }
        // Гость — источник merge. Нет гостевого стора → мержить нечего.
        guard Self.storeExists(for: .guest), let guestContainer = Self.makeModelContainer(for: .guest) else { return }

        let usedFallback = ScopeStoreOpenTracker.shared.usedFallback(resolvedScope.storeConfigurationName)
            || ScopeStoreOpenTracker.shared.usedFallback(DataScope.guest.storeConfigurationName)

        let outcome = await scopeReconciliationService.reconcile(
            userContainer: userContainer,
            userScope: resolvedScope,
            guestContainer: guestContainer,
            userStoreURL: Self.storeURL(for: resolvedScope),
            guestStoreURL: Self.storeURL(for: .guest),
            usedFallbackOpen: usedFallback,
            onWillMerge: { withAnimation(AppAnimation.standard) { isReconciling = true } }
        )

        if case .merged(let report) = outcome {
            // Пересоздаём дерево на слитых данных: FinanceViewModel/CashflowViewModel перечитают user-стор.
            scopeIdentityToken &+= 1
            if report.accountsAdded + report.transactionsAdded > 0 {
                let message = String(
                    format: L("reconciliation.summary.restored",
                              defaultValue: "Data restored: %1$lld accounts, %2$lld transactions"),
                    report.accountsAdded, report.transactionsAdded
                )
                toastCenter.show(message: message)
            }
            // Оверлей «висит» ещё кадр, пока пересоздаётся дерево, затем гаснет (как ScopeSwitch).
            if isReconciling {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Self.scopeSwitchOverlayLingerMilliseconds))
                    withAnimation(AppAnimation.easeOut) { isReconciling = false }
                }
            }
        } else if isReconciling {
            withAnimation(AppAnimation.easeOut) { isReconciling = false }
        }
    }

    @MainActor
    private func rebindDataScope(to targetScope: DataScope) async -> Bool {
        guard targetScope != activeDataScope else { return false }

        // Рантайм-смена скоупа (login/logout/force-signout) идёт с уже смонтированным
        // RootTabView — показываем переходный оверлей, пока пересоздаётся дерево (риск №7).
        // На cold start lifecycle ещё .launching (A1) → оверлей не нужен, виден splash.
        let isRuntimeSwap = appState.lifecycle == .ready
        if isRuntimeSwap {
            withAnimation(AppAnimation.standard) { isSwitchingScope = true }
        }

        let didTargetStoreExistBeforeBinding = Self.storeExists(for: targetScope)
        let targetContainer = Self.makeModelContainer(for: targetScope)
        if let targetContainer {
            migrateExistingStoresIfNeeded(
                into: targetContainer,
                targetScope: targetScope,
                currentScope: activeDataScope
            )
        }

        guard !Task.isCancelled else {
            if isRuntimeSwap { isSwitchingScope = false }
            return false
        }

        let binding: AppDependencyBinding?
        if let backendRuntime, let targetContainer {
            let preparedBinding = await prepareDependencyBinding(
                for: targetContainer,
                backendRuntime: backendRuntime,
                scopeIdentifier: targetScope.storeConfigurationName
            )
            guard !Task.isCancelled else {
                if isRuntimeSwap { isSwitchingScope = false }
                return false
            }
            binding = preparedBinding
        } else {
            binding = nil
        }

        activeDataScope = targetScope
        activeModelContainer = targetContainer
        // Если стор был пересоздан из-за смены схемы (есть .bak-файл), считаем что
        // "старого стора не было" — это позволяет автоматически предложить restore из iCloud.
        #if DEBUG
        let storeWasRebuilt = Self.bakStoreExists(for: targetScope)
        activeScopeStoreExistedBeforeBinding = didTargetStoreExistBeforeBinding && !storeWasRebuilt
        #else
        activeScopeStoreExistedBeforeBinding = didTargetStoreExistBeforeBinding
        #endif

        if let backendRuntime, let binding {
            applyDependencyBinding(binding, backendRuntime: backendRuntime)
        }

        // Бамп ПОСЛЕ свопа контейнера и применения зависимостей: .id меняется →
        // RootTabView и его FinanceViewModel/CashflowViewModel пересоздаются на новом
        // modelContext. Отмена in-flight задач старых VM происходит в их deinit при
        // teardown старого дерева (риск №3); старый контейнер жив по ARC до дезаллокации VM.
        scopeIdentityToken &+= 1

        if isRuntimeSwap {
            // Даём кадр новому дереву на первичный рендер, затем снимаем оверлей.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Self.scopeSwitchOverlayLingerMilliseconds))
                withAnimation(AppAnimation.easeOut) { isSwitchingScope = false }
            }
        }
        return true
    }

    // Задержка снятия оверлея смены профиля: даёт пересозданному дереву кадр на рендер,
    // чтобы не мигнуть пустым экраном между teardown старого RootTabView и рендером нового.
    private static let scopeSwitchOverlayLingerMilliseconds = 350

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

    #if DEBUG
    @MainActor
    private func debugImportBackupIfNeeded() async {
        let triggerURL = URL(fileURLWithPath: "/tmp/millio-debug-import.json")
        guard FileManager.default.fileExists(atPath: triggerURL.path),
              let data = try? Data(contentsOf: triggerURL),
              let repo = diContainer?.dataRepository else { return }
        do {
            try await repo.clearAllDataAsync()
            try await repo.importAllDataAsync(data)
            try? FileManager.default.removeItem(at: triggerURL)
            logger.info("DEBUG: backup import from /tmp/millio-debug-import.json succeeded")
        } catch {
            logger.error("DEBUG: backup import failed: \(error)")
        }
    }
    #endif

    private static func registerFeatures() {
        CurrencyFeatureRegistration.register()
        CardFeatureRegistration.register()
        CashbackFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
        UserSubscriptionsFeatureRegistration.register()
    }

    private static func makeModelContainer(for scope: DataScope) -> ModelContainer? {
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

        // schema не передаём в конфиг — AppMigrationPlan предоставляет актуальную схему.
        // SwiftData мигрирует существующие сторы (включая unversioned → V1 → V2) без потери данных.
        let modelConfiguration = ModelConfiguration(
            scope.storeConfigurationName,
            url: storeURL,
            cloudKitDatabase: .none
        )

        let storeAlreadyExists = FileManager.default.fileExists(atPath: storeURL.path)
        AppLogger.log(.info, category: "App", "Opening store '\(storeURL.lastPathComponent)' (existed=\(storeAlreadyExists)) scope=\(scope.storeConfigurationName)")

        do {
            let container = try AppMigrationPlan.makeContainer(configuration: modelConfiguration)
            AppLogger.log(.info, category: "App", "Store opened OK — path: \(storeURL.path)")
            return container
        } catch {
            // schema mismatch обрабатывается AppMigrationPlan; сюда попадаем при реальной коррупции.
            AppLogger.log(.error, category: "App", "Failed to open ModelContainer at \(storeURL.lastPathComponent): \(error)")

            if storeAlreadyExists {
                #if DEBUG
                let schema = AppSchema.create()
                // Track B (митигация B1b №6): стор пересоздан → reconciliation не фиксирует done.
                ScopeStoreOpenTracker.shared.markFallback(scope.storeConfigurationName)
                return Self.rebuildStorePreservingData(at: storeURL, schema: schema, scope: scope)
                #else
                // Migration plan failed on an existing store (e.g. schema version mismatch after
                // AppSchemaV2 was redefined). As a last resort, try opening without a migration plan
                // — SwiftData may still be able to open the store if the on-disk layout matches the
                // current schema close enough. If this also fails, we destroy the store and create
                // fresh so the user can restore from backup rather than being stuck forever.
                AppLogger.log(.error, category: "App", "Migration plan failed on existing store — attempting no-plan fallback")
                let fallbackConfig = ModelConfiguration(
                    scope.storeConfigurationName,
                    schema: AppSchema.create(),
                    url: storeURL,
                    cloudKitDatabase: .none
                )
                if let fallback = try? ModelContainer(for: AppSchema.create(), configurations: [fallbackConfig]) {
                    AppLogger.log(.warning, category: "App", "Opened store without migration plan — data may be partially readable")
                    // Track B (митигация B1b №6): partially readable → reconciliation не фиксирует done.
                    ScopeStoreOpenTracker.shared.markFallback(scope.storeConfigurationName)
                    return fallback
                }
                // Store is unrecoverable: rename to .corrupt and create fresh so the user can at
                // least launch and trigger a restore from iCloud backup.
                AppLogger.log(.error, category: "App", "Store unrecoverable — renaming to .corrupt and creating fresh store")
                let corruptURL = storeURL.deletingPathExtension().appendingPathExtension("corrupt.store")
                try? FileManager.default.removeItem(at: corruptURL)
                try? FileManager.default.moveItem(at: storeURL, to: corruptURL)
                let freshConfig = ModelConfiguration(
                    scope.storeConfigurationName,
                    schema: AppSchema.create(),
                    url: storeURL,
                    cloudKitDatabase: .none
                )
                if let fresh = try? ModelContainer(for: AppSchema.create(), configurations: [freshConfig]) {
                    AppLogger.log(.warning, category: "App", "Fresh store created after corruption — user should restore from backup")
                    return fresh
                }
                AppLogger.log(.error, category: "App", "Failed to create fresh store after corruption — showing error screen")
                return nil
                #endif
            }

            // Стор не существовал — новый пользователь или первый запуск.
            // Никогда не используем in-memory: данные должны жить на диске.
            // Пробуем создать чистый стор без плана миграции (нечего мигрировать).
            let freshConfig = ModelConfiguration(
                scope.storeConfigurationName,
                schema: AppSchema.create(),
                url: storeURL,
                cloudKitDatabase: .none
            )
            do {
                let fresh = try ModelContainer(for: AppSchema.create(), configurations: [freshConfig])
                AppLogger.log(.info, category: "App", "Created fresh on-disk store at \(storeURL.lastPathComponent)")
                return fresh
            } catch {
                AppLogger.log(.error, category: "App", "Failed to create fresh store: \(error) — showing error screen")
                return nil
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

    #if DEBUG
    private static func bakStoreExists(for scope: DataScope) -> Bool {
        guard let storeURL = storeURL(for: scope) else { return false }
        let bakURL = storeURL.deletingPathExtension().appendingPathExtension("bak.store")
        return FileManager.default.fileExists(atPath: bakURL.path)
    }
    #endif

    #if DEBUG
    /// Переименовывает несовместимый стор в .bak и создаёт пустой новый.
    /// Используется только в DEBUG: при смене схемы данные на девайсе разработчика теряются,
    /// но приложение запускается корректно. Для восстановления — бэкап в iCloud.
    private static func rebuildStorePreservingData(at storeURL: URL, schema: Schema, scope: DataScope) -> ModelContainer? {
        let backupURL = storeURL.deletingPathExtension().appendingPathExtension("bak.store")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: storeURL, to: backupURL)

        AppLogger.log(.error, category: "Schema", """
        ⚠️⚠️⚠️ DATA LOSS: Store rebuilt from scratch!
        Scope: \(scope.storeConfigurationName)
        Old store backed up to: \(backupURL.path)
        To recover: copy .bak.store → rename to .store → relaunch.
        Root cause: likely a @Model missing from AppSchemaCurrent.models or AppMigrationPlan.
        Run SchemaConsistencyTests to detect divergence.
        """)

        let newConfig = ModelConfiguration(scope.storeConfigurationName, schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try? ModelContainer(for: schema, configurations: [newConfig])
    }
    #endif

    private static func makeLegacyDefaultModelContainer() -> ModelContainer? {
        let legacyConfiguration = ModelConfiguration(
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try AppMigrationPlan.makeContainer(configuration: legacyConfiguration)
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
        // nil (fetch failed) → неизвестно → не мигрируем, чтобы не затереть существующие данные
        guard let targetCount = Self.exportedModelCount(in: targetContainer), targetCount == 0 else { return }
        let targetRepository = DataRepository(
            modelContext: targetContainer.mainContext,
            modelContainer: targetContainer
        )

        let sourceContainers = candidateMigrationSources(
            for: targetScope,
            currentScope: currentScope
        )

        for source in sourceContainers {
            // nil → источник неизвестен → пропускаем (не копируем из неопределённого состояния)
            guard let sourceCount = Self.exportedModelCount(in: source.container), sourceCount > 0 else { continue }

            let sourceRepository = DataRepository(
                modelContext: source.container.mainContext,
                modelContainer: source.container
            )

            do {
                let payload = try sourceRepository.exportAllData()
                try targetRepository.importAllData(payload)
                logger.info("Migrated data into \(targetScope.storeConfigurationName, privacy: .public) from \(source.label, privacy: .public)")
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

    private static let autoRestoreTimeoutSeconds: TimeInterval = 30
    private static let autoRestoreMaxAttempts = 2
    private static let autoRestoreAttemptsKey = "autoRestoreAttemptCount"

    private static func exportedModelCount(in container: ModelContainer) -> Int? {
        // Первичный путь: прямое чтение SQLite — обходит timing issue SwiftData, где
        // ModelContext возвращает 0 из только что открытого контейнера до того как SwiftUI
        // его инициализирует через .modelContainer(). SQLite WAL-режим безопасен для
        // параллельного чтения, пока ModelContainer держит тот же файл открытым.
        if let url = container.configurations.first?.url,
           let count = sqliteUserDataCount(at: url) {
            return count
        }
        // Fallback: путь через ModelContext (корректен после инициализации SwiftUI-окружения)
        let freshContext = ModelContext(container)
        let repository = DataRepository(
            modelContext: freshContext,
            modelContainer: container
        )
        guard
            let payload = try? repository.exportAllData(),
            let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let models = json["models"] as? [[String: Any]]
        else {
            AppLogger.log(.warning, category: "App", "exportedModelCount: fetch failed, count uncertain")
            return nil
        }
        return models.count
    }

    /// Прямой подсчёт строк в SQLite-сторе, минуя SwiftData.
    /// Считает все строки в пользовательских таблицах (Z-префикс, не системные Z_METADATA и т.п.).
    private static func sqliteUserDataCount(at url: URL) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }

        var tableNames: [String] = []
        var listStmt: OpaquePointer?
        // Пользовательские таблицы: Z-префикс, исключая системные Z_PRIMARYKEY / Z_METADATA / Z_MODELCACHE
        let listSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z%' AND name NOT LIKE 'Z\\_%' ESCAPE '\\'"
        if sqlite3_prepare_v2(db, listSQL, -1, &listStmt, nil) == SQLITE_OK {
            while sqlite3_step(listStmt) == SQLITE_ROW, let ptr = sqlite3_column_text(listStmt, 0) {
                tableNames.append(String(cString: ptr))
            }
        }
        sqlite3_finalize(listStmt)

        var total = 0
        for tableName in tableNames {
            var countStmt: OpaquePointer?
            let countSQL = "SELECT COUNT(*) FROM \"\(tableName)\""
            if sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil) == SQLITE_OK,
               sqlite3_step(countStmt) == SQLITE_ROW {
                total += Int(sqlite3_column_int(countStmt, 0))
            }
            sqlite3_finalize(countStmt)
        }

        return total
    }
    
    private func triggerBackgroundBackup() {
        guard appState.isBackupEnabled,
              appState.isAutoBackupEnabled,
              let diContainer = diContainer else { return }
        guard !appState.isRestoreInProgress else { return }

        // Не бекапим пустой или неизвестный стор — неизвестное состояние (nil) опаснее пропущенного бэкапа.
        guard let container = activeModelContainer,
              let count = Self.exportedModelCount(in: container),
              count > 0 else { return }

        Task {
            let policy = AutoBackupPolicy.everySixHours
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

        guard let localDataCount = Self.exportedModelCount(in: activeModelContainer) else {
            AppLogger.log(.warning, category: "App", "LaunchRecovery: count uncertain, skipping restore")
            return
        }
        // Если данные есть — счётчик авто-восстановления сбрасываем, чтобы не застревать
        // в ручном restore после двух неудачных попыток (например, при passphrase-бэкапе).
        if localDataCount > 0 {
            UserDefaults.standard.set(0, forKey: Self.autoRestoreAttemptsKey)
        }
        let latestBackupInfo = await diContainer.backupManager.lastBackupInfo()
        let input = LaunchRecoveryPolicy.Input(
            lifecycle: appState.lifecycle,
            hasCompletedOnboarding: lifecycleUseCase?.checkOnboardingStatus() ?? false,
            didLocalStoreExistBeforeLaunch: activeScopeStoreExistedBeforeBinding,
            localDataCount: localDataCount,
            latestBackupInfo: latestBackupInfo
        )
        let recoveryDecision = LaunchRecoveryPolicy.evaluate(input)
        AppLogger.log(.info, category: "App", "LaunchRecovery: localCount=\(localDataCount) storeExisted=\(activeScopeStoreExistedBeforeBinding) backup=\(latestBackupInfo != nil) lifecycle=\(appState.lifecycle) → \(recoveryDecision)")

        guard recoveryDecision.shouldPresentRestore else { return }
        appState.isICloudAvailable = await diContainer.backupManager.isAvailable()
        appState.lastBackupDate = latestBackupInfo?.date

        // Если стор существовал, но данные исчезли (потеря при обновлении / миграции схемы) —
        // восстанавливаем последний бекап автоматически, без участия пользователя.
        if activeScopeStoreExistedBeforeBinding, latestBackupInfo != nil {
            let attempts = UserDefaults.standard.integer(forKey: Self.autoRestoreAttemptsKey)
            guard attempts < Self.autoRestoreMaxAttempts else {
                AppLogger.log(.warning, category: "App", "Auto-restore: лимит попыток исчерпан (\(attempts)), переходим к ручному restore")
                appState.lifecycle = .restoring
                return
            }
            UserDefaults.standard.set(attempts + 1, forKey: Self.autoRestoreAttemptsKey)
            appState.isRestoreInProgress = true
            appState.lifecycle = .autoRestoring
            Task {
                defer { Task { @MainActor in appState.isRestoreInProgress = false } }
                do {
                    // TODO(temp): заменить size-guard на preflight.modelCount > 0 когда появится preflightLatestBackup()
                    let versions = await diContainer.backupManager.listBackupVersions()
                    guard let latestVersion = versions.first, latestVersion.size >= 1024 else {
                        AppLogger.log(.warning, category: "App", "Auto-restore: нет валидных версий (пусто или < 1KB), переходим к ручному restore")
                        await MainActor.run { appState.lifecycle = .restoring }
                        return
                    }
                    try await withTaskTimeout(seconds: Self.autoRestoreTimeoutSeconds) {
                        try await diContainer.backupManager.restoreLatest(passphrase: nil)
                    }
                    UserDefaults.standard.set(0, forKey: Self.autoRestoreAttemptsKey)
                    AppLogger.log(.info, category: "App", "Auto-restore completed successfully")
                    await MainActor.run { appState.lifecycle = .ready }
                } catch {
                    CrashReporting.record(error: error)
                    AppLogger.log(.error, category: "App", "Auto-restore failed, falling back to manual: \(error.localizedDescription)")
                    await MainActor.run { appState.lifecycle = .restoring }
                }
            }
        } else {
            // Свежая установка с доступным бекапом — показываем экран выбора версии.
            appState.lifecycle = .restoring
        }
    }

    @MainActor
    private func unlockWithBiometricsIfEnabled() async -> Bool {
        guard appState.isAppLockEnabled, appState.isBiometricUnlockEnabled, !isBiometricUnlockInProgress else {
            return false
        }
        isBiometricUnlockInProgress = true
        defer { isBiometricUnlockInProgress = false }
        let success = await AppLockBiometricAuth.authenticate(reason: AppLockBiometricAuth.authenticationReason())
        if success {
            appState.isAppLocked = false
        }
        return success
    }
}
