import Foundation
import SwiftData

/// Мост «старый флоу добавления счёта → новое ядро event-sourcing» (Фаза 1a-ui, 2, 3, 4).
/// Пресеты «Карта»/«Счёт» (Фаза 1a), «Кредит»/«Долг» (Фаза 2), «Вклад» (Фаза 3) и «Акции»/«Крипта»/
/// «Инвестиция»/«Недвижимость»/«Бизнес»/«Другое» (Фаза 4) создают `Account` нового ядра вместо
/// `Card`/`Credit`/`Investment`. Полный перенос экрана добавления и снос старых моделей — Фаза 6.
enum AccountsCoreAdditionBridge {

    /// Persisted product identity is derived from explicit form intent, never from bank presence.
    /// In particular, a credit card without a selected bank remains a credit card.
    static func moneyProductType(
        accountType: FinanceAccountType,
        investmentPreset: FinanceAddAccountInvestmentPreset,
        cardType: CardType?
    ) -> AccountProductType? {
        switch accountType {
        case .card:
            return cardType == .credit ? .creditCard : .debitCard
        case .investment where investmentPreset == .account:
            return .bankAccount
        default:
            return nil
        }
    }

    static func obligationProductType(kind: AccountKind, direction: DebtDirection?) -> AccountProductType? {
        switch kind {
        case .loan: return .loan
        case .debt where direction == .owedToMe: return .receivable
        case .debt where direction == .owedByMe: return .payable
        default: return nil
        }
    }

    static func assetProductType(
        category: InvestmentCategory,
        preset: FinanceAddAccountInvestmentPreset,
        hasTicker: Bool
    ) -> AccountProductType? {
        switch category {
        case .stocks: return .marketStock
        case .crypto: return .marketCrypto
        case .bonds: return .marketBond
        case .metals: return .marketMetal
        case .car: return .vehicle
        case .house: return .realEstate
        case .business: return .business
        case .other where preset == .asset:
            return hasTicker ? .genericMarketInvestment : .otherManualAsset
        case .other where preset == .category:
            return .otherManualAsset
        case .other:
            return nil
        case .debt:
            return nil
        }
    }

    /// kind для денежного пресета «Карта»: пустой/невыбранный банк (`.other`) трактуется как
    /// наличка без банка (спека §2.7, п. 63 — «наличка — вариант карты без банка»).
    /// Это временная эвристика до появления отдельного UI-пресета «Наличка».
    static func cardKind(bank: Bank) -> AccountKind {
        // Compatibility API for old tests/readers. New creation uses `moneyProductType` and the
        // catalog canonical kind. A missing bank is not evidence that the user meant cash.
        .debitCard
    }

    /// kind нового ядра для денежных пресетов («Карта»/«Счёт»), либо `nil`, если это не денежный
    /// пресет ИЛИ идёт редактирование СУЩЕСТВУЮЩЕГО легаси-счёта (`isEditingLegacy`).
    /// Фикс бага Фазы 6a: без проверки `isEditingLegacy` открытие формы для правки существующей
    /// легаси `Card`/`Investment(account)` создавало НОВЫЙ Account вместо обновления старой записи
    /// (`FinanceAddAccountView.newCoreMoneyKindForCurrentSelection` не учитывал `editingCard`/`editingInvestment`) —
    /// правка легаси-счёта осталась старым путём (`updateCard`/`updateInvestment`), редактирование
    /// new-core счетов — через `AccountDetailView`, не эту форму.
    static func moneyKind(
        accountType: FinanceAccountType,
        investmentPreset: FinanceAddAccountInvestmentPreset,
        bank: Bank,
        isEditingLegacy: Bool
    ) -> AccountKind? {
        guard !isEditingLegacy else { return nil }
        switch accountType {
        case .card:
            return cardKind(bank: bank)
        case .investment where investmentPreset == .account:
            return .bankAccount
        default:
            return nil
        }
    }

    /// kind нового ядра для пресетов «Кредит»/«Долг», либо `nil` — та же логика и та же причина,
    /// что у `moneyKind` (Фаза 6a): редактирование существующего легаси `Credit`/`Investment(debt)`
    /// не должно создавать новый Account.
    static func obligationKind(
        accountType: FinanceAccountType,
        investmentCategory: InvestmentCategory,
        isEditingLegacy: Bool
    ) -> AccountKind? {
        guard !isEditingLegacy else { return nil }
        switch accountType {
        case .credit:
            return .loan
        case .investment where investmentCategory == .debt:
            return .debt
        default:
            return nil
        }
    }

    /// Находит `AccountGroup` с тем же именем, что у выбранной `FinanceGroup`, либо создаёт новую.
    /// Мэппинг по имени (`AccountGroup` — канон после Фазы 1.5 плана 6b «Путь B»). Перенос остальных
    /// полей (`isFavorite`/`usesManualAccountOrdering`/`priorityRaw`/`displayCurrency`/`order`) с легаси-
    /// группы выполняет одноразовый `GroupsMigrator` при старте — здесь только резолвит/создаёт по имени
    /// и переносит `colorHex` для только что созданной группы. `nil` (счёт без группы = Ungrouped)
    /// не создаёт AccountGroup — совпадает с семантикой Ungrouped нового ядра (`account.group == nil`).
    static func resolveAccountGroup(matching financeGroup: FinanceGroup?, in modelContext: ModelContext) -> AccountGroup? {
        resolveAccountGroup(matchingName: financeGroup?.name, colorHex: financeGroup?.colorHex, in: modelContext)
    }

    /// Резолв/создание `AccountGroup` по ИМЕНИ легаси-группы — общая точка для всех, у кого на руках
    /// только имя (не сама `FinanceGroup`). Единственная реализация Ungrouped-гарда ядра: `nil`/пустое
    /// имя/любое из `allKnownUngroupedNames` → `nil` (счёт без группы, `account.group == nil`), core-
    /// сущность НЕ материализуется. Ф5c.7.3: сюда сведены `FinanceViewModel.resolveCoreGroup` и
    /// `LegacyAccountsMigrator.resolveCoreGroup`, ранее гардившие Ungrouped только по имени ТЕКУЩЕЙ
    /// локали (`ungroupedName`) — кросс-локальный легаси-Ungrouped там материализовался второй
    /// core-сущностью мимо этого гарда (Fable-резидуал 5c.7.1). Инвариант больше не зависит от памяти
    /// вызывающего и от текущего языка.
    static func resolveAccountGroup(matchingName name: String?, colorHex: String? = nil, in modelContext: ModelContext) -> AccountGroup? {
        guard let targetName = name,
              !targetName.isEmpty,
              !FinanceSystemGroups.allKnownUngroupedNames.contains(targetName) else { return nil }

        let descriptor = FetchDescriptor<AccountGroup>(
            predicate: #Predicate<AccountGroup> { $0.name == targetName }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let newGroup = AccountGroup(name: targetName, colorHex: colorHex)
        modelContext.insert(newGroup)
        return newGroup
    }

    /// Мэппинг формы «Кредит» старого мира → `LoanMeta` (Фаза 2). Старая форма НЕ собирает
    /// процентную ставку (`Credit.interestRate` всегда 0 при создании, см. `CreditViewModel.updateCredit`) —
    /// сохраняем этот же пробел (0), а не придумываем поле задним числом: schedule/rate UI — Фаза 3.
    /// `scheduleType` тоже не собирается формой — дефолт `.annuity` не используется расчётами в скоупе M
    /// (график погашения — вне скоупа), это просто безопасное значение по умолчанию.
    static func loanMeta(
        principal: Decimal,
        monthlyPayment: Decimal?,
        paymentDay: Int?,
        termEnd: Date?
    ) -> LoanMeta {
        LoanMeta(
            principal: principal,
            rate: 0,
            monthlyPayment: monthlyPayment,
            paymentDay: paymentDay,
            termEnd: termEnd,
            scheduleType: .annuity,
            insurance: nil
        )
    }

    /// Мэппинг формы «Долг» старого мира (Investment.category == .debt) → `DebtMeta`. Направление
    /// берётся из существующего `InvestmentType` (.positive = мне должны, .negative = я должен) —
    /// это ЕДИНСТВЕННОЕ поле направления, которое собирает старая форма. Контрагент/срок возврата
    /// старая форма не собирает вовсе (нет UI-поля) — оставляем nil, а не редизайним форму (вне скоупа).
    static func debtMeta(direction: DebtDirection) -> DebtMeta {
        DebtMeta(direction: direction, counterparty: nil, dueDate: nil, rate: nil)
    }

    /// kind нового ядра для пресета «Вклад»/«Накопительный счёт» (Фаза 3), либо `nil` — та же
    /// логика `isEditingLegacy`, что у `moneyKind`/`obligationKind` (Фаза 6a).
    static func depositKind(
        accountType: FinanceAccountType,
        investmentPreset: FinanceAddAccountInvestmentPreset,
        isEditingLegacy: Bool
    ) -> AccountKind? {
        guard !isEditingLegacy, accountType == .investment, investmentPreset == .deposit else { return nil }
        return .deposit
    }

    /// kind нового ядра для пресетов «Акции»/«Крипта»/«Недвижимость»/«Бизнес»/«Другое»/«Инвестиция»
    /// (Фаза 4), либо `nil` («Долг» сюда не входит — см. `obligationKind`). «Инвестиция»
    /// (category=.other, preset=.asset) — по наличию тикера (`hasTicker`): тикер есть → рыночный
    /// счёт, нет → ручной актив (брифинг Фазы 4, задача 1).
    static func assetKind(
        accountType: FinanceAccountType,
        investmentCategory: InvestmentCategory,
        investmentPreset: FinanceAddAccountInvestmentPreset,
        hasTicker: Bool,
        isEditingLegacy: Bool
    ) -> AccountKind? {
        guard !isEditingLegacy, accountType == .investment else { return nil }
        switch investmentCategory {
        case .stocks, .crypto:
            return .marketInvestment
        case .house, .business:
            return .manualAsset
        case .other where investmentPreset == .category:
            return .manualAsset
        case .other where investmentPreset == .asset:
            return hasTicker ? .marketInvestment : .manualAsset
        default:
            return nil
        }
    }

    /// Мэппинг символа тикера формы «Акции»/«Крипта»/«Инвестиция» → `MarketMeta` (Фаза 4).
    /// Класс актива определяется ТОЛЬКО категорией `.crypto` — облигации/металлы не собираются
    /// текущей формой (нет UI-пути), дефолт `.stock` безопасен и для «универсальной» инвестиции с тикером.
    static func marketMeta(symbol: String, category: InvestmentCategory) -> MarketMeta {
        let assetClass: MarketAssetClass = switch category {
        case .crypto: .crypto
        case .bonds: .bond
        case .metals: .metal
        default: .stock
        }
        return MarketMeta(symbol: symbol.uppercased(), assetClass: assetClass)
    }

    /// Мэппинг ручного актива (недвижимость/бизнес/другое/«инвестиция» без тикера) → `ManualAssetMeta`
    /// (Фаза 4). Старая форма не собирает ни напоминание о переоценке, ни амортизацию — пустые поля,
    /// а не выдуманные значения (тот же принцип, что и в `loanMeta`/`debtMeta` выше).
    static func manualAssetMeta() -> ManualAssetMeta {
        ManualAssetMeta(revalReminderMonths: nil, depreciationRatePerYear: nil, linkedLoanID: nil)
    }

    /// Мэппинг новой формы «Вклад»/«Накопительный счёт» (Фаза 3, `InlineDepositCreateForm`) →
    /// `DepositMeta`. Накопительный счёт — тот же движок, `termEnd == nil` (переключатель «без срока»
    /// в форме, НЕ отдельный пресет-экран, план §2.8). `earlyClosePenalty` собирается формой уже как
    /// ДОЛЯ 0…1 (см. докстринг `DepositMeta.earlyClosePenalty`) — форма сама делит %-ввод на 100.
    static func depositMeta(
        rate: Decimal,
        capitalization: AccountDepositCapitalization,
        termEnd: Date?,
        allowsTopUp: Bool,
        allowsEarlyClose: Bool,
        earlyClosePenaltyShare: Decimal?,
        remindEnd: Bool,
        autoRollover: Bool,
        isTaxable: Bool
    ) -> DepositMeta {
        DepositMeta(
            rate: rate,
            capitalization: capitalization,
            termEnd: termEnd,
            payoutDay: nil,
            allowsTopUp: allowsTopUp,
            allowsEarlyClose: allowsEarlyClose,
            earlyClosePenalty: allowsEarlyClose ? earlyClosePenaltyShare : nil,
            remindEnd: remindEnd,
            autoRollover: autoRollover,
            isTaxable: isTaxable
        )
    }
}
