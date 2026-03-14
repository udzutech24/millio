//
//  CashflowBulkExpenseImportSheet.swift
//  millio
//
//  Created by Codex on 11.03.2026.
//

import SwiftUI
import PhotosUI

struct CashflowBulkExpenseImportSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let month: Date
    let onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var mode: CashflowBulkExpenseImportMode = .manual
    @State private var selectedCurrency: String = SettingsManager.shared.primaryCurrencyCode
    @State private var selectedCardID: String?
    @State private var selectedMonth: Date
    @State private var categoryDrafts: [CashflowBulkExpenseCategoryDraft] = []
    @State private var categorySearchText: String = ""
    @State private var shouldAffectCardBalance: Bool = true
    @State private var loadedAffectingTotal: Double = 0
    @State private var screenshotItems: [PhotosPickerItem] = []
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?
    @State private var saveMessage: String?
    @State private var isErrorDismissed: Bool = false
    @State private var isSaveDismissed: Bool = false
    @State private var showHelpSheet: Bool = false
    @State private var showMonthPickerSheet: Bool = false
    @State private var showCategoryEditorSheet: Bool = false
    @State private var categoryEditorName: String = ""
    @State private var categoryEditorIcon: String = CashflowCustomCategory.defaultIcon
    @FocusState private var focusedCategoryID: String?

    private let parser = CashflowBulkExpenseImportParser()
    private let categoryResolver = CashflowBulkExpenseImportCategoryResolver()
    private let outerCornerRadius: CGFloat = 24
    private let innerCornerRadius: CGFloat = 18
    private let accent = Color(hex: "5FD1FF")
    private let toggleAccent = Color(hex: "6A7EA3")
    private let positive = Color(hex: "6DFFC7")
    private let warning = Color(hex: "FFB454")
    private let danger = Color(hex: "FF5A5F")
    private let preferredCurrency = SettingsManager.shared.primaryCurrencyCode
    private let categoryGridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    init(
        viewModel: CashflowViewModel,
        month: Date,
        onComplete: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.month = month
        self.onComplete = onComplete
        _selectedMonth = State(initialValue: month)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        modeSelector
                        introHeader
                        controlsCard
                        if mode == .screenshot {
                            screenshotCard
                        }
                        summaryCard
                        categoriesCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 120)
                }

                floatingAddCategoryButton
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
            }
            .navigationTitle(
                String(
                    localized: "cashflow.bulk_expense.title",
                    defaultValue: "Mass expense import",
                    comment: "Navigation title for bulk expense import sheet"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await saveRows()
                        }
                    } label: {
                        Text(
                            String(
                                localized: "cashflow.bulk_expense.save",
                                defaultValue: "Save",
                                comment: "Bulk expense import save button"
                            )
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(canSave ? positive : Color.white.opacity(0.38))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave || isProcessing)
                }
            }
            .onAppear {
                showMonthPickerSheet = false
                configureInitialStateIfNeeded()
            }
            .onChange(of: screenshotItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await analyzePhotos(items: newItems)
                }
            }
            .onChange(of: selectedCurrency) { _, _ in
                let previousCardID = selectedCardID
                syncSelectionWithCurrency()
                if selectedCardID == previousCardID {
                    Task {
                        await reloadDrafts()
                    }
                }
            }
            .onChange(of: selectedCardID) { _, _ in
                Task {
                    await reloadDrafts()
                }
            }
            .onChange(of: selectedMonth) { _, _ in
                Task {
                    await reloadDrafts()
                }
            }
            .onChange(of: viewModel.state.availableCards.map { "\($0.cardUniqueID)_\($0.currency)_\($0.isFavorite)" }) { _, _ in
                syncSelectionWithCurrency()
            }
            .onDisappear {
                showMonthPickerSheet = false
            }
            .sheet(isPresented: $showHelpSheet) {
                bulkImportHelpSheet
            }
            .sheet(isPresented: $showMonthPickerSheet) {
                monthPickerSheet
                    .presentationDetents([.fraction(0.3)])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showCategoryEditorSheet) {
                CashflowCategoryEditorSheet(
                    mode: .create,
                    name: $categoryEditorName,
                    icon: $categoryEditorIcon
                ) { name, icon in
                    handleCreateCategory(name: name, icon: icon)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var introHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                showMonthPickerSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                    Text(monthTitle)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            Button {
                showHelpSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 6) {
            ForEach(CashflowBulkExpenseImportMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(mode == item ? Color.white.opacity(0.96) : Color.white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(mode == item ? Color.white.opacity(0.16) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
        )
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(availableCurrencies, id: \.self) { currency in
                        Button(currency) {
                            selectedCurrency = currency
                        }
                    }
                } label: {
                    compactSelectorLabel(
                        title: String(localized: "cashflow.editor.currency"),
                        value: selectedCurrency
                    )
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(cardsInSelectedCurrency, id: \.cardUniqueID) { card in
                        Button {
                            selectedCardID = card.cardUniqueID
                        } label: {
                            Label(card.name, systemImage: card.cardType.icon)
                        }
                    }
                } label: {
                    compactSelectorLabel(
                        title: String(
                            localized: "cashflow.bulk_expense.card_title",
                            defaultValue: "Card",
                            comment: "Card picker title in bulk expense import"
                        ),
                        value: selectedCard?.name ?? String(
                            localized: "cashflow.bulk_expense.pick_card",
                            defaultValue: "Choose card",
                            comment: "Placeholder text for picking a card"
                        ),
                        icon: selectedCard?.cardType.icon ?? "creditcard.fill",
                        usesPlaceholderStyle: selectedCard == nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(cardsInSelectedCurrency.isEmpty)
                .opacity(cardsInSelectedCurrency.isEmpty ? 0.55 : 1)
            }

            if let selectedCard {
                Text(
                    String(
                        format: String(localized: "cashflow.editor.available_format"),
                        CashflowBulkExpenseRowDraft.formatAmount(selectedCard.balance),
                        selectedCard.currency
                    )
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.68))
            } else if cardsInSelectedCurrency.isEmpty {
                Text(String(localized: "cashflow.editor.no_cards_in_currency"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))
            }

            Toggle(
                isOn: $shouldAffectCardBalance,
                label: {
                    HStack(alignment: .center, spacing: 6) {
                        Text(
                            String(
                                localized: "cashflow.bulk_expense.affect_balance",
                                defaultValue: "Update card balance",
                                comment: "Toggle title for applying card balance changes"
                            )
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))

                        Button {
                            showHelpSheet = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.66))
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            String(
                                localized: "cashflow.bulk_expense.affect_balance.subtitle",
                                defaultValue: "Saved monthly totals reopen on this screen. Turn this off if you only want history.",
                                comment: "Toggle subtitle for applying card balance changes"
                            )
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(2)
                    }
                }
            )
            .toggleStyle(.switch)
            .tint(toggleAccent)
        }
        .padding(12)
        .background(cardBackground)
    }

    private func compactSelectorLabel(
        title: String,
        value: String,
        icon: String? = nil,
        usesPlaceholderStyle: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .textCase(.uppercase)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(usesPlaceholderStyle ? Color.white.opacity(0.58) : Color.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.54))
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(innerBackground)
        .frame(maxWidth: .infinity)
    }

    private func monthNavButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isEnabled ? Color.white.opacity(0.94) : Color.white.opacity(0.24))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.72))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isEnabled ? 0.34 : 0.12), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var monthPickerSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            String(
                                localized: "cashflow.bulk_expense.month_picker.title",
                                defaultValue: "Select month",
                                comment: "Month picker title for bulk expense import"
                            )
                        )
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.95))

                        Text(
                            String(
                                localized: "cashflow.bulk_expense.month_picker.subtitle",
                                defaultValue: "The current month is selected by default. If needed, switch the period and close the sheet.",
                                comment: "Month picker subtitle for bulk expense import"
                            )
                        )
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            monthNavButton(systemImage: "chevron.left", isEnabled: true) {
                                shiftMonth(by: -1)
                            }

                            Spacer(minLength: 0)

                            Text(monthTitle)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.97))

                            Spacer(minLength: 0)

                            monthNavButton(systemImage: "chevron.right", isEnabled: canMoveToNextMonth) {
                                shiftMonth(by: 1)
                            }
                        }

                        Text(periodRangeTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.58))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.black.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                accent.opacity(0.8),
                                                Color(hex: "D23AF2").opacity(0.82)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1.2
                                    )
                            )
                    )

                    Button {
                        showMonthPickerSheet = false
                    } label: {
                        Text(String(localized: "Done"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.94))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .presentationBackground(.clear)
        }
    }

    private var screenshotCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                String(
                    localized: "cashflow.bulk_expense.screenshot.hint",
                    defaultValue: "Load one or several screenshots from your bank. Recognized expenses will be merged into the monthly category totals below.",
                    comment: "Screenshot import hint"
                )
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.58))

            PhotosPicker(
                selection: $screenshotItems,
                maxSelectionCount: 6,
                matching: .images
            ) {
                rowActionLabel(
                    title: isProcessing
                    ? String(
                        localized: "cashflow.bulk_expense.screenshot.processing",
                        defaultValue: "Analyzing screenshots…",
                        comment: "Processing screenshots button label"
                    )
                    : String(
                        localized: "cashflow.bulk_expense.screenshot.pick",
                        defaultValue: "Choose screenshots",
                        comment: "Choose screenshot button label"
                    ),
                    systemImage: isProcessing ? "hourglass" : "photo.on.rectangle.angled"
                )
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)

            if let errorMessage, !isErrorDismissed {
                noticeCard(
                    text: errorMessage,
                    tint: danger,
                    systemImage: "exclamationmark.triangle.fill"
                ) {
                    isErrorDismissed = true
                }
            }
            if let saveMessage, !isSaveDismissed {
                noticeCard(
                    text: saveMessage,
                    tint: positive,
                    systemImage: "sparkles"
                ) {
                    isSaveDismissed = true
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                summaryMetric(
                    title: String(
                        localized: "cashflow.bulk_expense.summary.rows",
                        defaultValue: "Categories",
                        comment: "Summary title for category count"
                    ),
                    value: "\(filledDrafts.count)/\(categoryDrafts.count)"
                )

                Spacer()

                summaryMetric(
                    title: String(
                        localized: "cashflow.bulk_expense.summary.total",
                        defaultValue: "Total",
                        comment: "Summary title for total amount"
                    ),
                    value: totalAmountLabel
                )
            }

            if let selectedCard, shouldAffectCardBalance {
                let availableBalance = selectedCard.balance + loadedAffectingTotal
                let overflow = totalAmount - availableBalance
                if overflow > 0.009 {
                    noticeCard(
                        text: String(
                            localized: "cashflow.bulk_expense.summary.balance_warning",
                            defaultValue: "This monthly import exceeds the available card balance by \(CashflowBulkExpenseRowDraft.formatAmount(overflow)) \(selectedCard.currency).",
                            comment: "Warning for bulk expense import when amount exceeds card balance"
                        ),
                        tint: warning,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.42))

                TextField(
                    String(
                        localized: "cashflow.bulk_expense.search.placeholder",
                        defaultValue: "Search category",
                        comment: "Search placeholder for bulk expense categories"
                    ),
                    text: $categorySearchText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.94))
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(innerBackground)

            LazyVGrid(columns: categoryGridColumns, spacing: 8) {
                ForEach($categoryDrafts) { $draft in
                    if filteredCategoryDrafts.contains(where: { $0.id == draft.id }) {
                        categoryTile($draft)
                    }
                }
            }
            .padding(.bottom, 76)

            if let errorMessage, !isErrorDismissed {
                noticeCard(
                    text: errorMessage,
                    tint: danger,
                    systemImage: "exclamationmark.triangle.fill"
                ) {
                    isErrorDismissed = true
                }
            }
            if let saveMessage, !isSaveDismissed {
                noticeCard(
                    text: saveMessage,
                    tint: positive,
                    systemImage: "sparkles"
                ) {
                    isSaveDismissed = true
                }
            }
        }
    }

    private func categoryTile(_ draft: Binding<CashflowBulkExpenseCategoryDraft>) -> some View {
        let amountBinding = Binding(
            get: {
                draft.wrappedValue.amountText
            },
            set: { newValue in
                draft.wrappedValue.amountText = formatTileAmountInput(newValue)
            }
        )

        return VStack(spacing: 6) {
            HStack {
                Spacer(minLength: 0)
                CashflowCategoryIconView(
                    icon: draft.wrappedValue.category.icon,
                    fontSize: 18,
                    fontWeight: .semibold,
                    tint: AnyShapeStyle(Color.white.opacity(0.95))
                )
                Spacer(minLength: 0)
            }
            .frame(height: 20)

            Text(draft.wrappedValue.category.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.94))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 28)

            TextField(
                "",
                text: amountBinding,
                prompt: Text("0").foregroundStyle(Color.white.opacity(0.28))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(tileAmountFont(for: amountBinding.wrappedValue))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .focused($focusedCategoryID, equals: draft.wrappedValue.id)
            .foregroundStyle(draft.wrappedValue.hasValue ? Color.white.opacity(0.98) : Color.white.opacity(0.72))
            .padding(.horizontal, 2)
            .frame(height: 24)

            if !draft.wrappedValue.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(draft.wrappedValue.noteText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 92)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    accent.opacity(draft.wrappedValue.hasValue ? 0.9 : 0.5),
                                    Color(hex: "C428C8").opacity(draft.wrappedValue.hasValue ? 0.85 : 0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: draft.wrappedValue.hasValue ? 1.4 : 1
                        )
                )
        )
        .onTapGesture {
            focusedCategoryID = draft.wrappedValue.id
        }
        .contextMenu {
            Button(role: .destructive) {
                draft.wrappedValue.amountText = ""
                draft.wrappedValue.noteText = ""
            } label: {
                Label(
                    String(
                        localized: "cashflow.bulk_expense.tile.clear",
                        defaultValue: "Clear amount",
                        comment: "Context action to clear category amount in tile mode"
                    ),
                    systemImage: "trash"
                )
            }
        }
    }

    private var floatingAddCategoryButton: some View {
        Button {
            categoryEditorName = ""
            categoryEditorIcon = CashflowCustomCategory.defaultIcon
            showCategoryEditorSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 72, height: 72)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.92))
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            accent.opacity(0.65),
                                            Color(hex: "C428C8").opacity(0.6)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                )
        }
        .padding(.trailing, 4)
        .padding(.bottom, 4)
        .buttonStyle(.plain)
    }

    private func formatTileAmountInput(_ value: String) -> String {
        let sanitized = AmountInputFormatter.sanitize(value, maxFractionDigits: 0)
        return AmountInputFormatter.display(sanitized, maxFractionDigits: 0)
    }

    private func handleCreateCategory(name: String, icon: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let created = viewModel.createCustomCategory(kind: .expense, name: trimmed, icon: icon),
           categoryDrafts.contains(where: { $0.category.rawValue == created.rawValue }) == false {
            let nextIndex = (categoryDrafts.map(\.sourceOrderIndex).max() ?? -1) + 1
            categoryDrafts.append(
                CashflowBulkExpenseCategoryDraft(
                    category: created,
                    sourceOrderIndex: nextIndex
                )
            )
        }

        showCategoryEditorSheet = false
    }

    private func tileAmountFont(for value: String) -> Font {
        let digitCount = value.filter(\.isNumber).count

        switch digitCount {
        case 0...4:
            return .system(size: 20, weight: .bold, design: .rounded)
        case 5...6:
            return .system(size: 18, weight: .bold, design: .rounded)
        case 7...8:
            return .system(size: 16, weight: .bold, design: .rounded)
        default:
            return .system(size: 14, weight: .bold, design: .rounded)
        }
    }

    private var bulkImportHelpSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        helpHeroCard
                        helpStepCard(
                            number: "1",
                            title: String(
                                localized: "cashflow.bulk_expense.help.step.period.title",
                                defaultValue: "Choose period and card",
                                comment: "Bulk expense import help step title"
                            ),
                            body: String(
                                localized: "cashflow.bulk_expense.help.step.period.body",
                                defaultValue: "First choose a month and card. The import is tied to that exact pair, so reopening the screen shows the saved totals for the same month.",
                                comment: "Bulk expense import help step body"
                            )
                        )
                        helpStepCard(
                            number: "2",
                            title: String(
                                localized: "cashflow.bulk_expense.help.step.categories.title",
                                defaultValue: "Fill categories with monthly totals",
                                comment: "Bulk expense import help step title"
                            ),
                            body: String(
                                localized: "cashflow.bulk_expense.help.step.categories.body",
                                defaultValue: "In manual mode, enter the total amount into the needed category. The field formats numbers immediately, and larger values shrink to stay readable.",
                                comment: "Bulk expense import help step body"
                            )
                        )
                        helpStepCard(
                            number: "3",
                            title: String(
                                localized: "cashflow.bulk_expense.help.step.screenshot.title",
                                defaultValue: "Or import screenshots",
                                comment: "Bulk expense import help step title"
                            ),
                            body: String(
                                localized: "cashflow.bulk_expense.help.step.screenshot.body",
                                defaultValue: "Screenshot mode tries to recognize bank expenses and merge them into monthly categories automatically. It is a speed-up, not magic, so the result should still be checked.",
                                comment: "Bulk expense import help step body"
                            )
                        )
                        helpStepCard(
                            number: "4",
                            title: String(
                                localized: "cashflow.bulk_expense.help.step.balance.title",
                                defaultValue: "Decide whether to update card balance",
                                comment: "Bulk expense import help step title"
                            ),
                            body: String(
                                localized: "cashflow.bulk_expense.help.step.balance.body",
                                defaultValue: "If the toggle is on, saving also adjusts the current card balance. If you only need categorized history, turn it off.",
                                comment: "Bulk expense import help step body"
                            )
                        )
                        helpStepCard(
                            number: "5",
                            title: String(
                                localized: "cashflow.bulk_expense.help.step.save.title",
                                defaultValue: "Save without duplicates",
                                comment: "Bulk expense import help step title"
                            ),
                            body: String(
                                localized: "cashflow.bulk_expense.help.step.save.body",
                                defaultValue: "One card and one month keep a single category set. Saving again updates the current set instead of creating duplicate noise.",
                                comment: "Bulk expense import help step body"
                            )
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(
                String(
                    localized: "cashflow.bulk_expense.help.sheet_title",
                    defaultValue: "How it works",
                    comment: "Help sheet title for bulk expense import"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) {
                        showHelpSheet = false
                    }
                    .foregroundStyle(accent)
                }
            }
        }
    }

    private var helpHeroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "cashflow.bulk_expense.title"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.96))

            Text(
                String(
                    localized: "cashflow.bulk_expense.help.hero.body",
                    defaultValue: "This screen is designed for quickly recording monthly expenses by category without creating each transaction manually.",
                    comment: "Help hero body for bulk expense import"
                )
            )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    private func helpStepCard(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.94))

                Text(body)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.56))
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.94))
        }
    }

    private func badge(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.74))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private func rowActionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(Color.white.opacity(0.95))
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(accent.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                        .stroke(accent.opacity(0.38), lineWidth: 1)
                )
        )
    }

    private func noticeCard(
        text: String,
        tint: Color,
        systemImage: String,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(tint.opacity(0.12))
                        )

                    Text(text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.84))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.09, green: 0.07, blue: 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(0.78), lineWidth: 1.2)
                )
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
            .background(
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.25))
            )
    }

    private var innerBackground: some View {
        RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
    }

    private var preferredCard: Card? {
        cardsInSelectedCurrency.first(where: { $0.cardUniqueID == selectedCardID })
            ?? cardsInSelectedCurrency.first(where: \.isFavorite)
            ?? cardsInSelectedCurrency.first
    }

    private var selectedCard: Card? {
        guard let selectedCardID else { return nil }
        return cardsInSelectedCurrency.first(where: { $0.cardUniqueID == selectedCardID })
    }

    private var availableCurrencies: [String] {
        CashflowBulkExpenseImportSelectionPolicy.availableCurrencies(
            cards: viewModel.state.availableCards,
            preferredCurrency: preferredCurrency
        )
    }

    private var cardsInSelectedCurrency: [Card] {
        viewModel.state.availableCards
            .filter { $0.currency == selectedCurrency }
    }

    private var filledDrafts: [CashflowBulkExpenseCategoryDraft] {
        categoryDrafts
            .filter(\.hasValue)
            .sorted { $0.sourceOrderIndex < $1.sourceOrderIndex }
    }

    private var filteredCategoryDrafts: [CashflowBulkExpenseCategoryDraft] {
        let trimmed = categorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return categoryDrafts }
        return categoryDrafts.filter { draft in
            draft.category.displayName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var canSave: Bool {
        selectedCardID != nil && !filledDrafts.isEmpty
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: selectedMonth).localizedCapitalized
    }

    private var monthShortTitle: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("LLL yyyy")
        return formatter.string(from: selectedMonth).localizedCapitalized
    }

    private var periodRangeTitle: String {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "dd.MM.yyyy"
        return "\(formatter.string(from: start)) — \(formatter.string(from: end))"
    }

    private var canMoveToNextMonth: Bool {
        let calendar = Calendar.current
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) else { return false }
        let nextMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) ?? nextMonth
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return nextMonthStart <= currentMonthStart
    }

    private var totalAmount: Double {
        filledDrafts.compactMap(\.amount).reduce(0, +)
    }

    private var totalAmountLabel: String {
        "\(CashflowBulkExpenseRowDraft.formatAmount(totalAmount)) \(selectedCurrency)"
    }

    private func configureInitialStateIfNeeded() {
        syncSelectionWithCurrency()
        if categoryDrafts.isEmpty {
            categoryDrafts = makeEmptyCategoryDrafts()
        }
        Task {
            await reloadDrafts()
        }
    }

    private func syncSelectionWithCurrency() {
        let normalized = CashflowBulkExpenseImportSelectionPolicy.normalizeSelection(
            cards: viewModel.state.availableCards,
            selectedCurrency: selectedCurrency,
            selectedCardID: selectedCardID,
            preferredCurrency: preferredCurrency
        )
        selectedCurrency = normalized.currency
        selectedCardID = normalized.cardID
    }

    private func shiftMonth(by value: Int) {
        guard let shifted = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        if value > 0 && !canMoveToNextMonth {
            return
        }
        selectedMonth = shifted
    }

    private func makeEmptyCategoryDrafts() -> [CashflowBulkExpenseCategoryDraft] {
        viewModel.categoryOptions(for: .expense).enumerated().map { index, option in
            CashflowBulkExpenseCategoryDraft(category: option, sourceOrderIndex: index)
        }
    }

    private func reloadDrafts() async {
        let emptyDrafts = makeEmptyCategoryDrafts()
        categoryDrafts = emptyDrafts
        loadedAffectingTotal = 0
        errorMessage = nil
        saveMessage = nil
        isErrorDismissed = false
        isSaveDismissed = false

        guard let selectedCardID else { return }
        let storedEntries = viewModel.bulkExpenseImportStoredEntries(
            cardID: selectedCardID,
            month: selectedMonth
        )

        if let firstEntry = storedEntries.first {
            shouldAffectCardBalance = firstEntry.affectsCardBalance
        }
        loadedAffectingTotal = storedEntries
            .filter(\.affectsCardBalance)
            .reduce(0) { $0 + $1.amount }

        for entry in storedEntries {
            guard let index = categoryDrafts.firstIndex(where: { $0.category.rawValue == entry.categoryRaw }) else {
                continue
            }
            categoryDrafts[index].amountText = CashflowBulkExpenseRowDraft.formatAmount(entry.amount)
            categoryDrafts[index].noteText = entry.note ?? ""
        }
    }

    private func analyzePhotos(items: [PhotosPickerItem]) async {
        errorMessage = nil
        saveMessage = nil
        isErrorDismissed = false
        isSaveDismissed = false
        isProcessing = true
        defer { isProcessing = false }

        var imageDataList: [Data] = []
        for item in items.prefix(6) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                imageDataList.append(data)
            }
        }

        do {
            let parsedRows = try await parser.parseScreenshots(from: imageDataList)
            mergeParsedRowsIntoCategories(parsedRows)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mergeParsedRowsIntoCategories(_ parsedRows: [CashflowBulkExpenseParsedRow]) {
        guard !parsedRows.isEmpty else {
            errorMessage = String(
                localized: "cashflow.bulk_expense.manual.empty_parse",
                defaultValue: "Nothing usable was found in the imported data.",
                comment: "Error when bulk import parsing finds nothing"
            )
            return
        }

        let availableOptions = viewModel.categoryOptions(for: .expense)
        var mergedCount = 0

        for row in parsedRows {
            let resolution = categoryResolver.resolve(title: row.title, availableOptions: availableOptions)
            guard let index = categoryDrafts.firstIndex(where: { $0.category.rawValue == resolution.option.rawValue }) else {
                continue
            }
            let existingAmount = categoryDrafts[index].amount ?? 0
            let newAmount = existingAmount + row.amount
            categoryDrafts[index].amountText = CashflowBulkExpenseRowDraft.formatAmount(newAmount)
            mergedCount += 1
        }

        saveMessage = String(
            localized: "cashflow.bulk_expense.screenshot.merged",
            defaultValue: "Merged \(mergedCount) recognized expenses into monthly category totals.",
            comment: "Success message after merging screenshot rows into categories"
        )
        errorMessage = nil
        isSaveDismissed = false
        isErrorDismissed = false
        mode = .manual
    }

    private func saveRows() async {
        errorMessage = nil
        saveMessage = nil
        isErrorDismissed = false
        isSaveDismissed = false

        guard let selectedCardID else {
            errorMessage = CashflowBulkExpenseImportError.cardNotFound.localizedDescription
            isErrorDismissed = false
            return
        }

        let entries = filledDrafts.compactMap { draft -> CashflowBulkExpensePersistEntry? in
            guard let amount = draft.amount, amount > 0 else { return nil }
            return CashflowBulkExpensePersistEntry(
                amount: amount,
                expenseCategoryRaw: draft.category.rawValue,
                note: draft.normalizedNote,
                sourceOrderIndex: draft.sourceOrderIndex
            )
        }

        let request = CashflowBulkExpensePersistRequest(
            cardID: selectedCardID,
            month: selectedMonth,
            shouldAffectCardBalance: shouldAffectCardBalance,
            entries: entries
        )

        isProcessing = true
        defer { isProcessing = false }

        do {
            let savedCount = try await viewModel.persistBulkExpenseImport(request)
            saveMessage = String(
                localized: "cashflow.bulk_expense.saved",
                defaultValue: "Saved \(savedCount) category totals.",
                comment: "Success message after saving bulk expense import"
            )
            isSaveDismissed = false
            onComplete?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isErrorDismissed = false
        }
    }
}
