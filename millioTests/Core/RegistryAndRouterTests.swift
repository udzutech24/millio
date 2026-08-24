import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import millio

@Suite(.serialized)
struct ModelTypeRegistryTests {
    @Test("captureState/restoreState откатывает регистрацию importer")
    func testCaptureAndRestoreStateRevertsImporterRegistration() {
        let state = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(state) }
        
        struct TestImporter: ModelImporter {
            static func importType() -> String { "TestImporterType" }
            static func `import`(from data: [String: Any], context: ModelContext) throws {}
        }
        
        #expect(ModelTypeRegistry.shared.getImporter(for: "TestImporterType") == nil)
        ModelTypeRegistry.shared.registerImporter(TestImporter.self)
        #expect(ModelTypeRegistry.shared.getImporter(for: "TestImporterType") != nil)
        
        ModelTypeRegistry.shared.restoreState(state)
        #expect(ModelTypeRegistry.shared.getImporter(for: "TestImporterType") == nil)
    }
    
    @Test("ModelTypeRegistry выдерживает конкурентные registerImporter")
    func testConcurrentRegisterImporter() async {
        let state = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(state) }
        
        struct ImporterA: ModelImporter { static func importType() -> String { "A" }; static func `import`(from data: [String : Any], context: ModelContext) throws {} }
        struct ImporterB: ModelImporter { static func importType() -> String { "B" }; static func `import`(from data: [String : Any], context: ModelContext) throws {} }
        struct ImporterC: ModelImporter { static func importType() -> String { "C" }; static func `import`(from data: [String : Any], context: ModelContext) throws {} }
        struct ImporterD: ModelImporter { static func importType() -> String { "D" }; static func `import`(from data: [String : Any], context: ModelContext) throws {} }
        struct ImporterE: ModelImporter { static func importType() -> String { "E" }; static func `import`(from data: [String : Any], context: ModelContext) throws {} }
        struct ImporterF: ModelImporter { static func importType() -> String { "F" }; static func `import`(from data: [String : Any], context: ModelContext) throws {} }
        struct ImporterG: ModelImporter { static func importType() -> String { "G" }; static func `import`(from data: [String : Any], context: ModelContext) throws {} }
        struct ImporterH: ModelImporter { static func importType() -> String { "H" }; static func `import`(from data: [String : Any], context: ModelContext) throws {} }
        struct ImporterI: ModelImporter { static func importType() -> String { "I" }; static func `import`(from data: [String : Any], context: ModelContext) throws {} }
        struct ImporterJ: ModelImporter { static func importType() -> String { "J" }; static func `import`(from data: [String : Any], context: ModelContext) throws {} }
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { ModelTypeRegistry.shared.registerImporter(ImporterA.self) }
            group.addTask { ModelTypeRegistry.shared.registerImporter(ImporterB.self) }
            group.addTask { ModelTypeRegistry.shared.registerImporter(ImporterC.self) }
            group.addTask { ModelTypeRegistry.shared.registerImporter(ImporterD.self) }
            group.addTask { ModelTypeRegistry.shared.registerImporter(ImporterE.self) }
            group.addTask { ModelTypeRegistry.shared.registerImporter(ImporterF.self) }
            group.addTask { ModelTypeRegistry.shared.registerImporter(ImporterG.self) }
            group.addTask { ModelTypeRegistry.shared.registerImporter(ImporterH.self) }
            group.addTask { ModelTypeRegistry.shared.registerImporter(ImporterI.self) }
            group.addTask { ModelTypeRegistry.shared.registerImporter(ImporterJ.self) }
        }
        
        #expect(ModelTypeRegistry.shared.getImporter(for: "A") != nil)
        #expect(ModelTypeRegistry.shared.getImporter(for: "J") != nil)
    }
}

@Suite(.serialized)
@MainActor
struct AppRouterTests {
    @Test("navigate(to:) сбрасывает navigationPath и выставляет currentRoute")
    func testNavigateResetsPath() {
        let router = AppRouter()
        router.push(.finances)
        #expect(router.navigationPath.count == 1)
        
        router.navigate(to: .main)
        #expect(router.currentRoute == .main)
        #expect(router.navigationPath.count == 0)
    }
    
    @Test("push добавляет маршрут в navigationPath")
    func testPushAppendsToPath() {
        let router = AppRouter()
        router.push(.finances)
        router.push(.profile)
        #expect(router.navigationPath.count == 2)
    }

    @Test("popToRoot сбрасывает стек, не меняя текущий маршрут")
    func testPopToRootKeepsCurrentRoute() {
        let router = AppRouter()
        router.currentRoute = .main
        router.push(.profile)
        #expect(router.navigationPath.count == 1)

        router.popToRoot()
        #expect(router.currentRoute == .main)
        #expect(router.navigationPath.count == 0)
    }
}

@Suite(.serialized)
struct RootViewResolverTests {
    @Test("RootViewResolver.route корректно маппит AppLifecycleState")
    func testRouteMapping() {
        #expect(RootViewResolver.route(for: .launching, authStatus: .signedOut, isAuthenticated: false, isGuestModeEnabled: false) == .launching)
        #expect(RootViewResolver.route(for: .ready, authStatus: .restoring, isAuthenticated: false, isGuestModeEnabled: false) == .ready)
        #expect(RootViewResolver.route(for: .onboarding, authStatus: .signedOut, isAuthenticated: false, isGuestModeEnabled: false) == .auth)
        #expect(RootViewResolver.route(for: .onboarding, authStatus: .signedOut, isAuthenticated: false, isGuestModeEnabled: true) == .onboarding)
        #expect(RootViewResolver.route(for: .onboarding, authStatus: .authenticated, isAuthenticated: true, isGuestModeEnabled: false) == .onboarding)
        #expect(RootViewResolver.route(for: .restoring, authStatus: .authenticated, isAuthenticated: true, isGuestModeEnabled: false) == .restoring)
        #expect(RootViewResolver.route(for: .ready, authStatus: .authenticated, isAuthenticated: true, isGuestModeEnabled: false) == .ready)
        #expect(RootViewResolver.route(for: .error(.iCloudUnavailable), authStatus: .authenticated, isAuthenticated: true, isGuestModeEnabled: false) == .error)
    }

    @Test("Фоновой restoreSession не роняет готовый экран обратно в сплэш (регресс мигания при старте)")
    func testReadyRouteSurvivesBackgroundSessionRestore() {
        // Холодный старт авторизованного пользователя: локальный снапшот сессии → .ready,
        // затем сетевой restoreSession выставляет authStatus = .restoring.
        //
        // ⚠️ Ключ регресса: во время .restoring isAuthenticated == FALSE, потому что
        // AuthManager.isAuthenticated == (status == .authenticated && currentUser != nil)
        // (AuthService.swift:1203). Прежняя версия этого теста подавала здесь `true` и
        // поэтому не воспроизводила баг, хотя на устройстве дерево сносилось в сплэш
        // (лог: ROUTE ready -> launching -> ready за 108 мс, один и тот же PID).
        let sequence: [(AppLifecycleState, AuthManagerStatus, Bool)] = [
            (.launching, .signedOut, false),      // старт
            (.launching, .authenticated, true),   // снапшот сессии восстановлен
            (.ready, .authenticated, true),       // дерево смонтировано
            (.ready, .restoring, false),          // фоновой сетевой restoreSession
            (.ready, .authenticated, true)        // restoreSession завершён
        ]
        let routes = sequence.map { lifecycle, status, isAuthenticated in
            RootViewResolver.route(
                for: lifecycle,
                authStatus: status,
                isAuthenticated: isAuthenticated,
                isGuestModeEnabled: false
            )
        }
        #expect(routes == [.launching, .launching, .ready, .ready, .ready])
        // Ни одного перемонтирования дерева после того, как экран стал .ready.
        #expect(!routes.drop(while: { $0 != .ready }).contains(.launching))
    }

    @Test("restoring не мигает ни .auth, ни сплэшем: до монтирования — сплэш, после — текущий экран")
    func testUnauthenticatedRestoringNeverFlashesAuth() {
        // До того как дерево смонтировано (lifecycle == .launching) — сплэш, а не .auth.
        #expect(RootViewResolver.route(for: .launching, authStatus: .restoring, isAuthenticated: false, isGuestModeEnabled: false) == .launching)
        // Дерево уже смонтировано: транзиентный .restoring НЕ откатывает экран назад.
        #expect(RootViewResolver.route(for: .ready, authStatus: .restoring, isAuthenticated: false, isGuestModeEnabled: false) == .ready)
        #expect(RootViewResolver.route(for: .onboarding, authStatus: .restoring, isAuthenticated: false, isGuestModeEnabled: false) == .onboarding)
        #expect(RootViewResolver.route(for: .restoring, authStatus: .restoring, isAuthenticated: false, isGuestModeEnabled: false) == .restoring)
        // Терминальный отказ сессии (logout / 401 → .signedOut) — экран авторизации, как и раньше.
        #expect(RootViewResolver.route(for: .ready, authStatus: .signedOut, isAuthenticated: false, isGuestModeEnabled: false) == .auth)
        #expect(RootViewResolver.route(for: .onboarding, authStatus: .signedOut, isAuthenticated: false, isGuestModeEnabled: false) == .auth)
        // Гостевой режим не зависит от статуса auth.
        #expect(RootViewResolver.route(for: .ready, authStatus: .restoring, isAuthenticated: false, isGuestModeEnabled: true) == .ready)
    }

    @Test("Полная хронология холодного старта с устройства не содержит второго прохода UI")
    func testDeviceColdStartTimelineHasNoSecondMount() {
        // Воспроизводит трассировку StartupTrace с iPhone 17 Pro Max (один PID, без краша):
        // t+0.058 launching → t+2.405 ready → t+3.739 restoreSession → t+3.847 authenticated.
        let sequence: [(AppLifecycleState, AuthManagerStatus, Bool)] = [
            (.launching, .signedOut, false),
            (.launching, .authenticated, true),
            (.ready, .authenticated, true),
            (.ready, .restoring, false),
            (.ready, .authenticated, true)
        ]
        let routes = sequence.map { lifecycle, status, isAuthenticated in
            RootViewResolver.route(
                for: lifecycle,
                authStatus: status,
                isAuthenticated: isAuthenticated,
                isGuestModeEnabled: false
            )
        }
        // После первого .ready маршрут больше не меняется → RootTabView монтируется ровно один раз.
        let afterFirstReady = Array(routes.drop(while: { $0 != .ready }))
        #expect(afterFirstReady.allSatisfy { $0 == .ready })
        #expect(!routes.contains(.auth))
    }

    @Test("RootViewResolver сбрасывает стек только при смене root-route")
    func testShouldResetNavigationPathOnRootRouteChange() {
        #expect(RootViewResolver.shouldResetNavigationPath(from: .auth, to: .ready))
        #expect(RootViewResolver.shouldResetNavigationPath(from: .ready, to: .onboarding))
        #expect(!RootViewResolver.shouldResetNavigationPath(from: .ready, to: .ready))
    }
}

@Suite(.serialized)
struct FeatureRegistryTests {
    @Test("FeatureRegistry.configureAll вызывает registerModels для зарегистрированных модулей")
    func testConfigureAllCallsRegisterModels() {
        let state = FeatureRegistry.shared.captureState()
        defer { FeatureRegistry.shared.restoreState(state) }
        
        final class Recorder {
            var calls = 0
        }
        let recorder = Recorder()
        
        struct TestFeature: FeatureModule {
            let recorder: Recorder
            
            func registerModels(in registry: ModelTypeRegistryProtocol) {
                recorder.calls += 1
            }
            
            func registerRoutes(in router: AppRouter) {}
            func configureDependencies(in container: DIContainer) {}
        }
        
        FeatureRegistry.shared.register(TestFeature(recorder: recorder))
        FeatureRegistry.shared.configureAll()
        
        #expect(recorder.calls == 1)
    }
}
