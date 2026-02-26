//
//  CashbackViewModelScreenshotImportTests.swift
//  millioTests
//
//  Created by Codex on 26.02.2026.
//

import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct CashbackViewModelScreenshotImportTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            Cashback.self,
            CashbackCustomCategory.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    private func createModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.deleteAll(Cashback.self)
        try context.deleteAll(CashbackCustomCategory.self)
        try context.deleteAll(Card.self)
        try context.save()
        return context
    }

    @Test("Импортное имя маппится в системную категорию, если совпадение очевидно")
    func testCategoryOptionForImportedNameUsesSystemCategory() throws {
        let context = try createModelContext()
        let viewModel = CashbackViewModel(modelContext: context)

        let option = viewModel.categoryOptionForImportedName("Топливо в городе")

        #expect(option.rawValue == CashbackCategory.gasStation.rawValue)
        #expect(option.isCustom == false)
        #expect(option.displayName == CashbackCategory.gasStation.displayName)
    }

    @Test("Неизвестная импортная категория создаётся как кастомная и дедуплицируется")
    func testCategoryOptionForImportedNameCreatesCustomCategory() throws {
        let context = try createModelContext()
        let viewModel = CashbackViewModel(modelContext: context)

        let first = viewModel.categoryOptionForImportedName("Авиабилеты")
        let second = viewModel.categoryOptionForImportedName("  авиабилеты  ")

        #expect(first.isCustom)
        #expect(second.isCustom)
        #expect(first.rawValue == second.rawValue)
        #expect(viewModel.state.customCategories.count == 1)
        #expect(viewModel.state.customCategories.first?.name == "Авиабилеты")
    }
}
