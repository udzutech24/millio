//
//  CashflowQuickEntrySheet.swift
//  millio
//
//  Быстрый ввод транзакции через bottom sheet.
//  Открывается тапом на категорию в CashflowCategoryTransactionSheet.
//

import SwiftUI

struct CashflowQuickEntrySheet: View {

    // MARK: - Input

    @ObservedObject var viewModel: CashflowViewModel
    let option: CashflowCategoryOption
    let kind: CashflowCategoryTransactionSheetKind
    let selectedMonth: Date
    var onSave: (() -> Void)? = nil
    var onOpenFullEditor: ((CashflowCategoryOption) -> Void)? = nil

    // MARK: - State

    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var note: String = ""
    @State private var selectedCardID: String? = nil
    @State private var isSaving: Bool = false
    @State private var showError: Bool = false

    @FocusState private var amountFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Фоновый градиент
                LinearGradient(
                    colors: [Color.black, Color(white: 0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Заголовок с категорией
                    categoryHeader
                        .padding(.top, 8)
                        .padding(.bottom, 24)

                    // Поле суммы
                    amountField
                        .padding(.bottom, 16)

                    // Поле заметки
                    noteField
                        .padding(.bottom, 16)

                    // Выбор карты (всегда показываем; если карт нет — только "Без карты")
                    cardPicker
                        .padding(.bottom, 24)

                    // Кнопка добавить
                    saveButton

                    // Ссылка на полный редактор
                    if onOpenFullEditor != nil {
                        Button(L("cashflow.quick.open_full_editor")) {
                            dismiss()
                            onOpenFullEditor?(option)
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.top, 12)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cashflow.common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            amountFocused = true
            selectedCardID = viewModel.state.availableCards.first?.cardUniqueID
        }
        .alert(L("cashflow.editor.save_failed.title"), isPresented: $showError) {
            Button(L("cashflow.common.ok"), role: .cancel) {}
        }
    }

    // MARK: - Subviews

    private var categoryHeader: some View {
        VStack(spacing: 10) {
            // Иконка категории в кружке
            ZStack {
                Circle()
                    .fill(kind.accentColor.opacity(0.18))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .strokeBorder(kind.accentColor.opacity(0.35), lineWidth: 1)
                    )

                CashflowCategoryIconView(
                    icon: option.icon,
                    fontSize: 22,
                    fontWeight: .semibold,
                    tint: AnyShapeStyle(kind.accentColor)
                )
            }

            // Название категории
            Text(option.displayName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("cashflow.quick.amount.placeholder"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            TextField("0", text: $amountText)
                .keyboardType(.decimalPad)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .focused($amountFocused)
                .onChange(of: amountText) { _, newValue in
                    amountText = AmountInputFormatter.sanitize(newValue)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
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
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("cashflow.quick.note.placeholder"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            TextField(
                L("cashflow.quick.note.placeholder"),
                text: $note
            )
            .font(.system(size: 15))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
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

    private var cardPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("cashflow.quick.card.label"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            let cards = viewModel.state.availableCards
            let selectedCard = cards.first(where: { $0.cardUniqueID == selectedCardID })

            Menu {
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
                HStack(spacing: 10) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selectedCard != nil ? kind.accentColor : AppColors.textSecondary)
                    Text(selectedCard?.name ?? L("cashflow.quick.card.none"))
                        .font(.system(size: 15))
                        .foregroundStyle(selectedCard != nil ? AppColors.textPrimary : AppColors.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        parsedAmount != nil
                            ? LinearGradient(
                                colors: kind.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                              )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.12)],
                                startPoint: .leading,
                                endPoint: .trailing
                              )
                    )
            )
        }
        .disabled(parsedAmount == nil || isSaving)
        .animation(.easeInOut(duration: 0.2), value: parsedAmount != nil)
    }

    // MARK: - Logic

    private var parsedAmount: Double? {
        let value = AmountInputFormatter.parse(amountText)
        guard let value, value > 0 else { return nil }
        return value
    }

    private func saveTransaction() {
        guard let amount = parsedAmount else { return }

        let incomeCategoryRaw: String? = kind.categoryKind == .income ? option.rawValue : nil
        let expenseCategoryRaw: String? = kind.categoryKind == .expense ? option.rawValue : nil

        let transaction = CashflowTransaction(
            transactionType: kind.transactionType,
            amount: amount,
            currency: viewModel.state.displayCurrency,
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
                    dismiss()
                } else {
                    showError = true
                }
            }
        }
    }
}
