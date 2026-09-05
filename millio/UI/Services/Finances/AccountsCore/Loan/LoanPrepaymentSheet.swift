import SwiftUI

/// Лист досрочного погашения (макет, ЭКРАН 4): ввод суммы → выбор «срок / платёж» → «что изменится».
///
/// Вью ничего не считает: и цифры, и тексты приходят готовыми из `LoanPrepaymentPresentation`.
/// Один и тот же лист обслуживает три сценария — досрочку, недоплату и полное погашение; какой из
/// них показать, решает ядро по введённой сумме, а не экран.
struct LoanPrepaymentSheet: View {
    let terms: LoanTerms
    let outstandingPrincipal: Decimal
    let paymentsMade: Int
    let currency: String
    let onConfirm: (LoanExtraPaymentEntry) -> Void

    /// Предвыбран «Срок» — решение владельца (спека §4.4): он математически выгоднее.
    @State private var strategy: LoanPrepaymentStrategy = .term
    @State private var amountText = ""
    @FocusState private var amountFocused: Bool
    @State private var detent: PresentationDetent = .height(Self.compactHeight)

    /// Компактная высота: шапка + поле суммы с подсказкой + кнопка. Держим числом, потому что
    /// `.presentationDetents` требует высоту до layout-прохода. Пока сумма не введена, лист не
    /// разворачивается на весь экран — под полем зияла пустота до кнопки.
    private static let compactHeight: CGFloat = 300

    private var amount: Decimal {
        Decimal(string: AmountInputFormatter.sanitize(amountText)) ?? .zero
    }

    private var presentation: LoanPrepaymentPresentation {
        LoanPrepaymentPresentation.make(
            terms: terms,
            outstandingPrincipal: outstandingPrincipal,
            paymentsMade: paymentsMade,
            amount: amount,
            strategy: strategy,
            currency: currency
        )
    }

    var body: some View {
        let presentation = presentation
        // Разворачиваем лист, только когда ядру есть что показать под полем ввода.
        let isExpanded = !presentation.options.isEmpty
            || !presentation.diff.isEmpty
            || presentation.outcome != nil
        VStack(spacing: 0) {
            title
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    amountField(presentation)
                    if !presentation.options.isEmpty {
                        section(L("accounts_core.loan.prepayment.section.what_reduce")) {
                            VStack(spacing: AppSpacing.s) {
                                ForEach(presentation.options) { option in
                                    optionRow(option, isSelected: option.strategy == presentation.selectedStrategy)
                                }
                            }
                        }
                    }
                    if !presentation.diff.isEmpty {
                        section(L("accounts_core.loan.prepayment.section.what_changes")) {
                            AccountDetailsBoxCard {
                                ForEach(Array(presentation.diff.enumerated()), id: \.element.id) { index, row in
                                    if index > 0 { AccountDetailsDivider() }
                                    diffRow(row)
                                }
                            }
                        }
                    }
                    if let outcome = presentation.outcome { outcomeCard(outcome) }
                }
                .padding(.horizontal, AppSpacing.l)
                .padding(.bottom, AppSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            confirmButton(presentation)
        }
        .padding(.top, AppSpacing.xl)
        .background(GradientBackground())
        .presentationDetents([.height(Self.compactHeight), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: isExpanded) { _, expanded in
            detent = expanded ? .large : .height(Self.compactHeight)
        }
        .autofocusAfterPresentation($amountFocused)
        .toolbar {
            // Цифровая клавиатура не имеет клавиши подтверждения — без этой кнопки поле суммы
            // невозможно закрыть, не уводя лист.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("common.done")) { amountFocused = false }
            }
        }
    }

    // MARK: - Шапка и ввод

    private var title: some View {
        Text(L("accounts_core.loan.prepayment.title"))
            .font(.millioHeadlineBold)
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, AppSpacing.l)
    }

    private func amountField(_ presentation: LoanPrepaymentPresentation) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(L("accounts_core.loan.prepayment.amount_label"))
                .font(.millioCaption2)
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.s) {
                AmountTextField(
                    placeholder: "0",
                    value: $amountText,
                    maxFractionDigits: 0,
                    // Рамп шрифта: длинная сумма ужимается на ступень, иначе «1 200 000 ₽» не
                    // помещается в строку (тот же приём, что в редакторе операций Cashflow).
                    font: { $0.filter(\.isWholeNumber).count >= 7 ? .millioTitle3 : .millioTitle }
                )
                .foregroundStyle(LoanScreenStyle.accent)
                .focused($amountFocused)
                .lineLimit(1)
                Text(LoanMoneyFormat.symbol(for: currency))
                    .font(.millioTitle3)
                    .foregroundStyle(LoanScreenStyle.accent)
            }
            Text(presentation.hint)
                .font(.millioCaptionRegular)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(title)
                .font(.millioCaption2)
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)
            content()
        }
    }

    // MARK: - Выбор сценария

    private func optionRow(
        _ option: LoanPrepaymentPresentation.Option, isSelected: Bool
    ) -> some View {
        Button {
            strategy = option.strategy
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.m) {
                radio(isSelected: isSelected)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.s) {
                        Text(option.title)
                            .font(.millioBodySemibold)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer(minLength: 0)
                        if let tag = option.tag {
                            Text(tag)
                                .font(.millioCaption2Medium)
                                .foregroundStyle(LoanScreenStyle.principalColor)
                                .padding(.horizontal, AppSpacing.s)
                                .padding(.vertical, AppSpacing.xs)
                                .background(
                                    Capsule().fill(LoanScreenStyle.positiveFill)
                                )
                        }
                    }
                    Text(option.note)
                        .font(.millioCaptionRegular)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(AppSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LoanScreenStyle.buttonCornerRadius, style: .continuous)
                    .fill(LoanScreenStyle.quietFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LoanScreenStyle.buttonCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? LoanScreenStyle.accent : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func radio(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? LoanScreenStyle.accent : AppColors.textTertiary,
                    lineWidth: 1.5
                )
                .frame(width: LoanScreenStyle.radioSize, height: LoanScreenStyle.radioSize)
            if isSelected {
                Circle()
                    .fill(LoanScreenStyle.accent)
                    .frame(width: LoanScreenStyle.radioDotSize, height: LoanScreenStyle.radioDotSize)
            }
        }
        // Кружок выравнивается по первой строке заголовка, а не по центру блока: у строк с
        // примечанием в две строки центр уезжает вниз.
        .padding(.top, AppSpacing.xs)
    }

    // MARK: - Что изменится

    private func diffRow(_ row: LoanPrepaymentPresentation.DiffRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.s) {
            Text(row.title)
                .font(.millioBody)
                .foregroundStyle(AppColors.textSecondary)
            Spacer(minLength: AppSpacing.s)
            if let after = row.after {
                Text(row.before)
                    .font(.millioCalloutRegular)
                    .foregroundStyle(AppColors.textTertiary)
                    .strikethrough(true, color: AppColors.textTertiary)
                    .lineLimit(1)
                Text(after)
                    .font(.millioCalloutSemibold)
                    .foregroundStyle(color(for: row.afterStyle))
                    .lineLimit(1)
            } else {
                Text(row.before)
                    .font(.millioCalloutSemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(L("accounts_core.loan.prepayment.unchanged"))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, AppSpacing.l)
    }

    private func color(for style: LoanPrepaymentPresentation.ValueStyle) -> Color {
        switch style {
        case .neutral: AppColors.textPrimary
        case .positive: LoanScreenStyle.principalColor
        case .negative: LoanScreenStyle.interestColor
        }
    }

    private func outcomeCard(_ outcome: LoanPrepaymentPresentation.Outcome) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(outcome.title)
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.s)
                Text(outcome.value)
                    .font(.millioBodySemibold)
                    .foregroundStyle(color(for: outcome.style))
                    .lineLimit(1)
            }
            if let detail = outcome.detail {
                Text(detail)
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LoanScreenStyle.buttonCornerRadius, style: .continuous)
                .fill(outcome.style == .negative ? LoanScreenStyle.negativeFill : LoanScreenStyle.positiveFill)
        )
    }

    // MARK: - Подтверждение

    private func confirmButton(_ presentation: LoanPrepaymentPresentation) -> some View {
        Button {
            guard let entry = presentation.entry else { return }
            onConfirm(entry)
        } label: {
            Text(presentation.confirmTitle)
                .font(.millioBodySemibold)
                .foregroundStyle(LoanScreenStyle.accentContrast)
                .frame(maxWidth: .infinity, minHeight: LoanScreenStyle.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: LoanScreenStyle.buttonCornerRadius, style: .continuous)
                        .fill(LoanScreenStyle.accent)
                )
        }
        .buttonStyle(.plain)
        .disabled(!presentation.canConfirm)
        .opacity(presentation.canConfirm ? 1 : 0.4)
        .padding(.horizontal, AppSpacing.l)
        .padding(.top, AppSpacing.s)
        .padding(.bottom, AppSpacing.m)
    }
}
