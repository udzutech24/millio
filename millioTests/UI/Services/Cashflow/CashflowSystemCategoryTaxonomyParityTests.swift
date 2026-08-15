import Foundation
import Testing
@testable import millio

struct CashflowSystemCategoryTaxonomyParityTests {
    private struct Fixture: Decodable {
        let version: Int
        let income: [String]
        let expense: [String]
    }

    @Test("Versioned statement taxonomy matches the current iOS system categories")
    func fixtureMatchesIOSCatalog() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = (0..<5).reduce(testFile) { value, _ in value.deletingLastPathComponent() }
        let fixtureURL = repositoryRoot
            .appendingPathComponent("millio/UI/Services/Cashflow/StatementImport/Fixtures/system-category-taxonomy.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))

        #expect(fixture.version == 1)
        #expect(Set(fixture.income) == Set(IncomeCategory.allCases.map(\.rawValue)))
        #expect(Set(fixture.expense) == Set(ExpenseCategory.allCases.map(\.rawValue)))
        #expect((fixture.income + fixture.expense).allSatisfy { !$0.hasPrefix("custom:") })
    }
}
