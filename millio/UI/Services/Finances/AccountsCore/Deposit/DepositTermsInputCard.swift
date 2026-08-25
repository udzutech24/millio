import SwiftUI

/// Общий блок ввода условий вклада: сумма и ставка на одной линии, под ними — периодичность
/// начисления, живая оценка дохода за период и тег «налогооблагаемый».
///
/// Один компонент на создание И на правку намеренно: пока это были две независимые формы, они
/// разъехались — в правке жил `payoutDay`, которого нет в создании, а суммы и валюты не было вовсе.
struct DepositTermsInputCard: View {
    @Binding var amountText: String
    @Binding var currency: String
    @Binding var rateText: String
    @Binding var capitalization: AccountDepositCapitalization
    @Binding var isTaxable: Bool
    /// Общий фокус с формой-хозяином: иначе кнопка «Готово» на клавиатуре не гасит наши поля.
    var isFocused: FocusState<Bool>.Binding
    /// В правке существующего счёта валюта только показывается. Смена валюты на событийном ядре —
    /// это деноминация (`AccountEventType.redenomination`), а не подмена поля: без неё вся прошлая
    /// лента молча переосмыслится в новой валюте. Писателя деноминации пока нет.
    var isCurrencyEditable: Bool = true

    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    @State private var showCurrencyPicker = false
    @State private var currencySearchText = ""
    @State private var showCryptoProAlert = false

    /// Стартовое значение произвольного периода — квартал «в днях», чтобы шаг был осмысленным
    /// с первого тапа и пользователю не пришлось крутить степпер от единицы.
    private static let defaultCustomDays = 90

    private var amount: Decimal? { AmountInputFormatter.parse(amountText).map { Decimal($0) } }
    private var rate: Decimal? { AmountInputFormatter.parse(rateText).map { Decimal($0) } }

    /// Единственный источник правды по произвольному периоду — сам `capitalization`.
    /// Отдельный `@State` для N неизбежно рассинхронизировался бы с моделью при внешнем изменении.
    private var customDaysBinding: Binding<Int> {
        Binding(
            get: { capitalization.customDays ?? Self.defaultCustomDays },
            set: { capitalization = .customDays(max(1, $0)) }
        )
    }

    private var periodIncome: Decimal? {
        DepositCreationPreview.interest(
            amount: amount,
            rate: rate,
            days: capitalization.approximatePeriodDays
        )
    }

    var body: some View {
        FinancesGlassCard(
            contentPadding: EdgeInsets(
                top: AppSpacing.l, leading: AppSpacing.l,
                bottom: AppSpacing.l, trailing: AppSpacing.l
            )
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                headlineRow
                Divider().overlay(AppColors.iconBackground)
                periodicitySelector
                incomeHint
                taxableChip
            }
        }
        .sheet(isPresented: $showCurrencyPicker) { currencyPickerSheet }
        .premiumUpsellAlert(
            isPresented: $showCryptoProAlert,
            titleKey: "monetization.crypto.pro_title",
            message: .key("monetization.crypto.pro_message"),
            onSubscribe: { router.push(.subscription) }
        )
    }

    // MARK: - Сумма и ставка на одной линии

    private var headlineRow: some View {
        HStack(alignment: .top, spacing: AppSpacing.l) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                fieldCaption(L("accounts_core.deposit_form.section.amount"))
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.s) {
                    AmountTextField(placeholder: "0", value: $amountText)
                        .font(.millioDisplay)
                        .foregroundStyle(AppColors.textPrimary)
                        .focused(isFocused)
                    currencyButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Capsule()
                .fill(AppColors.iconBackground)
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                fieldCaption(L("accounts_core.deposit_form.section.rate"))
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                    AmountTextField(placeholder: "0", value: $rateText)
                        .font(.millioTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .focused(isFocused)
                    Text(verbatim: "%")
                        .font(.millioTitle3)
                        .foregroundStyle(AppColors.brandPrimary)
                }
                Text(L("accounts_core.deposit_form.rate_suffix"))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .frame(width: 116)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var currencyButton: some View {
        if isCurrencyEditable {
            Button { showCurrencyPicker = true } label: {
                currencyLabel(showsChevron: true, tint: AppColors.brandPrimary)
            }
            .buttonStyle(.plain)
        } else {
            currencyLabel(showsChevron: false, tint: AppColors.textSecondary)
        }
    }

    private func currencyLabel(showsChevron: Bool, tint: Color) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Text(currency)
                .font(.millioCalloutSemibold)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.millioMicro)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, AppSpacing.s)
        .padding(.vertical, AppSpacing.xs)
        .background(Capsule().fill(AppColors.iconBackground))
    }

    // MARK: - Периодичность начисления

    private var periodicitySelector: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            fieldCaption(L("accounts_core.deposit_form.capitalization_label"))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.s), count: 3),
                spacing: AppSpacing.s
            ) {
                ForEach(AccountDepositCapitalization.presetCases, id: \.rawValue) { option in
                    periodChip(title: title(for: option), isSelected: capitalization == option) {
                        capitalization = option
                    }
                }
                periodChip(
                    title: L("accounts_core.deposit_form.capitalization.custom"),
                    isSelected: capitalization.customDays != nil
                ) {
                    capitalization = .customDays(customDaysBinding.wrappedValue)
                }
            }
            if capitalization.customDays != nil {
                Stepper(value: customDaysBinding, in: 1...365) {
                    Text(String(
                        format: L("accounts_core.deposit_form.custom_days_format"),
                        customDaysBinding.wrappedValue
                    ))
                    .font(.millioCallout)
                    .foregroundStyle(AppColors.textSecondary)
                }
                .transition(.opacity)
            }
        }
        .animation(AppAnimation.fast, value: capitalization)
    }

    private func periodChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.millioCallout)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.s)
                .background {
                    RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                        .fill(isSelected
                              ? LinearGradient(
                                  colors: AppColors.financesGradient.map { $0.opacity(0.35) },
                                  startPoint: .leading, endPoint: .trailing
                              )
                              : LinearGradient(
                                  colors: [AppColors.iconBackground, AppColors.iconBackground],
                                  startPoint: .leading, endPoint: .trailing
                              ))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                                .stroke(
                                    isSelected ? AppColors.brandPrimary : Color.clear,
                                    lineWidth: 1
                                )
                        }
                }
        }
        .buttonStyle(.plain)
    }

    private func title(for option: AccountDepositCapitalization) -> String {
        switch option {
        case .none: L("accounts_core.deposit_form.capitalization.none")
        case .daily: L("accounts_core.deposit_form.capitalization.daily")
        case .monthly: L("accounts_core.deposit_form.capitalization.monthly")
        case .quarterly: L("accounts_core.deposit_form.capitalization.quarterly")
        case .customDays: L("accounts_core.deposit_form.capitalization.custom")
        }
    }

    // MARK: - Живой доход за период

    @ViewBuilder
    private var incomeHint: some View {
        if let periodIncome {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "arrow.up.right")
                    .font(.millioMicro)
                Text(String(
                    format: L("accounts_core.deposit_form.income_per_period_format"),
                    AmountTextField.formatted(from: NSDecimalNumber(decimal: periodIncome).stringValue),
                    currency,
                    periodPhrase
                ))
                .font(.millioSubheadline)
            }
            .foregroundStyle(AppColors.positiveColor)
            .transition(.opacity)
        } else {
            Text(L("accounts_core.deposit_form.income_hint_empty"))
                .font(.millioCaptionRegular)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private var periodPhrase: String {
        switch capitalization {
        case .none: L("accounts_core.deposit_form.period.yearly")
        case .daily: L("accounts_core.deposit_form.period.daily")
        case .monthly: L("accounts_core.deposit_form.period.monthly")
        case .quarterly: L("accounts_core.deposit_form.period.quarterly")
        case .customDays(let days):
            String(format: L("accounts_core.deposit_form.period.custom_days_format"), max(1, days))
        }
    }

    // MARK: - Тег «налогооблагаемый»

    private var taxableChip: some View {
        Button {
            isTaxable.toggle()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: isTaxable ? "checkmark.seal.fill" : "seal")
                    .font(.millioCallout)
                Text(L("accounts_core.deposit_form.taxable"))
                    .font(.millioCallout)
            }
            .foregroundStyle(isTaxable ? AppColors.warning : AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.s)
            .background {
                Capsule()
                    .fill(isTaxable ? AppColors.warning.opacity(0.16) : AppColors.iconBackground)
                    .overlay {
                        Capsule().stroke(
                            isTaxable ? AppColors.warning.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isTaxable ? .isSelected : [])
        .animation(AppAnimation.fast, value: isTaxable)
    }

    // MARK: - Валюта

    private func fieldCaption(_ text: String) -> some View {
        Text(text)
            .font(.millioCaption)
            .textCase(.uppercase)
            .foregroundStyle(AppColors.textTertiary)
    }

    private var currencyPickerSheet: some View {
        let favoriteCodes = SettingsManager.shared.favoriteCurrencyCodes
        let canUseCrypto = EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
        return NavigationStack {
            CurrencyPickerView(
                allCodes: CurrencySelectionSupport.pickerCodes(extraCodes: [currency]),
                searchText: $currencySearchText,
                selectedCodes: favoriteCodes,
                favoriteCodes: Set(favoriteCodes),
                currentSelection: currency,
                primaryPinnedCode: SettingsManager.shared.primaryCurrencyCode,
                onToggleFavorite: nil,
                badgeForCode: { code in
                    guard CurrencySelectionSupport.isCrypto(code), !canUseCrypto else { return nil }
                    return .pro
                },
                onSelect: { code in
                    if CurrencySelectionSupport.isCrypto(code), !canUseCrypto {
                        showCryptoProAlert = true
                        return
                    }
                    currency = code
                    showCurrencyPicker = false
                }
            )
        }
    }
}
