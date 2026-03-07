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
}

@Suite(.serialized)
struct RootViewResolverTests {
    @Test("RootViewResolver.route корректно маппит AppLifecycleState")
    func testRouteMapping() {
        #expect(RootViewResolver.route(for: .launching, authStatus: .signedOut, isAuthenticated: false, isGuestModeEnabled: false) == .launching)
        #expect(RootViewResolver.route(for: .ready, authStatus: .restoring, isAuthenticated: false, isGuestModeEnabled: false) == .launching)
        #expect(RootViewResolver.route(for: .onboarding, authStatus: .signedOut, isAuthenticated: false, isGuestModeEnabled: false) == .auth)
        #expect(RootViewResolver.route(for: .onboarding, authStatus: .signedOut, isAuthenticated: false, isGuestModeEnabled: true) == .onboarding)
        #expect(RootViewResolver.route(for: .onboarding, authStatus: .authenticated, isAuthenticated: true, isGuestModeEnabled: false) == .onboarding)
        #expect(RootViewResolver.route(for: .restoring, authStatus: .authenticated, isAuthenticated: true, isGuestModeEnabled: false) == .restoring)
        #expect(RootViewResolver.route(for: .ready, authStatus: .authenticated, isAuthenticated: true, isGuestModeEnabled: false) == .ready)
        #expect(RootViewResolver.route(for: .error(.iCloudUnavailable), authStatus: .authenticated, isAuthenticated: true, isGuestModeEnabled: false) == .error)
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
