//
//  CashbackViewModelCategoryDedupTests.swift
//  millioTests
//
//  Регрессионный тест на краш `Fatal error: Duplicate values for key: 'custom:<UUID>'`
//  у CashbackCustomCategory — та же уязвимость, что была у CashflowCustomCategory
//  (см. CashflowCategoryServiceDedupTests). categoryID не защищён @Attribute(.unique),
//  CloudKit merge/restore мог создать два CashbackCustomCategory с одним categoryID —
//  ForEach/LazyVGrid по [CashbackCategoryOption] падал, т.к. id == rawValue ==
//  "custom:<categoryID>" совпадал у обоих объектов.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct CashbackViewModelCategoryDedupTests {
    private static let schema = Schema([
        Card.self,
        Cashback.self,
        CashbackCustomCategory.self
    ])
    // Без retainedContainers ModelContainer деаллоцируется сразу после return
    // (только mainContext возвращается наружу) — доступ к контексту после этого
    // валит тест SIGTRAP'ом. См. тот же паттерн в CashflowCategoryServiceDedupTests.
    private static var retainedContainers: [ModelContainer] = []

    private func createTestModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    /// Изолированный UserDefaults suite: CashbackViewModel по умолчанию читает/пишет
    /// hiddenCategoryRaws в `.standard`, который расшарен между параллельными тестами
    /// в этом же test-процессе — без изоляции тест плавает в зависимости от того, что
    /// туда успели записать другие сьюты (см. Test Fix Mode в AGENTS.md).
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "CashbackViewModelCategoryDedupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - dedupedCustomCategories (чистая логика)

    @Test("Дубли categoryID схлопываются в одну запись — побеждает более поздний updatedAt")
    func dedupKeepsLatestUpdatedAt() throws {
        let sharedID = UUID().uuidString

        let older = CashbackCustomCategory(name: "Такси")
        older.categoryID = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 1_000)

        let newer = CashbackCustomCategory(name: "Такси (переименовано)")
        newer.categoryID = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)

        let result = CashbackViewModel.dedupedCustomCategories([older, newer])

        #expect(result.count == 1, "Два объекта с одинаковым categoryID должны схлопнуться в один")
        #expect(result.first?.name == "Такси (переименовано)", "Побеждает объект с более поздним updatedAt")
    }

    @Test("Категории с разными categoryID не затрагиваются")
    func distinctCategoriesUnaffected() throws {
        let a = CashbackCustomCategory(name: "A")
        let b = CashbackCustomCategory(name: "B")

        let result = CashbackViewModel.dedupedCustomCategories([a, b])

        #expect(result.count == 2)
    }

    @Test("Пустой массив не падает")
    func emptyArrayDoesNotCrash() throws {
        let result = CashbackViewModel.dedupedCustomCategories([])
        #expect(result.isEmpty)
    }

    @Test("Три дубля с одним categoryID схлопываются в один экземпляр")
    func threeWayDuplicateCollapsesToOne() throws {
        let sharedID = UUID().uuidString
        let first = CashbackCustomCategory(name: "V1")
        first.categoryID = sharedID
        first.updatedAt = Date(timeIntervalSince1970: 1_000)

        let second = CashbackCustomCategory(name: "V2")
        second.categoryID = sharedID
        second.updatedAt = Date(timeIntervalSince1970: 3_000)

        let third = CashbackCustomCategory(name: "V3")
        third.categoryID = sharedID
        third.updatedAt = Date(timeIntervalSince1970: 2_000)

        let result = CashbackViewModel.dedupedCustomCategories([first, second, third])

        #expect(result.count == 1)
        #expect(result.first?.name == "V2", "Побеждает объект с максимальным updatedAt среди всех дублей")
    }

    // MARK: - categoryOptions(matching:) — сквозной регресс сценария из краша

    @Test("categoryOptions возвращает уникальные id при дубле categoryID в сторе — краш не воспроизводится")
    func categoryOptionsProducesUniqueIDsDespiteDuplicateStore() throws {
        let modelContext = try createTestModelContext()

        let sharedID = UUID().uuidString
        let first = CashbackCustomCategory(name: "Такси")
        first.categoryID = sharedID
        first.updatedAt = Date(timeIntervalSince1970: 1_000)

        let duplicate = CashbackCustomCategory(name: "Такси (дубль)")
        duplicate.categoryID = sharedID
        duplicate.updatedAt = Date(timeIntervalSince1970: 2_000)

        modelContext.insert(first)
        modelContext.insert(duplicate)
        try modelContext.save()

        let viewModel = CashbackViewModel(modelContext: modelContext, defaults: makeIsolatedDefaults())
        let options = viewModel.categoryOptions()

        let customOptions = options.filter(\.isCustom)
        #expect(customOptions.count == 1, "Дубли с одинаковым categoryID должны схлопнуться в одну опцию")

        let ids = Set(options.map(\.id))
        #expect(ids.count == options.count, "id всех CashbackCategoryOption обязаны быть уникальны — иначе ForEach/LazyVGrid падает с Fatal error: Duplicate values for key")
    }
}
