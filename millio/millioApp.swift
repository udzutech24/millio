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
        let accountSnapshotBackfillCoordinator: AccountSnapshotBackfillCoordinator
        let historicalValuationMaintenance: HistoricalValuationProductionMaintenance
    }

    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var firebaseDelegate
    @State private var appState = AppState()
    @State private var diContainer: DIContainer?
    @State private var lifecycleUseCase: AppLifecycleUseCase?
    @State private var financeStartupWarmupUseCase: FinanceStartupWarmupUseCase?
    @State private var portfolioSymbolsSyncService: PortfolioSymbolsSyncService?
    @State private var accountSnapshotBackfillCoordinator: AccountSnapshotBackfillCoordinator?
    @State private var historicalValuationMaintenance: HistoricalValuationProductionMaintenance?
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
    // Единственный владелец состояния launch-recovery: App-level @State переживает пересоздание
    // дерева по RootSceneIdentity, поэтому решение «recovery уже отработал для этого поколения
    // scope» не теряется при remount RestoreView (D1).
    @State private var launchRecoveryGate = LaunchRecoveryGate()
    // Оверлей «Переключение профиля…» на время рантайм-смены скоупа (login/logout/force-signout).
    @State private var isSwitchingScope = false
    // Track B: оверлей «Восстанавливаю данные…» на время merge guest→user (reconciliation).
    @State private var isReconciling = false
    @State private var scopeReconciliationService = ScopeReconciliationService()
    @State private var backendRuntime: BackendSessionRuntime?
    @State private var backendAvailabilityTask: Task<Void, Never>?
    @State private var startupCoordinator = StartupCoordinator(initialScope: .guest)
    @State private var appRefreshCoordinator = AppRefreshCoordinator()
    @State private var incomingStatementCoordinator: IncomingStatementCoordinator?
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
        if runtimeEnvironment.isScreenshotMode || runtimeEnvironment.isUnifiedEntryPerformanceMode {
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

                    BackendAvailabilityIndicator(
                        availability: appState.backendAvailability,
                        retry: { startBackendAvailabilityProbe() }
                    )
                    .zIndex(12)
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
                    if runtimeEnvironment.isScreenshotMode || runtimeEnvironment.isUnifiedEntryPerformanceMode {
                        if runtimeEnvironment.isUnifiedEntryPerformanceMode {
                            try? UnifiedEntryPerformanceFixtureSeeder.seed(into: container.mainContext)
                            // Dispatch after RootTabView is mounted; a value set during
                            // App initialization is not an observable deep-link event.
                            appState.pendingOpenCashflowIncome = true
                        } else {
                            await ScreenshotDataSeeder.seed(into: container.mainContext)
                        }
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
                    guard !runtimeEnvironment.isUITesting,
                          !runtimeEnvironment.isScreenshotMode,
                          !runtimeEnvironment.isUnifiedEntryPerformanceMode else { return }
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
                        presentNextIncomingStatementIfReady()

                        await financeStartupWarmupUseCase?.warmupIfNeeded()
                        await runHistoricalMaintenancePipeline()
                    }
                }
                .onOpenURL { url in
                    if url.pathExtension == "millio-backup" {
                        appState.pendingIncomingBackupURL = url
                    } else if IncomingStatementFileKind.allCases.map(\.filenameExtension).contains(url.pathExtension.lowercased()) {
                        handleIncomingStatementURL(url)
                    } else {
                        AppWidgetDeepLinkHandler.handle(url: url, appState: appState)
                    }
                }
                .onChange(of: appState.lifecycle) { _, _ in
                    presentNextIncomingStatementIfReady()
                }
                .onChange(of: appState.isAppLocked) { _, _ in
                    presentNextIncomingStatementIfReady()
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
    private func handleIncomingStatementURL(_ url: URL) {
        do {
            let coordinator = try resolvedIncomingStatementCoordinator()
            _ = try coordinator.stageDirectURL(url)
            presentNextIncomingStatementIfReady()
        } catch {
            // Financial filenames, amounts and source paths must never enter logs.
            AppLogger.log(.error, category: "StatementIngress", "Incoming statement rejected code=validation_failed")
        }
    }

    @MainActor
    private func presentNextIncomingStatementIfReady() {
        guard appState.pendingIncomingStatementItem == nil else { return }
        do {
            let coordinator = try resolvedIncomingStatementCoordinator()
            let readiness: IncomingStatementReadiness
            if appState.isAppLocked {
                readiness = .locked
            } else if appState.lifecycle != .ready || activeModelContainer == nil {
                readiness = .storeUnavailable
            } else if appState.isRestoreInProgress || isSwitchingScope || isReconciling {
                readiness = .modalBusy
            } else {
                readiness = .ready
            }
            appState.pendingIncomingStatementItem = try coordinator.nextItem(readiness: readiness)
        } catch {
            AppLogger.log(.error, category: "StatementIngress", "Statement inbox unavailable code=inbox_failed")
        }
    }

    @MainActor
    private func resolvedIncomingStatementCoordinator() throws -> IncomingStatementCoordinator {
        if let incomingStatementCoordinator { return incomingStatementCoordinator }
        let coordinator = try IncomingStatementCoordinator.appGroup()
        incomingStatementCoordinator = coordinator
        return coordinator
    }
    
    @MainActor
    private func initializeColdStart(using container: ModelContainer) async {
        let start = DispatchTime.now()
        let backendRuntime = await resolveBackendRuntimeIfNeeded()
        startBackendAvailabilityProbe()

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
        // Local scope must become usable without waiting for refresh-token network I/O. A saved
        // snapshot is enough for the resilience path; the authoritative refresh runs afterwards.
        let cachedUser = await authManager.restoreCachedSessionForResilience()
        AppLogger.log(.info, category: "App", "Local auth snapshot restored — isAuthenticated=\(authManager.isAuthenticated) hasUser=\(cachedUser != nil)")
        await synchronizeDataScope(with: authManager.currentUser) {
            // 6b Фаза 2 (фикс адверсариального ревью 2026-07-10): легаси→core миграция ДО .ready.
            // Агрегат «Общий баланс» стал core-only (FinanceTotalsService.calculateTotalsSnapshot) —
            // если FinanceViewModel монтируется раньше миграции, первый расчёт видит core пустым и
            // показывает «баланс ≈ 0» (ни мигратор, ни конвертер не публикуют FinanceEvent — авто-
            // пересчёта нет, transient держится до случайного триггера или рестарта). Здесь — на
            // финальном (пост-swap) контейнере, гарантированно до конструирования RootTabView/VM.
            guard await self.runLegacyAccountsMigrationIfNeeded() else { return }
            await useCase.initialize()
        }
        Task { @MainActor in
            await authManager.restoreSession()
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
        let accountSnapshotBackfillCoordinator = AccountSnapshotBackfillCoordinator(
            modelContainer: modelContainer
        )
        let historicalValuationMaintenance = HistoricalValuationProductionMaintenance(
            modelContainer: modelContainer,
            scopeID: scopeIdentifier
        )

        logger.info("DIContainer.create finished in \(Double(DispatchTime.now().uptimeNanoseconds - diStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        return AppDependencyBinding(
            container: container,
            financeWarmupUseCase: financeWarmupUseCase,
            portfolioSymbolsSyncService: portfolioSymbolsSyncService,
            accountSnapshotBackfillCoordinator: accountSnapshotBackfillCoordinator,
            historicalValuationMaintenance: historicalValuationMaintenance
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
        accountSnapshotBackfillCoordinator = binding.accountSnapshotBackfillCoordinator
        historicalValuationMaintenance = binding.historicalValuationMaintenance
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

        // Endpoint configuration is local and deterministic. Availability is intentionally
        // checked after local startup, so an outage cannot delay the usable SwiftData UI.
        let runtime = BackendStartupResolver(endpoints: resolvedEndpoints).resolveStaticRuntime()
        self.backendRuntime = runtime
        appState.applyBackendRuntime(runtime)
        return runtime
    }

    @MainActor
    private func startBackendAvailabilityProbe() {
        guard let runtime = backendRuntime else { return }
        backendAvailabilityTask?.cancel()
        appState.applyBackendAvailability(.checking)

        backendAvailabilityTask = Task { @MainActor in
            async let result = BackendAvailabilityProbe().check(endpoint: runtime.selectedEndpoint)
            async let deadline: Void = {
                try? await Task.sleep(for: .seconds(5))
            }()

            await deadline
            guard !Task.isCancelled else { return }
            if appState.backendAvailability == .checking {
                appState.applyBackendAvailability(.offline(.probeTimedOut))
            }

            let probeResult = await result
            guard !Task.isCancelled else { return }
            switch probeResult {
            case .success:
                // This changes availability only; it never triggers scope or navigation work.
                appState.applyBackendAvailability(.online)
            case .failure(let failure):
                if appState.backendAvailability != .online {
                    appState.applyBackendAvailability(.offline(failure))
                }
            }
        }
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

        // Watchdog (митигация B1b №7): если merge аномально затянулся, снимаем оверлей, чтобы
        // пользователь не завис на «Восстанавливаю данные…». Сам merge (off-main) при этом
        // продолжается и корректно завершится/выставит маркер — на данные watchdog не влияет.
        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.reconcileWatchdogSeconds))
            if isReconciling { withAnimation(AppAnimation.easeOut) { isReconciling = false } }
        }

        let outcome = await scopeReconciliationService.reconcile(
            userContainer: userContainer,
            userScope: resolvedScope,
            guestContainer: guestContainer,
            userStoreURL: Self.storeURL(for: resolvedScope),
            guestStoreURL: Self.storeURL(for: .guest),
            usedFallbackOpen: usedFallback,
            onWillMerge: { withAnimation(AppAnimation.standard) { isReconciling = true } }
        )
        watchdog.cancel()

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
        activeScopeStoreExistedBeforeBinding = didTargetStoreExistBeforeBinding

        if let backendRuntime, let binding {
            applyDependencyBinding(binding, backendRuntime: backendRuntime)

            // Триггер легаси→core self-heal-миграции на КАЖДОМ свопе контейнера, а не только на
            // cold-start-замыкании onScopeResolved (initializeColdStart:262). Async-своп на user через
            // onSessionChanged → synchronizeDataScope(onScopeResolved: nil) РАНЬШЕ миграцию не переигрывал:
            // cold-start резолвил guest (без легаси) и мигрировал его вхолостую, а user-стор со своими
            // легаси-записями и пустым ядром активировался здесь позже и оставался немигрированным навсегда
            // (progress/2026-07-11-migration-flag-restore-bug.md). Место — строго ПОСЛЕ applyDependencyBinding:
            // миграция читает diContainer.modelContainer, который тот только что переключил на новый scope
            // (до :541 ушло бы в старый контейнер). Повторный вызов в том же процессе (cold-start уже
            // мигрировал этот scope) — дешёвый no-op: один fetchCount(Account) + флаг-short-circuit.
            guard await runLegacyAccountsMigrationIfNeeded() else {
                if isRuntimeSwap { isSwitchingScope = false }
                return false
            }
        }

        // Бамп ПОСЛЕ свопа контейнера и применения зависимостей: .id меняется →
        // RootTabView и его FinanceViewModel/CashflowViewModel пересоздаются на новом
        // modelContext. Отмена in-flight задач старых VM происходит в их deinit при
        // teardown старого дерева (риск №3); старый контейнер жив по ARC до дезаллокации VM.
        scopeIdentityToken &+= 1
        // Смена scope = новое поколение recovery: ранее выданные токены становятся stale,
        // а для нового scope решение принимается заново.
        launchRecoveryGate.bumpGeneration()

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
    /// Watchdog reconciliation (Track B): максимальная длительность оверлея «Восстанавливаю данные…».
    private static let reconcileWatchdogSeconds = 20

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
        await runHistoricalMaintenancePipeline()

        // 6b Фаза 2 (фикс ревью 2026-07-10): легаси→core миграция ПЕРЕНЕСЕНА отсюда — теперь
        // вызывается раньше, ДО lifecycle == .ready (см. runLegacyAccountsMigrationIfNeeded и
        // initializeColdStart). Здесь (после .ready, после монтирования RootTabView) было слишком
        // поздно: FinanceViewModel уже успевал посчитать core-only агрегат тотала на пустом ядре.

    }

    @MainActor
    private func runHistoricalMaintenancePipeline() async {
        let scopeIdentifier = activeDataScope.storeConfigurationName
        await HistoricalValuationActivationPipeline.run(
            snapshotBackfill: {
                _ = await accountSnapshotBackfillCoordinator?.backfillIfNeeded(
                    scopeIdentifier: scopeIdentifier
                )
            },
            historicalMaintenance: {
                await historicalValuationMaintenance?.resumeMissedDays()
            }
        )
    }

    /// 6b Фаза 2 (фикс адверсариального ревью 2026-07-10): одноразовая opening-balance-миграция
    /// активных легаси-счетов (Card/Credit/Investment) в ядро AccountsCore + перенос полей легаси-
    /// групп. Вызывается ИЗ initializeColdStart ДО useCase.initialize() (который выставляет
    /// lifecycle = .ready) — на финальном (пост-swap) контейнере, но раньше, чем RootTabView вообще
    /// монтируется. Синхронная и быстрая (1–2 счёта у текущих юзеров, без сетевых вызовов) —
    /// перенос раньше .ready не меняет её стоимость, только устраняет transient «баланс ≈ 0» на
    /// первом кадре (агрегат тотала core-only с Фазы 2, а FinanceViewModel не пересчитывает сам
    /// себя после миграции — ни мигратор, ни конвертер не публикуют FinanceEvent).
    @MainActor
    private func runLegacyAccountsMigrationIfNeeded() async -> Bool {
        guard let modelContainer = diContainer?.modelContainer else {
            appState.lifecycle = .error(.incompatibleSchemaVersion)
            return false
        }
        let scopeIdentifier = activeDataScope.storeConfigurationName
        let readiness = HistoricalValuationReadinessCoordinator.shared
        readiness.begin(scopeID: scopeIdentifier, operation: .revisionMigration)

        do {
            let evidence = LegacyProductEvidenceCollector.collect(in: modelContainer.mainContext)
            let classified = try AccountProductIdentityMigrator.migratePersistedAccounts(
                in: modelContainer,
                verifiedEvidenceByCoreAccountID: evidence
            )
            if classified > 0 {
                AppLogger.log(.info, category: "AccountsCore", "Product identity [\(scopeIdentifier)]: \(classified) classified")
            }
        } catch {
            // A writable scope with unclassified product rows is not ready: continuing would let
            // edit/import writers operate on a tuple that the catalog has not validated.
            AppLogger.log(.error, category: "AccountsCore", "Product identity migration failed: \(error.localizedDescription)")
            readiness.fail(
                scopeID: scopeIdentifier,
                operation: .revisionMigration,
                reasonCode: "product_classification_failed"
            )
            appState.lifecycle = .error(.incompatibleSchemaVersion)
            return false
        }

        let migrator = LegacyAccountsMigrator(modelContext: modelContainer.mainContext)
        let summary = migrator.migrateIfNeeded(scopeIdentifier: scopeIdentifier)
        if summary.migrated > 0 || summary.failures > 0 {
            AppLogger.log(.info, category: "AccountsCore",
                          "Legacy migration [\(scopeIdentifier)]: \(summary.migrated) мигрировано, \(summary.skippedAlreadyConverted) уже, \(summary.failures) ошибок")
        }
        guard summary.failures == 0 else {
            readiness.fail(
                scopeID: scopeIdentifier,
                operation: .revisionMigration,
                reasonCode: "legacy_product_migration_failed"
            )
            appState.lifecycle = .error(.incompatibleSchemaVersion)
            return false
        }

        // 6b Фаза 1.5: перенос полей легаси-групп (isFavorite/priority/ordering/color/currency/order)
        // на одноимённые AccountGroup. После миграции счетов (выше) группы-двойники уже существуют —
        // здесь дозаполняем их поля. Идемпотентно (legacyFieldsMigratedAt-маркер на AccountGroup,
        // сериализуется в export/import — переживает backup/restore, фикс дефекта ревью 2026-07-09).
        let groupsMigrator = GroupsMigrator(modelContext: modelContainer.mainContext)
        let groupsSummary = groupsMigrator.migrateIfNeeded(scopeIdentifier: scopeIdentifier)
        if groupsSummary.migrated > 0 {
            AppLogger.log(.info, category: "AccountsCore",
                          "Groups merge [\(scopeIdentifier)]: \(groupsSummary.migrated) групп перенесено")
        }
        readiness.complete(scopeID: scopeIdentifier, operation: .revisionMigration)
        return true
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
        AccountsCoreFeatureRegistration.register()
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

        // Schema централизованно подставляет `AppMigrationPlan.makeContainer`: это
        // гарантирует current version identifier даже для schema-less production config.
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

            // Fail closed for both existing and first-launch stores. In particular, an unknown or
            // unmigratable existing schema must remain byte-for-byte untouched for explicit recovery;
            // no no-plan open, rename, deletion or automatic fresh-store creation is safe here.
            if storeAlreadyExists {
                ScopeStoreOpenTracker.shared.markFallback(scope.storeConfigurationName)
            }
            AppLogger.log(.error, category: "App", "Persistent store preserved; showing storage recovery error UI")
            return nil
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

        // Идемпотентность (D1): synchronizeDataScope дёргается и на cold start (:328), и на
        // каждом onSessionChanged (:418) — включая тот, что приходит от restoreSession в том же
        // запуске. Без гейта второй проход открывал RestoreView повторно / инкрементил счётчик
        // попыток второй раз.
        guard let gateToken = launchRecoveryGate.beginEvaluation(
            scopeKey: activeDataScope.storeConfigurationName
        ) else {
            AppLogger.log(.info, category: "App", "LaunchRecovery: решение уже принято для текущего поколения scope — no-op")
            return
        }

        let localDataCount = Self.exportedModelCount(in: activeModelContainer)
        // Если данные есть — счётчик авто-восстановления сбрасываем, чтобы не застревать
        // в ручном restore после двух неудачных попыток (например, при passphrase-бэкапе).
        if let localDataCount, localDataCount > 0 {
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
        let countDescription = localDataCount.map(String.init) ?? "unknown"
        AppLogger.log(.info, category: "App", "LaunchRecovery: localCount=\(countDescription) storeExisted=\(activeScopeStoreExistedBeforeBinding) backup=\(latestBackupInfo != nil) lifecycle=\(appState.lifecycle) → \(recoveryDecision)")

        // Транзиентный skip (lifecycle не готов, онбординг не пройден, лукап бэкапа пуст/упал)
        // не фиксируется как принятое решение — повторный проход обязан отработать заново (SR7).
        launchRecoveryGate.finish(
            gateToken,
            outcome: recoveryDecision.locksLaunchRecovery ? .decided : .unresolved
        )
        guard recoveryDecision.shouldPresentRestore else { return }
        appState.isICloudAvailable = await diContainer.backupManager.isAvailable()
        appState.lastBackupDate = latestBackupInfo?.date

        // Если стор существовал, но данные исчезли (потеря при обновлении / миграции схемы) —
        // восстанавливаем последний бекап автоматически, без участия пользователя.
        // Неизвестный счётчик локальных моделей запрещает деструктивный авто-путь:
        // пользователь сам подтверждает перезапись в RestoreView.
        if recoveryDecision.allowsAutomaticRestore, activeScopeStoreExistedBeforeBinding, latestBackupInfo != nil {
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
                defer {
                    Task { @MainActor in
                        guard launchRecoveryGate.shouldPublishRestoreOutcome(for: gateToken) else { return }
                        appState.isRestoreInProgress = false
                    }
                }
                do {
                    // TODO(temp): заменить size-guard на preflight.modelCount > 0 когда появится preflightLatestBackup()
                    let versions = await diContainer.backupManager.listBackupVersions()
                    guard let latestVersion = versions.first, latestVersion.size >= 1024 else {
                        AppLogger.log(.warning, category: "App", "Auto-restore: нет валидных версий (пусто или < 1KB), переходим к ручному restore")
                        await MainActor.run { publishAutoRestoreLifecycle(.restoring, token: gateToken) }
                        return
                    }
                    // Точка перед деструктивной фазой: если пользователь успел разлогиниться или
                    // сменить аккаунт, восстановление в чужой scope не запускаем вовсе.
                    guard await MainActor.run(body: { launchRecoveryGate.isCurrent(gateToken) }) else {
                        AppLogger.log(.warning, category: "App", "Auto-restore: scope сменился до старта восстановления — отменено")
                        return
                    }
                    try await withTaskTimeout(seconds: Self.autoRestoreTimeoutSeconds) {
                        try await diContainer.backupManager.restoreLatest(passphrase: nil)
                    }
                    guard await MainActor.run(body: { launchRecoveryGate.shouldPublishRestoreOutcome(for: gateToken) }) else {
                        AppLogger.log(.warning, category: "App", "Auto-restore: результат устарел (сменился scope) — успех не публикуется")
                        return
                    }
                    UserDefaults.standard.set(0, forKey: Self.autoRestoreAttemptsKey)
                    AppLogger.log(.info, category: "App", "Auto-restore completed successfully")
                    await MainActor.run { publishAutoRestoreLifecycle(.ready, token: gateToken) }
                } catch {
                    CrashReporting.record(error: error)
                    AppLogger.log(.error, category: "App", "Auto-restore failed, falling back to manual: \(error.localizedDescription)")
                    await MainActor.run { publishAutoRestoreLifecycle(.restoring, token: gateToken) }
                }
            }
        } else {
            if case .presentRestoreManualOnly(let reason) = recoveryDecision {
                AppLogger.log(.warning, category: "App", "LaunchRecovery: авто-restore запрещён (\(reason)) — ручной сценарий")
            }
            // Свежая установка с доступным бекапом (или неизвестный локальный счётчик) —
            // показываем экран выбора версии.
            appState.lifecycle = .restoring
        }
    }

    /// Единственная точка публикации результата авто-restore в lifecycle.
    /// Stale-колбэк (scope сменился во время восстановления) молча отбрасывается.
    @MainActor
    private func publishAutoRestoreLifecycle(
        _ lifecycle: AppLifecycleState,
        token: LaunchRecoveryGate.Token
    ) {
        guard launchRecoveryGate.shouldPublishRestoreOutcome(for: token) else {
            AppLogger.log(.warning, category: "App", "Auto-restore: stale-колбэк, lifecycle не меняем")
            return
        }
        appState.lifecycle = lifecycle
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
