//
//  FinancesDeepLinkHandlerTests.swift
//  millioTests
//
//  Created by Codex on 03.03.2026.
//

import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct FinancesDeepLinkHandlerTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            Credit.self,
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.deleteAll(FinanceAccount.self)
        try context.deleteAll(FinanceGroup.self)
        try context.deleteAll(Card.self)
        try context.deleteAll(Credit.self)
        try context.deleteAll(Investment.self)
        try context.deleteAll(CashflowTransaction.self)
        try context.save()
        return context
    }

    @Test("Deep-link открывает add product sheet и сбрасывает флаг")
    func testOpenAddCardIfRequestedConsumesPendingFlag() throws {
        let context = try createTestModelContext()
        let appState = AppState()
        let viewModel = FinanceViewModel(modelContext: context, skipInitialLoad: true)
        appState.pendingOpenFinanceAddCard = true

        FinancesDeepLinkHandler.openAddCardIfRequested(appState: appState, viewModel: viewModel)

        #expect(appState.pendingOpenFinanceAddCard == false)
        #expect(viewModel.state.showAddAccountSheet)
        #expect(viewModel.state.selectedGroupForAccount == nil)
    }

    @Test("Deep-link не теряется, пока FinanceViewModel не готов")
    func testOpenAddCardIfRequestedKeepsPendingWhenViewModelMissing() {
        let appState = AppState()
        appState.pendingOpenFinanceAddCard = true

        FinancesDeepLinkHandler.openAddCardIfRequested(appState: appState, viewModel: nil)

        #expect(appState.pendingOpenFinanceAddCard)
    }

    @Test("Без pending-флага add product sheet не открывается")
    func testOpenAddCardIfRequestedNoopWhenPendingFlagIsFalse() throws {
        let context = try createTestModelContext()
        let appState = AppState()
        let viewModel = FinanceViewModel(modelContext: context, skipInitialLoad: true)

        FinancesDeepLinkHandler.openAddCardIfRequested(appState: appState, viewModel: viewModel)

        #expect(viewModel.state.showAddAccountSheet == false)
    }
}
