import Foundation
import SwiftData
import Testing
@testable import millio

/// Тесты моста «старый флоу добавления счёта → новое ядро» (Фаза 1a-ui).
@Suite("AccountsCoreAdditionBridge")
struct AccountsCoreAdditionBridgeTests {

    private func makeContainer() throws -> ModelContainer {
        try AppMigrationPlan.makeInMemoryContainer()
    }

    // MARK: - cardKind

    @Test
    func cardKindOtherBankIsCash() {
        #expect(AccountsCoreAdditionBridge.cardKind(bank: .other) == .cash)
    }

    @Test
    func cardKindRealBankIsDebitCard() {
        #expect(AccountsCoreAdditionBridge.cardKind(bank: .sberbank) == .debitCard)
        #expect(AccountsCoreAdditionBridge.cardKind(bank: .tinkoff) == .debitCard)
    }

    // MARK: - resolveAccountGroup

    @Test @MainActor
    func resolveAccountGroupReturnsNilForNilFinanceGroup() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        #expect(AccountsCoreAdditionBridge.resolveAccountGroup(matching: nil, in: ctx) == nil)
    }

    @Test @MainActor
    func resolveAccountGroupCreatesNewGroupByName() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let financeGroup = FinanceGroup(name: "Мои карты", colorHex: "#123456")
        ctx.insert(financeGroup)

        let resolved = AccountsCoreAdditionBridge.resolveAccountGroup(matching: financeGroup, in: ctx)
        #expect(resolved?.name == "Мои карты")

        let descriptor = FetchDescriptor<AccountGroup>()
        let allGroups = try ctx.fetch(descriptor)
        #expect(allGroups.count == 1)
    }

    @Test @MainActor
    func resolveAccountGroupReusesExistingGroupWithSameName() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = AccountGroup(name: "Вклады")
        ctx.insert(existing)
        try ctx.save()

        let financeGroup = FinanceGroup(name: "Вклады")
        ctx.insert(financeGroup)

        let resolved = AccountsCoreAdditionBridge.resolveAccountGroup(matching: financeGroup, in: ctx)
        #expect(resolved?.id == existing.id)

        let descriptor = FetchDescriptor<AccountGroup>()
        let allGroups = try ctx.fetch(descriptor)
        #expect(allGroups.count == 1) // не задублировали
    }

    // MARK: - loanMeta/debtMeta (Фаза 2 — формы «Кредит»/«Долг» → new-core meta)

    @Test
    func loanMetaMapsFormFieldsAndDefaultsRateToZero() {
        let termEnd = Date(timeIntervalSince1970: 1_800_000_000)
        let meta = AccountsCoreAdditionBridge.loanMeta(
            principal: 500_000, monthlyPayment: 15_000, paymentDay: 10, termEnd: termEnd
        )
        #expect(meta.principal == 500_000)
        #expect(meta.rate == 0) // старая форма не собирает ставку — сохраняем этот же пробел
        #expect(meta.monthlyPayment == 15_000)
        #expect(meta.paymentDay == 10)
        #expect(meta.termEnd == termEnd)
        #expect(meta.scheduleType == .annuity)
    }

    @Test
    func debtMetaCarriesDirectionOnly() {
        let owedToMe = AccountsCoreAdditionBridge.debtMeta(direction: .owedToMe)
        #expect(owedToMe.direction == .owedToMe)
        #expect(owedToMe.counterparty == nil)
        #expect(owedToMe.dueDate == nil)

        let owedByMe = AccountsCoreAdditionBridge.debtMeta(direction: .owedByMe)
        #expect(owedByMe.direction == .owedByMe)
    }

    // MARK: - depositMeta (Фаза 3 — форма «Вклад»/«Накопительный счёт» → new-core meta)

    @Test
    func depositMetaMapsFormFieldsAndConvertsPenaltyToShare() {
        let termEnd = Date(timeIntervalSince1970: 1_800_000_000)
        let meta = AccountsCoreAdditionBridge.depositMeta(
            rate: 12, capitalization: .monthly, termEnd: termEnd,
            allowsTopUp: false, allowsEarlyClose: true, earlyClosePenaltyShare: 0.5,
            remindEnd: true, autoRollover: false
        )
        #expect(meta.rate == 12)
        #expect(meta.capitalization == .monthly)
        #expect(meta.termEnd == termEnd)
        #expect(meta.allowsTopUp == false)
        #expect(meta.allowsEarlyClose == true)
        #expect(meta.earlyClosePenalty == 0.5)
        #expect(meta.remindEnd == true)
        #expect(meta.autoRollover == false)
    }

    @Test
    func depositMetaSavingsAccountHasNilTermEnd() {
        let meta = AccountsCoreAdditionBridge.depositMeta(
            rate: 8, capitalization: .monthly, termEnd: nil,
            allowsTopUp: true, allowsEarlyClose: false, earlyClosePenaltyShare: nil,
            remindEnd: false, autoRollover: false
        )
        #expect(meta.termEnd == nil) // накопительный счёт — без срока, тот же движок B
    }

    @Test
    func depositMetaDropsPenaltyWhenEarlyCloseNotAllowed() {
        // Если досрочное закрытие запрещено — penalty бессмысленен, даже если форма его собрала.
        let meta = AccountsCoreAdditionBridge.depositMeta(
            rate: 10, capitalization: .none, termEnd: Date(), allowsTopUp: false,
            allowsEarlyClose: false, earlyClosePenaltyShare: 0.3, remindEnd: false, autoRollover: false
        )
        #expect(meta.earlyClosePenalty == nil)
    }

    // MARK: - marketMeta/manualAssetMeta (Фаза 4 — пресеты «Акции»/«Крипта»/недвижимость/бизнес/другое)

    @Test
    func marketMetaUppercasesSymbolAndDefaultsToStock() {
        let meta = AccountsCoreAdditionBridge.marketMeta(symbol: "aapl", category: .stocks)
        #expect(meta.symbol == "AAPL")
        #expect(meta.assetClass == .stock)
    }

    @Test
    func marketMetaUsesCryptoAssetClassOnlyForCryptoCategory() {
        let crypto = AccountsCoreAdditionBridge.marketMeta(symbol: "btc", category: .crypto)
        #expect(crypto.assetClass == .crypto)

        // «Инвестиция» универсальная (category=.other) с тикером — по умолчанию акция, не облигация/металл
        // (форма их не собирает — нет UI-пути отличить, см. докстринг).
        let genericWithTicker = AccountsCoreAdditionBridge.marketMeta(symbol: "voo", category: .other)
        #expect(genericWithTicker.assetClass == .stock)
    }

    @Test
    func manualAssetMetaHasEmptyOptionalFieldsByDefault() {
        let meta = AccountsCoreAdditionBridge.manualAssetMeta()
        #expect(meta.revalReminderMonths == nil)
        #expect(meta.depreciationRatePerYear == nil)
        #expect(meta.linkedLoanID == nil)
    }

    // MARK: - moneyKind/obligationKind (Фаза 6a — регресс: правка легаси-счёта не должна создавать дубликат)

    @Test
    func moneyKindResolvesCardAndBankAccountWhenCreating() {
        #expect(
            AccountsCoreAdditionBridge.moneyKind(
                accountType: .card, investmentPreset: .asset, bank: .sberbank, isEditingLegacy: false
            ) == .debitCard
        )
        #expect(
            AccountsCoreAdditionBridge.moneyKind(
                accountType: .investment, investmentPreset: .account, bank: .other, isEditingLegacy: false
            ) == .bankAccount
        )
    }

    @Test
    func moneyKindReturnsNilWhenEditingExistingLegacyAccount() {
        // Баг Фазы 6a: без этой проверки открытие формы для правки существующей легаси `Card`
        // создавало НОВЫЙ Account вместо обновления старой записи.
        #expect(
            AccountsCoreAdditionBridge.moneyKind(
                accountType: .card, investmentPreset: .asset, bank: .sberbank, isEditingLegacy: true
            ) == nil
        )
        #expect(
            AccountsCoreAdditionBridge.moneyKind(
                accountType: .investment, investmentPreset: .account, bank: .other, isEditingLegacy: true
            ) == nil
        )
    }

    @Test
    func obligationKindResolvesLoanAndDebtWhenCreating() {
        #expect(
            AccountsCoreAdditionBridge.obligationKind(
                accountType: .credit, investmentCategory: .other, isEditingLegacy: false
            ) == .loan
        )
        #expect(
            AccountsCoreAdditionBridge.obligationKind(
                accountType: .investment, investmentCategory: .debt, isEditingLegacy: false
            ) == .debt
        )
    }

    @Test
    func obligationKindReturnsNilWhenEditingExistingLegacyAccount() {
        #expect(
            AccountsCoreAdditionBridge.obligationKind(
                accountType: .credit, investmentCategory: .other, isEditingLegacy: true
            ) == nil
        )
        #expect(
            AccountsCoreAdditionBridge.obligationKind(
                accountType: .investment, investmentCategory: .debt, isEditingLegacy: true
            ) == nil
        )
    }
}
