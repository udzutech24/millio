import SwiftUI
import SwiftData
import PhotosUI

/// Создание счёта в новом ядре: резолверы `AccountKind` по пресету и команды создания.
extension FinanceAddAccountView {
    /// kind нового ядра для текущего выбора пресета «Карта»/«Счёт» — `nil` для остальных
    /// пресетов (вклад/инвестиции/… — свои резолверы). Форма теперь только для СОЗДАНИЯ:
    /// EDIT-путь легаси снесён (6b Ф5c.3), поэтому `isEditingLegacy: false`. Защитный гуард
    /// `isEditingLegacy` в мосте сохранён (гард-тест `AllPresetsOnNewCoreTests`, анамнез Фазы 6a).
    var newCoreMoneyKindForCurrentSelection: AccountKind? {
        return AccountsCoreAdditionBridge.moneyKind(
            accountType: selectedAccountType,
            investmentPreset: selectedInvestmentPreset,
            bank: cardData?.bank ?? .other,
            isEditingLegacy: false
        )
    }

    /// kind нового ядра для пресетов «Кредит»/«Долг» (Фаза 2) — `nil` для остальных пресетов
    /// и для режима редактирования (та же причина и фикс Фазы 6a, см. `newCoreMoneyKindForCurrentSelection`).
    var newCoreObligationKindForCurrentSelection: AccountKind? {
        return AccountsCoreAdditionBridge.obligationKind(
            accountType: selectedAccountType,
            investmentCategory: selectedInvestmentCategory,
            isEditingLegacy: false
        )
    }

    /// kind нового ядра для пресета «Вклад»/«Накопительный счёт» (Фаза 3) — `nil` для остальных
    /// пресетов и для режима редактирования (правка depositMeta — через `AccountDetailView`, не эту форму).
    var newCoreDepositKindForCurrentSelection: AccountKind? {
        return AccountsCoreAdditionBridge.depositKind(
            accountType: selectedAccountType,
            investmentPreset: selectedInvestmentPreset,
            isEditingLegacy: false
        )
    }

    /// kind нового ядра для пресетов «Акции»/«Крипта»/«Недвижимость»/«Бизнес»/«Другое»/«Инвестиция»
    /// (Фаза 4) — `nil` для остальных пресетов (карта/счёт/вклад/кредит/долг — уже обработаны выше)
    /// и для режима редактирования. «Долг» сюда НЕ попадает — обработан `newCoreObligationKindForCurrentSelection`.
    var newCoreAssetKindForCurrentSelection: AccountKind? {
        let hasTicker = investmentData?.marketData?.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return AccountsCoreAdditionBridge.assetKind(
            accountType: selectedAccountType,
            investmentCategory: selectedInvestmentCategory,
            investmentPreset: selectedInvestmentPreset,
            hasTicker: hasTicker,
            isEditingLegacy: false
        )
    }

    /// Создание вклада/накопительного счёта на новом ядре (Фаза 3): создаёт счёт + сразу генерирует
    /// БУДУЩИЕ interest-события по расписанию капитализации (`DepositInterestScheduler`) — карточка
    /// счёта открывается уже с прогнозом «в месяц»/«за срок», без отдельного шага «посчитать».
    func createDepositAccountOnNewCore() {
        do {
            guard try AccountCreationCoordinator.finalizeDepositAccount(
                accountName: accountName,
                selectedProductTypeTitle: selectedProductTypeTitle,
                depositData: depositData,
                groupID: targetGroup?.id,  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
                draftIconName: draftIconName,
                draftIconColor: draftIconColor,
                modelContext: viewModel.modelContext
            ) != nil else { return }
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать вклад нового ядра: \(error)")
        }
    }

    /// Создание денежного счёта («Карта»/«Счёт») на новом ядре event-sourcing (Фаза 1a-ui).
    /// Никогда не создаёт старый `Card`/`Investment` — единственная точка записи: `AccountsCoreService`.
    func createMoneyAccountOnNewCore(kind: AccountKind) {
        do {
            guard try AccountCreationCoordinator.finalizeMoneyAccount(
                kind: kind,
                selectedProductOption: selectedProductOption,
                accountName: accountName,
                selectedProductTypeTitle: selectedProductTypeTitle,
                cardData: cardData,
                investmentData: investmentData,
                groupID: targetGroup?.id,  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
                draftIconName: draftIconName,
                draftIconColor: draftIconColor,
                modelContext: viewModel.modelContext
            ) != nil else { return }
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать денежный счёт нового ядра: \(error)")
        }
    }

    func moneyCreateCommand(kind: AccountKind, accountID: UUID = UUID()) throws -> CreateProductCommand {
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? selectedProductTypeTitle : trimmedName
        let currency: String
        let openingBalance: Decimal
        var cardMeta: CardMeta?

        switch kind {
        case .debitCard:
            guard let cardData else { throw AccountStatementOnboardingError.unsupportedProduct }
            currency = cardData.currency
            openingBalance = Decimal(cardData.balance)
            cardMeta = CardMeta(
                bank: cardData.bank == .other ? nil : cardData.bank.rawValue,
                last4: cardData.cardNumber.isEmpty ? nil : cardData.cardNumber,
                creditLimit: cardData.cardType == .credit ? cardData.creditLimit.map { Decimal($0) } : nil
            )
        default:
            guard let investmentData else { throw AccountStatementOnboardingError.unsupportedProduct }
            currency = investmentData.currency
            openingBalance = Decimal(investmentData.amount)
        }

        let resolved = try FinanceProductCreationCommandResolver.resolve(.init(
            option: selectedProductOption,
            name: resolvedName,
            currency: currency,
            amount: openingBalance,
            includeInTotal: cardData?.includeInTotal ?? investmentData?.includeInTotal ?? true,
            groupID: targetGroup?.id,
            cardType: cardData?.cardType,
            bank: cardData?.bank,
            cardLast4: cardData?.cardNumber,
            creditLimit: cardMeta?.creditLimit,
            statementDay: cardData?.statementDay,
            dueDay: cardData?.dueDay,
            minPayment: cardData?.minPayment.map { Decimal($0) },
            graceDays: cardData?.graceDays,
            note: cardData?.note
        ))
        return CreateProductCommand(
            accountID: accountID,
            productType: resolved.productType,
            name: resolved.name,
            currency: resolved.currency,
            openingBalance: resolved.openingBalance,
            includeInTotal: resolved.includeInTotal,
            order: resolved.order,
            groupID: resolved.groupID,
            metadata: resolved.metadata,
            note: resolved.note,
            date: resolved.date,
            initialMarketPurchase: resolved.initialMarketPurchase,
            calendar: resolved.calendar
        )
    }

    /// Создание обязательства («Кредит»/«Долг») на новом ядре event-sourcing (Фаза 2).
    /// Никогда не создаёт старый `Credit`/`Investment(debt)` — единственная точка записи: `AccountsCoreService`.
    func createObligationAccountOnNewCore(kind: AccountKind) {
        do {
            guard try AccountCreationCoordinator.finalizeObligationAccount(
                kind: kind,
                accountName: accountName,
                selectedProductTypeTitle: selectedProductTypeTitle,
                creditData: creditData,
                investmentData: investmentData,
                loanTermsDraft: loanTermsDraft,
                groupID: targetGroup?.id,  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
                draftIconName: draftIconName,
                draftIconColor: draftIconColor,
                modelContext: viewModel.modelContext
            ) != nil else { return }
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать обязательство нового ядра: \(error)")
        }
    }

    /// Создание рыночного/ручного актива на новом ядре event-sourcing (Фаза 4). Никогда не создаёт
    /// старый `Investment` — единственная точка записи: `AccountsCoreService`.
    func createAssetAccountOnNewCore(kind: AccountKind) {
        do {
            guard try AccountCreationCoordinator.finalizeAssetAccount(
                kind: kind,
                selectedProductOption: selectedProductOption,
                accountName: accountName,
                selectedProductTypeTitle: selectedProductTypeTitle,
                investmentData: investmentData,
                groupID: targetGroup?.id,  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
                realEstatePropertyType: realEstatePropertyType,
                realEstatePhotoData: realEstatePhotoData,
                draftIconName: draftIconName,
                draftIconColor: draftIconColor,
                modelContext: viewModel.modelContext
            ) != nil else { return }
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать актив нового ядра: \(error)")
        }
    }

    func addAccount() {
        guard validateEntitlementsForSave() else { return }

        if let newCoreKind = newCoreMoneyKindForCurrentSelection {
            createMoneyAccountOnNewCore(kind: newCoreKind)
            return
        }

        if newCoreDepositKindForCurrentSelection != nil {
            createDepositAccountOnNewCore()
            return
        }

        if let newCoreObligationKind = newCoreObligationKindForCurrentSelection {
            createObligationAccountOnNewCore(kind: newCoreObligationKind)
            return
        }

        if let newCoreAssetKind = newCoreAssetKindForCurrentSelection {
            createAssetAccountOnNewCore(kind: newCoreAssetKind)
            return
        }

        // Все 11 create-пресетов резолвятся в один core-kind выше (гард-тест
        // `AllPresetsOnNewCoreTests`) — легаси-writer'ы (Card/Credit/Investment) недостижимы
        // после сноса EDIT-пути (6b Ф5c.3). Сюда управление в норме не доходит.
    }
}
