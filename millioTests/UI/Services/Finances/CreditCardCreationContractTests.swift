import Foundation
import Testing
@testable import millio

@Suite("Credit-card specialized creation contract")
struct CreditCardCreationContractTests {
    @Test("Creation resolver persists every supported CardMeta term")
    func supportedTerms() throws {
        let command = try FinanceProductCreationCommandResolver.resolve(.init(
            option: .card,
            name: "Card",
            currency: "RUB",
            amount: 80_000,
            includeInTotal: false,
            cardType: .credit,
            bank: .sberbank,
            cardLast4: "4242",
            creditLimit: 100_000,
            statementDay: 5,
            dueDay: 25,
            minPayment: 2_000,
            graceDays: 60
        ))
        #expect(command.productType == .creditCard)
        #expect(command.includeInTotal == false)
        #expect(command.metadata.card?.last4 == "4242")
        #expect(command.metadata.card?.creditLimit == 100_000)
        #expect(command.metadata.card?.statementDay == 5)
        #expect(command.metadata.card?.dueDay == 25)
        #expect(command.metadata.card?.minPayment == 2_000)
        #expect(command.metadata.card?.graceDays == 60)
    }
}
