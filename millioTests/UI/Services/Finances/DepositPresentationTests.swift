import Foundation
import SwiftUI
import Testing
@testable import millio

@Suite("Deposit presentation")
struct DepositPresentationTests {
    @Test func amountFormatterUsesGroupingAndTwoFractionDigitsAtMost() {
        let locale = Locale(identifier: "ru_RU")

        #expect(DepositAmountTextFormatter.string(47_808_499, currency: "RUB", locale: locale) == "47 808 499 RUB")
        #expect(DepositAmountTextFormatter.string(717_127.49, currency: "RUB", locale: locale) == "717 127,49 RUB")
        #expect(DepositAmountTextFormatter.string(8_507_471.600, currency: "RUB", locale: locale) == "8 507 471,6 RUB")
    }
    @Test @MainActor
    func requiredStatesRenderAtPhoneSizesWithAccessibilityText() throws {
        let sizes = [CGSize(width: 375, height: 812), CGSize(width: 390, height: 844)]
        let states: [DepositLifecycleState] = [
            .active, .openEnded, .dueSoon, .maturedNeedsAction, .closed, .incomplete
        ]
        for state in states {
            for size in sizes {
                let snapshot = renderSnapshot(state: state)
                let view = ScrollView {
                    DepositDetailSection(
                        presentation: .make(snapshot: snapshot), accountName: "Deposit", onAction: { _ in }
                    ).padding()
                }
                .frame(width: size.width, height: size.height)
                .environment(\.dynamicTypeSize, .accessibility3)
                let renderer = ImageRenderer(content: view)
                renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
                #expect(renderer.cgImage != nil)
            }
        }
    }

    @Test @MainActor
    func termsEditorRendersAtPhoneSizeWithLargeText() {
        let size = CGSize(width: 390, height: 844)
        let meta = DepositMeta(
            rate: 12.5,
            capitalization: .monthly,
            termEnd: Date().addingTimeInterval(365 * 86_400),
            payoutDay: 15,
            allowsTopUp: true,
            allowsEarlyClose: true,
            earlyClosePenalty: 0,
            remindEnd: true,
            autoRollover: false
        )
        // `DepositTermsInputCard` внутри требует AppState/AppRouter (PRO-гейт крипто-валют в пикере),
        // как и любой экран Финансов в приложении — без них SwiftUI падает на резолве Environment.
        let view = DepositTermsEditSheet(
            meta: meta,
            snapshot: renderSnapshot(state: .active),
            openingDate: Date(),
            currentNote: "Заметка",
            onSave: { _ in }
        )
        .environment(AppState())
        .environment(AppRouter())
        .frame(width: size.width, height: size.height)
        .environment(\.dynamicTypeSize, .accessibility3)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)

        #expect(renderer.cgImage != nil)
    }

    private func renderSnapshot(state: DepositLifecycleState) -> DepositPresentationSnapshot {
        .init(
            asOf: Date(), currency: "RUB", principal: .confirmed(100_000),
            confirmedInterest: .confirmed(5_000), estimatedDueInterest: .estimated(1_000),
            futureInterest: .estimated(10_000), currentBalance: .confirmed(105_000),
            projectedBalance: .estimated(115_000), availableToWithdraw: .unavailable,
            nextAccrual: .init(date: Date().addingTimeInterval(86_400), amount: .estimated(1_000)),
            maturityDate: Date().addingTimeInterval(30 * 86_400), maturityAmount: .estimated(115_000),
            daysRemaining: 30, progress: 0.7, lifecycleState: state,
            capabilities: .init(
                allowsTopUp: state == .active, allowsEarlyClose: state == .active,
                allowsWithdrawal: false, reminderIsOperational: false, autoRolloverIsOperational: false
            ),
            unresolved: state == .incomplete ? [.missingMetadata] : []
        )
    }
    private func snapshot(
        lifecycle: DepositLifecycleState,
        topUp: Bool = true,
        earlyClose: Bool = true,
        balance: Decimal = 110,
        confirmedInterest: Decimal = 10,
        due: Decimal = 2,
        future: Decimal = 8
    ) -> DepositPresentationSnapshot {
        DepositPresentationSnapshot(
            asOf: Date(), currency: "RUB", principal: .confirmed(100),
            confirmedInterest: .confirmed(confirmedInterest), estimatedDueInterest: .estimated(due),
            futureInterest: .estimated(future), currentBalance: .confirmed(balance),
            projectedBalance: .estimated(120), availableToWithdraw: .unavailable,
            nextAccrual: nil, maturityDate: Date().addingTimeInterval(86_400),
            maturityAmount: .estimated(120), daysRemaining: 1, progress: 0.9,
            lifecycleState: lifecycle,
            capabilities: .init(
                allowsTopUp: topUp, allowsEarlyClose: earlyClose, allowsWithdrawal: false,
                reminderIsOperational: false, autoRolloverIsOperational: false
            ),
            unresolved: []
        )
    }

    @Test("Actions are driven by capabilities and never expose generic writers")
    func capabilityActions() {
        #expect(DepositDetailPresentation.make(snapshot: snapshot(lifecycle: .active)).actions == [
            .topUp, .adjustBalance, .editTerms, .earlyClose, .archive
        ])
        #expect(DepositDetailPresentation.make(
            snapshot: snapshot(lifecycle: .active, topUp: false, earlyClose: false)
        ).actions == [.adjustBalance, .editTerms, .archive])
    }

    @Test("Matured and archived states are explicit and archived is read only")
    func lifecycleActions() {
        let matured = DepositDetailPresentation.make(snapshot: snapshot(lifecycle: .maturedNeedsAction))
        #expect(matured.state == .maturedNeedsAction)
        #expect(matured.actions == [.withdrawAtMaturity])

        let archived = DepositDetailPresentation.make(snapshot: snapshot(lifecycle: .closed))
        #expect(archived.state == .archived)
        #expect(archived.actions.isEmpty)
    }

    @Test("Early close preview separates forecast, penalty and net proceeds")
    func earlyClosePreview() {
        let preview = DepositDetailPresentation.earlyClosePreview(
            snapshot: snapshot(lifecycle: .active), penaltyShare: 0.5
        )
        #expect(preview == .init(lostInterest: 10, penalty: 5, netProceeds: 105))
    }

    @Test("Generated interest is forecast and cannot enter historical UI")
    func forecastEventClassification() {
        let accountID = UUID()
        let generated = AccountEvent(
            date: Date(), type: .interest, amount: 10,
            sourceTransactionID: "deposit-interest:\(accountID.uuidString):2026-08-31"
        )
        let confirmed = AccountEvent(
            date: Date(), type: .interest, amount: 10,
            sourceTransactionID: "bank-confirmation:2026-08"
        )
        #expect(DepositDetailPresentation.isGeneratedForecastEvent(generated, accountID: accountID))
        #expect(!DepositDetailPresentation.isGeneratedForecastEvent(confirmed, accountID: accountID))
    }

    @Test("Creation preview validates term combinations and estimates ACT/365 income")
    func creationPreview() {
        let opening = Date(timeIntervalSince1970: 1_735_689_600)
        let maturity = opening.addingTimeInterval(365 * 86_400)
        let valid = DepositCreationPreview.make(
            amount: 100_000, rate: 10, openingDate: opening, termEnd: maturity,
            hasTerm: true, earlyClosePenaltyPercent: 50, allowsEarlyClose: true,
            remindEnd: true, autoRollover: false
        )
        #expect(valid.isValid)
        #expect(valid.interest == 10_000)
        #expect(valid.maturityAmount == 110_000)

        let invalid = DepositCreationPreview.make(
            amount: 100, rate: 10, openingDate: opening, termEnd: nil,
            hasTerm: false, earlyClosePenaltyPercent: 101, allowsEarlyClose: true,
            remindEnd: true, autoRollover: true
        )
        #expect(invalid.errors.contains(.invalidPenalty))
        #expect(invalid.errors.contains(.termRequiredForLifecycleOption))
    }

    /// Бессрочный вклад/накопительный счёт: срока нет, но доход показывать обязаны — иначе поле
    /// «доход» пустое при полностью заполненной форме. Считается условное окно в 30 дней,
    /// «суммы к концу срока» при этом по-прежнему нет.
    @Test("Open-ended deposit still previews income but has no maturity amount")
    func openEndedPreviewIsNotEmpty() {
        let preview = DepositCreationPreview.make(
            amount: 100_000, rate: 12, openingDate: Date(), termEnd: nil,
            hasTerm: false, earlyClosePenaltyPercent: 0, allowsEarlyClose: true,
            remindEnd: false, autoRollover: false
        )

        #expect(preview.isValid)
        #expect(preview.maturityAmount == nil)
        // 100 000 × 12% × 30/365 = 986,30
        #expect(preview.interest == Decimal(string: "986.30")!)
        #expect(DepositCreationPreview.openEndedPreviewDays == 30)
    }

    /// Живая подсказка «доход за период» не должна ни падать, ни врать на вырожденном вводе.
    @Test("Period income hint is nil on degenerate input instead of crashing")
    func periodIncomeGuardsDegenerateInput() {
        #expect(DepositCreationPreview.interest(amount: 100_000, rate: 12, days: 0) == nil)
        #expect(DepositCreationPreview.interest(amount: nil, rate: 12, days: 30) == nil)
        #expect(DepositCreationPreview.interest(amount: 100_000, rate: nil, days: 30) == nil)
        #expect(DepositCreationPreview.interest(amount: 0, rate: 12, days: 30) == nil)
        #expect(DepositCreationPreview.interest(amount: -100, rate: 12, days: 30) == nil)
        #expect(DepositCreationPreview.interest(amount: 100_000, rate: 0, days: 30) == nil)
        #expect(DepositCreationPreview.interest(amount: 100_000, rate: 12, days: -5) == nil)
    }

    /// Длина периода для подсказки — всегда ≥ 1 дня, поэтому подсказка определена для ЛЮБОЙ
    /// периодичности, включая вырожденный `customDays(0)` из старых/битых данных.
    @Test("Every capitalization yields a usable preview period")
    func everyCapitalizationHasPositivePeriod() {
        let cases: [AccountDepositCapitalization] = [
            .none, .daily, .monthly, .quarterly, .customDays(45), .customDays(0)
        ]
        for option in cases {
            #expect(option.approximatePeriodDays >= 1)
            #expect(
                DepositCreationPreview.interest(
                    amount: 100_000, rate: 12, days: option.approximatePeriodDays
                ) != nil
            )
        }
    }
}
