import Foundation
import Testing
@testable import millio

/// Ф3 кредита: черновик формы «Условия кредита» — единственная часть экрана с логикой.
///
/// Проверяем ровно то, что форма не имеет права посчитать сама: разбор текстовых полей,
/// пересчёт срока «месяцы → периоды» при смене периодичности и то, что платёж-подсказка
/// приходит из ядра, а не из вью.
@Suite("LoanTermsDraft")
struct LoanTermsDraftTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var firstPayment: Date {
        calendar.date(from: DateComponents(year: 2025, month: 2, day: 10))!
    }

    private func referenceDraft() -> LoanTermsDraft {
        var draft = LoanTermsDraft(firstPaymentDate: firstPayment)
        draft.principalText = "1200000"
        draft.ratePercentText = "18.9"
        draft.termMonths = 60
        return draft
    }

    private func rubles(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var mutable = value
        NSDecimalRound(&result, &mutable, 0, .plain)
        return result
    }

    // MARK: - Сбор условий

    @Test("Эталонный черновик собирается в условия ядра")
    func referenceDraftProducesTerms() throws {
        let terms = try #require(referenceDraft().terms)
        #expect(terms.principal == 1_200_000)
        #expect(terms.annualRatePercent == 18.9)
        #expect(terms.termPeriods == 60)
        #expect(terms.frequency == .monthly)
        #expect(terms.scheduleType == .annuity)
        #expect(terms.paymentOverride == nil)
    }

    @Test("Подсказка о платеже берётся из ядра: 31 063 ₽")
    func calculatedPaymentMatchesEngine() throws {
        let payment = try #require(referenceDraft().calculatedPayment)
        #expect(rubles(payment) == 31_063)
    }

    @Test("Пустая сумма или пустая ставка — условий нет")
    func incompleteDraftHasNoTerms() {
        var draft = referenceDraft()
        draft.principalText = ""
        #expect(draft.terms == nil)

        draft = referenceDraft()
        draft.ratePercentText = ""
        #expect(draft.terms == nil)
    }

    @Test("Нулевая сумма кредита условий не даёт")
    func zeroPrincipalHasNoTerms() {
        var draft = referenceDraft()
        draft.principalText = "0"
        #expect(draft.terms == nil)
    }

    @Test("Срок 0 без ручного платежа условий не даёт, с ручным — даёт открытый график")
    func zeroTermRequiresManualPayment() throws {
        var draft = referenceDraft()
        draft.termMonths = 0
        #expect(draft.terms == nil)

        draft.isManualPayment = true
        draft.paymentText = "31063"
        let terms = try #require(draft.terms)
        #expect(terms.termPeriods == 0)
        #expect(terms.paymentOverride == 31_063)
    }

    // MARK: - Срок и периодичность

    @Test("Квартальная периодичность: 60 месяцев = 20 периодов")
    func quarterlyTermConvertsToPeriods() throws {
        var draft = referenceDraft()
        draft.frequency = .quarterly
        draft.alignTermToFrequency()
        #expect(draft.termMonths == 60)
        let terms = try #require(draft.terms)
        #expect(terms.termPeriods == 20)
    }

    @Test("Смена периодичности подтягивает срок вверх до кратного шагу")
    func alignTermRoundsUpToStep() {
        var draft = referenceDraft()
        draft.termMonths = 61
        draft.frequency = .quarterly
        draft.alignTermToFrequency()
        // 61 не делится на 3 нацело: без выравнивания termPeriods округлился бы вниз (20 периодов
        // = 60 месяцев) и график молча стал бы короче введённого срока.
        #expect(draft.termMonths == 63)
        #expect(draft.termPeriods == 21)
    }

    @Test("Годовая периодичность даёт варианты срока только кратные 12")
    func termOptionsFollowFrequencyStep() {
        var draft = referenceDraft()
        draft.frequency = .annual
        let options = draft.termMonthOptions
        #expect(options.first == 12)
        #expect(options.allSatisfy { $0 % 12 == 0 })
        #expect(options.last == LoanTermsDraft.maxTermMonths)
    }

    // MARK: - Ручной платёж

    @Test("Ручной платёж уходит в paymentOverride, выключенный тумблер его снимает")
    func manualPaymentBecomesOverride() throws {
        var draft = referenceDraft()
        draft.isManualPayment = true
        draft.paymentText = "31500"
        #expect(try #require(draft.terms).paymentOverride == 31_500)

        draft.isManualPayment = false
        // Текст поля намеренно НЕ стирается: человек может вернуть тумблер обратно.
        #expect(draft.paymentText == "31500")
        #expect(try #require(draft.terms).paymentOverride == nil)
    }

    @Test("Включённый тумблер с пустой суммой платежа условий не даёт")
    func manualPaymentWithoutAmountIsInvalid() {
        var draft = referenceDraft()
        draft.isManualPayment = true
        draft.paymentText = ""
        #expect(draft.terms == nil)
    }

    @Test("Подсказка показывает расчётный платёж, а не вписанный вручную")
    func calculatedPaymentIgnoresOverride() throws {
        var draft = referenceDraft()
        draft.isManualPayment = true
        draft.paymentText = "40000"
        #expect(rubles(try #require(draft.calculatedPayment)) == 31_063)
    }

    // MARK: - Сид из существующих условий

    @Test("Сид из условий и обратная сборка дают те же условия")
    func seedFromTermsRoundTrips() throws {
        let source = LoanTerms(
            principal: 1_200_000,
            annualRatePercent: 18.9,
            termPeriods: 20,
            firstPaymentDate: firstPayment,
            scheduleType: .differentiated,
            frequency: .quarterly,
            paymentOverride: 94_059
        )
        let draft = LoanTermsDraft(terms: source)
        #expect(draft.termMonths == 60)
        #expect(draft.isManualPayment)

        let rebuilt = try #require(draft.terms)
        #expect(rebuilt.principal == source.principal)
        #expect(rebuilt.annualRatePercent == source.annualRatePercent)
        #expect(rebuilt.termPeriods == source.termPeriods)
        #expect(rebuilt.firstPaymentDate == source.firstPaymentDate)
        #expect(rebuilt.scheduleType == source.scheduleType)
        #expect(rebuilt.frequency == source.frequency)
        #expect(rebuilt.paymentOverride == source.paymentOverride)
    }
}
