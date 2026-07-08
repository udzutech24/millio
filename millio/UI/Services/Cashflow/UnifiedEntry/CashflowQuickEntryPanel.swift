//
//  CashflowQuickEntryPanel.swift
//  millio
//
//  Инлайн-панель быстрого ввода суммы (Фаза 3, чекпоинт 3b).
//  Заменяет прежний второй .sheet (CashflowQuickEntrySheet): показывается
//  как оверлей-шторка внутри того же модального контекста единого экрана —
//  двухслойность «мини-шит → большой-шит» устранена (§2.1.2).
//

import SwiftUI

struct CashflowQuickEntryPanel: View {

    // MARK: - Input

    @ObservedObject var viewModel: CashflowViewModel
    let option: CashflowCategoryOption
    let kind: CashflowCategoryTransactionSheetKind
    let selectedMonth: Date
    var onSave: (() -> Void)? = nil
    var onOpenFullEditor: ((CashflowCategoryOption) -> Void)? = nil
    var onDismiss: () -> Void

    // MARK: - State

    @Environment(AppState.self) private var appState

    @State private var amountText: String = ""
    @State private var note: String = ""
    @State private var selectedCardID: String? = nil
    @State private var isSaving: Bool = false
    @State private var showError: Bool = false
    // Ручной оверрайд валюты транзакции. nil → валюта следует за выбранным счётом (§2.1.1).
    @State private var overrideCurrency: String? = nil
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""

    @FocusState private var amountFocused: Bool

    /// Валюта выбранного счёта (легаси-карты + счета нового ядра), с фолбэком на display-валюту.
    private var accountCurrency: String {
        if let selectedCardID {
            if let card = viewModel.state.availableCards.first(where: { $0.cardUniqueID == selectedCardID }) {
                return card.currency
            }
            if let account = viewModel.newCoreAccountsForCashflowPicker().first(where: { $0.id.uuidString == selectedCardID }) {
                return account.currency
            }
        }
        return viewModel.state.displayCurrency
    }

    /// Итоговая валюта транзакции: ручной оверрайд либо валюта счёта.
    private var effectiveCurrency: String {
        overrideCurrency ?? accountCurrency
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Затемнение фона — тап по нему закрывает панель.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { close() }

            card
                .padding(.horizontal, AppSpacing.l)
                .padding(.bottom, AppSpacing.l)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .onAppear {
            amountFocused = true
            selectedCardID = viewModel.state.availableCards.first?.cardUniqueID
        }
        .alert(L("cashflow.editor.save_failed.title"), isPresented: $showError) {
            Button(L("cashflow.common.ok"), role: .cancel) {}
        }
    }

    private var card: some View {
        VStack(spacing: AppSpacing.l) {
            grabber
            categoryHeader
            amountField
            noteField
            accountAndCurrencyRow
            saveButton
            if onOpenFullEditor != nil {
                Button(L("cashflow.quick.open_full_editor")) {
                    onOpenFullEditor?(option)
                    onDismiss()
                }
                .font(.millioBodyRegular)
                .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(AppSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(white: 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Subviews

    private var grabber: some View {
        Capsule()
            .fill(Color.white.opacity(0.2))
            .frame(width: 36, height: 5)
    }

    private var categoryHeader: some View {
        HStack(spacing: AppSpacing.m) {
            ZStack {
                Circle()
                    .fill(kind.accentColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(kind.accentColor.opacity(0.35), lineWidth: 1)
                    )
                CashflowCategoryIconView(
                    icon: option.icon,
                    fontSize: 18,
                    fontWeight: .semibold,
                    tint: AnyShapeStyle(kind.accentColor)
                )
            }
            Text(option.displayName)
                .font(.millioHeadline)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.millioCaption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(AppSpacing.s)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
        }
    }

    private var amountField: some View {
        TextField("0", text: $amountText)
            .keyboardType(.decimalPad)
            .font(.millioDisplay)
            .foregroundStyle(AppColors.textPrimary)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .focused($amountFocused)
            .contentTransition(.numericText())
            .onChange(of: amountText) { _, newValue in
                amountText = AmountInputFormatter.sanitize(newValue)
            }
            .padding(.vertical, AppSpacing.ml)
            .padding(.horizontal, AppSpacing.l)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                amountFocused
                                    ? kind.accentColor.opacity(0.5)
                                    : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
    }

    private var noteField: some View {
        TextField(L("cashflow.quick.note.placeholder"), text: $note)
            .font(.millioSubheadlineMedium)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.vertical, AppSpacing.m)
            .padding(.horizontal, AppSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }

    private var accountAndCurrencyRow: some View {
        HStack(spacing: AppSpacing.s) {
            cardPicker
            currencyChip
        }
        // Смена счёта возвращает валюту к валюте нового счёта (§2.1.1).
        .onChange(of: selectedCardID) { _, _ in
            overrideCurrency = nil
        }
    }

    private var currencyChip: some View {
        Button {
            amountFocused = false
            showCurrencyPicker = true
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Text(effectiveCurrency)
                    .font(.millioSubheadlineMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.millioCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.vertical, AppSpacing.m)
            .padding(.horizontal, AppSpacing.ml)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(kind.accentColor.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                overrideCurrency != nil
                                    ? kind.accentColor.opacity(0.5)
                                    : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
        }
        .sheet(isPresented: $showCurrencyPicker) {
            currencyPickerSheet
        }
    }

    private var currencyPickerSheet: some View {
        let canUseCrypto = EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
        return NavigationStack {
            CurrencyPickerView(
                allCodes: CurrencySelectionSupport.allCodes(includeCrypto: canUseCrypto),
                searchText: $currencySearchText,
                selectedCodes: SettingsManager.shared.favoriteCurrencyCodes,
                favoriteCodes: Set(SettingsManager.shared.favoriteCurrencyCodes),
                currentSelection: effectiveCurrency,
                primaryPinnedCode: CashflowTransactionEditorView.operationCurrencyPrimaryPinnedCode(
                    from: SettingsManager.shared.primaryCurrencyCode
                ),
                onSelect: { currency in
                    overrideCurrency = currency
                    showCurrencyPicker = false
                }
            )
            .navigationTitle(L("cashflow.editor.transaction_currency"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cashflow.common.cancel")) {
                        showCurrencyPicker = false
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var cardPicker: some View {
        let cards = viewModel.state.availableCards
        let selectedCard = cards.first(where: { $0.cardUniqueID == selectedCardID })

        return Menu {
            Button {
                selectedCardID = nil
            } label: {
                Label(L("cashflow.quick.card.none"), systemImage: "xmark.circle")
            }
            Divider()
            ForEach(cards, id: \.cardUniqueID) { card in
                Button {
                    selectedCardID = card.cardUniqueID
                } label: {
                    Label(card.name, systemImage: "creditcard")
                }
            }
        } label: {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "creditcard")
                    .font(.millioSubheadlineMedium)
                    .foregroundStyle(selectedCard != nil ? kind.accentColor : AppColors.textSecondary)
                Text(selectedCard?.name ?? L("cashflow.quick.card.none"))
                    .font(.millioSubheadlineMedium)
                    .foregroundStyle(selectedCard != nil ? AppColors.textPrimary : AppColors.textSecondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.millioCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.vertical, AppSpacing.m)
            .padding(.horizontal, AppSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }

    private var saveButton: some View {
        Button {
            saveTransaction()
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(L("cashflow.quick.add"))
                        .font(.millioHeadline)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        parsedAmount != nil
                            ? LinearGradient(colors: kind.gradientColors, startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.white.opacity(0.12)], startPoint: .leading, endPoint: .trailing)
                    )
            )
        }
        .disabled(parsedAmount == nil || isSaving)
        .animation(AppAnimation.standard, value: parsedAmount != nil)
    }

    // MARK: - Logic

    private var parsedAmount: Double? {
        let value = AmountInputFormatter.parse(amountText)
        guard let value, value > 0 else { return nil }
        return value
    }

    private func close() {
        amountFocused = false
        onDismiss()
    }

    private func saveTransaction() {
        guard let amount = parsedAmount else { return }

        let incomeCategoryRaw: String? = kind.categoryKind == .income ? option.rawValue : nil
        let expenseCategoryRaw: String? = kind.categoryKind == .expense ? option.rawValue : nil

        let transaction = CashflowTransaction(
            transactionType: kind.transactionType,
            amount: amount,
            currency: effectiveCurrency,
            transactionDate: CashflowCategorySheetBootstrap.initialTransactionDate(
                forSelectedMonth: selectedMonth
            ),
            cardID: selectedCardID,
            toCardID: nil,
            investmentID: nil,
            incomeCategoryRaw: incomeCategoryRaw,
            expenseCategoryRaw: expenseCategoryRaw,
            note: note.isEmpty ? nil : note,
            recurrenceRule: .none,
            recurrenceWeekdays: [],
            recurrenceSeriesID: nil,
            affectsCardBalance: false
        )

        isSaving = true
        Task {
            let didSave = await viewModel.persistTransaction(
                transaction,
                replacing: nil,
                dismissEditorOnSuccess: false
            )
            await MainActor.run {
                isSaving = false
                if didSave {
                    onSave?()
                    close()
                } else {
                    showError = true
                }
            }
        }
    }
}
