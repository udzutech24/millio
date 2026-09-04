import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф3 кредита: договор, сохранённый формой, переживает перезапуск приложения.
///
/// Именно перезапуск, а не `context.save()`: in-memory контейнер остальных тестов доказывает
/// только то, что строка легла в контекст. Здесь стор кладётся НА ДИСК, контейнер отпускается
/// и открывается заново по тому же URL — это и есть «закрыл приложение, открыл снова».
@Suite(.serialized)
@MainActor
struct LoanContractPersistenceTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func makeStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("loan-contract-\(UUID().uuidString).store")
    }

    private func makeContainer(at url: URL) throws -> ModelContainer {
        try AppMigrationPlan.makeContainer(
            configuration: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
    }

    private func removeStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + suffix)
            )
        }
    }

    @Test("Условия, собранные формой, читаются после перезапуска стора")
    func draftSurvivesRestart() throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }

        let accountID = UUID()
        let firstPayment = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!

        var draft = LoanTermsDraft(firstPaymentDate: firstPayment)
        draft.principalText = "1200000"
        draft.ratePercentText = "18.9"
        draft.termMonths = 60
        draft.frequency = .quarterly
        draft.alignTermToFrequency()
        draft.scheduleType = .differentiated
        draft.isManualPayment = true
        draft.paymentText = "94059"
        let terms = try #require(draft.terms)

        do {
            let container = try makeContainer(at: url)
            let context = container.mainContext
            try LoanContractStore(context: context).upsert(accountID: accountID) { contract in
                contract.principal = terms.principal
                contract.annualRatePercent = terms.annualRatePercent
                contract.termPeriods = terms.termPeriods
                contract.firstPaymentDate = terms.firstPaymentDate
                contract.scheduleType = terms.scheduleType
                contract.frequency = terms.frequency
                contract.paymentOverride = terms.paymentOverride
            }
            try context.save()
        }

        // Новый контейнер по тому же файлу — тот же путь, что проходит приложение при запуске.
        let reopened = try makeContainer(at: url)
        let restored = try #require(
            try LoanContractStore(context: reopened.mainContext).contract(for: accountID)
        )
        #expect(restored.terms == terms)

        // И обратно в форму: пользователь видит ровно то, что вводил.
        let restoredDraft = LoanTermsDraft(terms: restored.terms)
        #expect(restoredDraft.termMonths == 60)
        #expect(restoredDraft.frequency == .quarterly)
        #expect(restoredDraft.scheduleType == .differentiated)
        #expect(restoredDraft.isManualPayment)
    }

    @Test("Повторная правка условий не плодит вторую строку и не сбрасывает прогресс погашения")
    func editKeepsSingleRowAndProgress() throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }

        let accountID = UUID()
        do {
            let container = try makeContainer(at: url)
            let context = container.mainContext
            try LoanContractStore(context: context).upsert(accountID: accountID) { contract in
                contract.principal = 1_200_000
                contract.annualRatePercent = 18.9
                contract.termPeriods = 60
                contract.paymentsMade = 5
                contract.paidInterestTotal = 92_554
            }
            try context.save()
        }

        do {
            let container = try makeContainer(at: url)
            let context = container.mainContext
            // Правка условий трогает только условия — накопители прогресса это факт погашения,
            // а не поле договора, и сбрасываться при смене срока они не должны.
            try LoanContractStore(context: context).upsert(accountID: accountID) { contract in
                contract.termPeriods = 48
            }
            try context.save()
        }

        let reopened = try makeContainer(at: url)
        let rows = try reopened.mainContext.fetch(FetchDescriptor<LoanContract>())
        #expect(rows.count == 1)
        #expect(rows.first?.termPeriods == 48)
        #expect(rows.first?.paymentsMade == 5)
        #expect(rows.first?.paidInterestTotal == 92_554)
    }
}
