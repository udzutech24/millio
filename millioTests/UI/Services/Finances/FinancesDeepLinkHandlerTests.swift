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
    private static let schema = Schema([
        Card.self,
        Credit.self,
        Investment.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self
    ])
    private static var retainedContainers: [ModelContainer] = []

    private func createTestModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        let context = container.mainContext
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
