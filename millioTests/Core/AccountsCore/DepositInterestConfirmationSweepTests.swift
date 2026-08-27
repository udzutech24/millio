import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф1.5 плана `2026-08-26__deposit-confirmed-balance-unification.md`: авто-подтверждение
/// наступивших начислений (вариант A владельца) и защита от «воскрешения» прогноза,
/// уже поглощённого более поздней корректировкой баланса.
@Suite("Deposit interest confirmation sweep", .serialized)
@MainActor
struct DepositInterestConfirmationSweepTests {

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let accountID: UUID
        let opening: Date
        let calendar: Calendar
    }

    private func fixture() throws -> Fixture {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let maturity = calendar.date(byAdding: .month, value: 3, to: opening)!
        let accountID = try AccountProductFactory(modelContext: context).create(CreateProductCommand(
            productType: .deposit, name: "Deposit", currency: "RUB", openingBalance: 100_000,
            metadata: .init(deposit: DepositMeta(
                rate: 12, capitalization: .monthly, termEnd: maturity, payoutDay: nil,
                allowsTopUp: true, allowsEarlyClose: true, earlyClosePenalty: nil,
                remindEnd: false, autoRollover: false
            )),
            date: opening, calendar: calendar
        ))
        return Fixture(
            container: container, context: context, accountID: accountID,
            opening: opening, calendar: calendar
        )
    }

    private func deposit(_ fixture: Fixture) throws -> Account {
        try #require(fixture.context.fetch(FetchDescriptor<Account>()).first { $0.id == fixture.accountID })
    }

    private func confirmedBalance(_ fixture: Fixture, on date: Date) throws -> Decimal {
        let deposit = try deposit(fixture)
        return DepositConfirmedBalanceResolver.balanceAt(
            events: deposit.events ?? [], accountID: deposit.id, on: date
        )
    }

    @Test("Наступившее начисление подтверждается и входит в подтверждённый баланс")
    func dueForecastBecomesConfirmed() throws {
        let fixture = try fixture()
        let asOf = fixture.calendar.date(from: DateComponents(year: 2025, month: 2, day: 15))!

        #expect(try confirmedBalance(fixture, on: asOf) == 100_000)

        let confirmed = DepositInterestConfirmationSweep.run(context: fixture.context, asOf: asOf)

        #expect(confirmed == 1)
        #expect(try confirmedBalance(fixture, on: asOf) == 101_000)

        // Будущие прогнозы остаются прогнозами.
        let depositAccount = try deposit(fixture)
        let stillGenerated = (depositAccount.events ?? []).filter {
            DepositConfirmedBalanceResolver.isGeneratedInterest($0, accountID: depositAccount.id)
        }
        #expect(stillGenerated.count == 2)
        #expect(stillGenerated.allSatisfy { $0.date > asOf })
    }

    @Test("Повторный прогон идемпотентен")
    func sweepIsIdempotent() throws {
        let fixture = try fixture()
        let asOf = fixture.calendar.date(from: DateComponents(year: 2025, month: 2, day: 15))!

        #expect(DepositInterestConfirmationSweep.run(context: fixture.context, asOf: asOf) == 1)
        let balanceAfterFirst = try confirmedBalance(fixture, on: asOf)

        #expect(DepositInterestConfirmationSweep.run(context: fixture.context, asOf: asOf) == 0)
        #expect(try confirmedBalance(fixture, on: asOf) == balanceAfterFirst)
        #expect(try deposit(fixture).events?.filter { $0.type == .interest }.count == 3)
    }

    /// Реальный кейс «Альфа 12%» (Ф0): прогноз от 12.08 пережил корректировку от 26.08.
    /// Подтвердить его задним числом = вернуть в баланс сумму, которую владелец только что списал.
    @Test("Прогноз, поглощённый более поздней корректировкой, не подтверждается, а вычищается")
    func forecastAbsorbedByLaterCorrectionIsPurged() throws {
        let fixture = try fixture()
        let correctionDate = fixture.calendar.date(from: DateComponents(year: 2025, month: 2, day: 10))!
        let asOf = fixture.calendar.date(from: DateComponents(year: 2025, month: 2, day: 15))!

        _ = try DepositOperationCoordinator(modelContext: fixture.context).adjustBalance(
            depositID: fixture.accountID,
            command: DepositBalanceAdjustmentCommand(
                operationID: "deposit-balance-adjustment:\(UUID().uuidString)",
                newBalance: 90_000,
                date: correctionDate,
                note: nil
            ),
            calendar: fixture.calendar
        )

        // Прогноз от 01.02 корректировку пережил — она удаляет только события ПОСЛЕ своей даты.
        let depositAccount = try deposit(fixture)
        let survivedForecast = (depositAccount.events ?? []).contains(where: { event in
            DepositConfirmedBalanceResolver.isGeneratedInterest(event, accountID: depositAccount.id)
                && event.date < correctionDate
        })
        #expect(survivedForecast)
        #expect(try confirmedBalance(fixture, on: asOf) == 90_000)

        let confirmed = DepositInterestConfirmationSweep.run(context: fixture.context, asOf: asOf)

        #expect(confirmed == 0)
        #expect(try confirmedBalance(fixture, on: asOf) == 90_000)
        let after = try deposit(fixture)
        let hasPastInterest = (after.events ?? []).contains(where: { event in
            event.type == .interest && event.date <= correctionDate
        })
        #expect(!hasPastInterest)

        // И повторный прогон не воскрешает удалённый прогноз.
        #expect(DepositInterestConfirmationSweep.run(context: fixture.context, asOf: asOf) == 0)
        #expect(try confirmedBalance(fixture, on: asOf) == 90_000)
    }

    @Test("Триггер: развёртка запускается из прохода планировщика")
    func schedulerPassRunsTheSweep() throws {
        let fixture = try fixture()
        let asOf = fixture.calendar.date(from: DateComponents(year: 2025, month: 2, day: 15))!

        DepositInterestScheduler.extendActiveDepositHorizons(
            context: fixture.context, asOf: asOf, calendar: fixture.calendar
        )

        #expect(try confirmedBalance(fixture, on: asOf) == 101_000)
    }
}
