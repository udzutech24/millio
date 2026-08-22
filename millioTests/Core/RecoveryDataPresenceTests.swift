import Foundation
import Testing
@testable import millio

struct RecoveryDataPresenceTests {
    @Test("Reference and cache models do not suppress recovery")
    func ignoresReferenceModels() throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "models": [
                ["_type": "HistoricalRate"],
                ["_type": "AssetCatalogItem"],
                ["_type": "HistoricalAssetPrice"]
            ]
        ])

        #expect(RecoveryDataPresence.userFinancialModelCount(in: payload) == 0)
    }

    @Test("Accounts and transactions prove user financial data exists")
    func countsFinancialModels() throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "models": [
                ["_type": "HistoricalRate"],
                ["_type": "Account"],
                ["_type": "CashflowTransaction"]
            ]
        ])

        #expect(RecoveryDataPresence.userFinancialModelCount(in: payload) == 2)
    }
}
