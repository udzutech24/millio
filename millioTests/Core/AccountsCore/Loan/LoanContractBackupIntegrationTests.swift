import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф7 кредита: договор попадает в бэкап и переживает export → wipe → import без потери полей
/// (спека §9.3). До регистрации в `ModelTypeRegistry` условия кредита в бэкап не попадали вовсе.
@Suite(.serialized)
@MainActor
struct LoanContractBackupIntegrationTests {

    private func withRegistry(_ body: () throws -> Void) throws {
        let state = ModelTypeRegistry.shared.captureState()
        FinanceFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        CurrencyFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()
        do { try body() } catch { ModelTypeRegistry.shared.restoreState(state); throw error }
        ModelTypeRegistry.shared.restoreState(state)
    }

    private func firstPaymentDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
    }

    @Test("export → wipe → import: поля договора возвращаются без потерь")
    func contractSurvivesBackupRoundtrip() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext

            let account = Account(name: "Автокредит", kind: .loan)
            context.insert(account)
            let accountID = account.id
            let opened = firstPaymentDate()
            try LoanContractStore(context: context).upsert(accountID: accountID) {
                $0.principal = 1_200_000
                $0.annualRatePercent = 18.9
                $0.termPeriods = 60
                $0.firstPaymentDate = opened
                $0.scheduleType = .differentiated
                $0.frequency = .quarterly
                $0.paymentOverride = 31_063.55
                $0.paymentsMade = 5
                $0.paidInterestTotal = 92_554.42
                $0.insuranceAmount = 1_500
            }
            try context.save()

            let backup = try DataRepository.exportAllData(from: context)
            let repository = DataRepository(modelContext: context, modelContainer: container)
            try repository.clearAllData()
            #expect(try context.fetch(FetchDescriptor<LoanContract>()).isEmpty)

            try repository.importAllData(backup)

            let restored = try #require(try LoanContractStore(context: context).contract(for: accountID))
            #expect(restored.principal == 1_200_000)
            #expect(restored.annualRatePercent == 18.9)
            #expect(restored.termPeriods == 60)
            #expect(restored.firstPaymentDate.timeIntervalSince1970 == opened.timeIntervalSince1970)
            #expect(restored.scheduleType == .differentiated)
            #expect(restored.frequency == .quarterly)
            // Копейки обязаны пережить бэкап бит-в-бит: денежные поля едут строкой, не Double.
            #expect(restored.paymentOverride == Decimal(string: "31063.55"))
            #expect(restored.paymentsMade == 5)
            #expect(restored.paidInterestTotal == Decimal(string: "92554.42"))
            #expect(restored.insuranceAmount == 1_500)
        }
    }

    @Test("Старый бэкап без договоров восстанавливается без краша")
    func oldBackupWithoutContractRestores() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext
            context.insert(Account(name: "Кредит без договора", kind: .loan))
            try context.save()

            let backup = try DataRepository.exportAllData(from: context)
            let repository = DataRepository(modelContext: context, modelContainer: container)
            try repository.clearAllData()
            try repository.importAllData(backup)

            #expect(try context.fetch(FetchDescriptor<Account>()).count == 1)
            #expect(try context.fetch(FetchDescriptor<LoanContract>()).isEmpty)
        }
    }

    @Test("Импортёр идемпотентен: повторный импорт того же словаря не плодит строк")
    func importerIsIdempotent() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let dict: [String: Any] = [
            "type": "LoanContract",
            "id": UUID().uuidString,
            "accountID": UUID().uuidString,
            "principal": "1200000",
            "annualRatePercent": "18.9",
            "termPeriods": 60,
            "firstPaymentDate": firstPaymentDate().timeIntervalSince1970,
            "scheduleTypeRaw": LoanScheduleType.annuity.rawValue,
            "frequencyRaw": LoanPaymentFrequency.monthly.rawValue,
            "paymentsMade": 5,
            "paidInterestTotal": "92554",
            "createdAt": firstPaymentDate().timeIntervalSince1970,
            "updatedAt": firstPaymentDate().timeIntervalSince1970,
        ]
        try LoanContractImporter.import(from: dict, context: context)
        try LoanContractImporter.import(from: dict, context: context)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<LoanContract>()).count == 1)
    }

    @Test("Битая строка бэкапа отвергается, а не пишется мусором")
    func importerRejectsCorruptedRow() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        #expect(throws: AppError.backupCorrupted) {
            try LoanContractImporter.import(
                from: ["type": "LoanContract", "id": "не-uuid", "accountID": "тоже-не-uuid"],
                context: context
            )
        }
    }
}
