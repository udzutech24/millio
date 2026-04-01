//
//  CashflowBulkExpenseImportSheet.swift
//  millio
//
//  Created by Codex on 11.03.2026.
//

import SwiftUI
import PhotosUI

struct CashflowBulkExpenseImportToolbarPresentation: Equatable {
    let icon: String
    let isEnabled: Bool
}

struct CashflowBulkExpenseImportControlsStatusPresentation: Equatable {
    enum Tone: Equatable {
        case neutral
        case warning
    }

    let text: String
    let tone: Tone
}

struct CashflowBulkExpenseImportTilePresentation: Equatable {
    enum BorderTone: Equatable {
        case expenseDefault
        case transfer
    }

    let borderTone: BorderTone
}

struct CashflowBulkExpenseImportToggleToastPresentation: Equatable {
    let message: String
    let tint: Color
    let systemImage: String
}

private enum CashflowBulkExpenseImportSelectorStyle {
    case compact
    case expanded
}

enum CashflowBulkExpenseImportLayoutPolicy {
    static let floatingAddCategoryButtonSize: CGFloat = 38
    static let floatingAddCategoryBottomPadding: CGFloat = 28

    static func saveActionPresentation(canSave: Bool, isProcessing: Bool) -> CashflowBulkExpenseImportToolbarPresentation {
        CashflowBulkExpenseImportToolbarPresentation(
            icon: "checkmark",
            isEnabled: canSave && !isProcessing
        )
    }

    static func controlsStatus(balanceText: String?, hasCards: Bool) -> CashflowBulkExpenseImportControlsStatusPresentation? {
        if let balanceText, !balanceText.isEmpty {
            return CashflowBulkExpenseImportControlsStatusPresentation(
                text: balanceText,
                tone: .neutral
            )
        }

        guard !hasCards else { return nil }
        return CashflowBulkExpenseImportControlsStatusPresentation(
            text: String(localized: "cashflow.editor.no_cards_in_currency"),
            tone: .warning
        )
    }

    static func categoryTilePresentation(
        isTransferCategory: Bool
    ) -> CashflowBulkExpenseImportTilePresentation {
        if isTransferCategory {
            return CashflowBulkExpenseImportTilePresentation(
                borderTone: .transfer
            )
        }

        return CashflowBulkExpenseImportTilePresentation(
            borderTone: .expenseDefault
        )
    }

    static func scrollContentBottomPadding() -> CGFloat {
        BottomPinnedLayoutPolicy.scrollContentBottomPaddingForOverlay(
            overlayHeight: floatingAddCategoryButtonSize,
            overlayBottomPadding: floatingAddCategoryBottomPadding
        )
    }
}

struct CashflowBulkExpenseImportSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let month: Date
    let onComplete: (() -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var mode: CashflowBulkExpenseImportMode = .manual
    @State private var selectedCurrency: String = SettingsManager.shared.primaryCurrencyCode
    @State private var selectedCardID: String?
    @State private var selectedMonth: Date
    @State private var categoryDrafts: [CashflowBulkExpenseCategoryDraft] = []
    @State private var baselineCategoryTotals: [String: Double] = [:]
    @State private var screenshotPreviewRows: [CashflowBulkExpenseRowDraft] = []
    @State private var categorySearchText: String = ""
    @State private var importedCategoryRaws: Set<String> = []
    @State private var shouldAffectCardBalance: Bool = false
    @State private var loadedAffectingTotal: Double = 0
    @State private var screenshotItems: [PhotosPickerItem] = []
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?
    @State private var saveMessage: String?
    @State private var isErrorDismissed: Bool = false
    @State private var isSaveDismissed: Bool = false
    @State private var showPremiumAlert: Bool = false
    @State private var premiumAlertMessage: LocalizedTextResolver = .empty
    @State private var showHelpSheet: Bool = false
    @State private var showMonthPickerSheet: Bool = false
    @State private var showCategoryEditorSheet: Bool = false
    @State private var categoryEditorName: String = ""
    @State private var categoryEditorIcon: String = CashflowCustomCategory.defaultIcon
    @State private var pendingCategoryCreationRowID: UUID?
    @State private var affectBalanceToast: CashflowBulkExpenseImportToggleToastPresentation?
    @State private var isCategorySearchVisible: Bool = false
    @State private var didInitializeAffectBalanceToggle: Bool = false
    @State private var affectBalanceToastTask: Task<Void, Never>?
    @FocusState private var focusedCategoryID: String?
    @FocusState private var isCategorySearchFocused: Bool

    private let parser = CashflowBulkExpenseImportParser()
    private let outerCornerRadius: CGFloat = 24
    private let innerCornerRadius: CGFloat = 18
    private let accent = Color(hex: "5FD1FF")
    private let positive = Color(hex: "6DFFC7")
    private let warning = Color(hex: "FFB454")
    private let danger = Color(hex: "FF5A5F")
    private let preferredCurrency = SettingsManager.shared.primaryCurrencyCode
    private let categoryGridColumns = [
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
                        if !screenshotPreviewRows.isEmpty {
                            screenshotPreviewCard
                        }
                        categoriesCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, CashflowBulkExpenseImportLayoutPolicy.scrollContentBottomPadding())
                }

                floatingAddCategoryButton
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
            }
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

                ToolbarItem(placement: .principal) {
                    Text(CashflowBulkExpenseImportLocalization.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .accessibilityAddTraits(.isHeader)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showHelpSheet = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(CashflowBulkExpenseImportLocalization.helpOpen))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    let presentation = CashflowBulkExpenseImportLayoutPolicy.saveActionPresentation(
                        canSave: canSave,
                        isProcessing: isProcessing
                    )
                    Button {
                        Task {
                            await saveRows()
                        }
                    } label: {
                        Image(systemName: presentation.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(presentation.isEnabled ? AppColors.toggleOnGreen : AppColors.textSecondary.opacity(0.6))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(CashflowBulkExpenseImportLocalization.save))
                    .disabled(!canSave || isProcessing)
                }
            }
            .onAppear {
                showMonthPickerSheet = false
                didInitializeAffectBalanceToggle = false
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
            .onChange(of: shouldAffectCardBalance) { _, _ in
                if didInitializeAffectBalanceToggle {
                    presentAffectBalanceToast(isEnabled: shouldAffectCardBalance)
                } else {
                    didInitializeAffectBalanceToggle = true
                }
                Task {
                    await reloadDrafts()
                }
            }
            .onChange(of: CashflowViewModel.cardSyncSignature(for: viewModel.state.availableCards)) { _, _ in
                syncSelectionWithCurrency()
            }
            .onDisappear {
                showMonthPickerSheet = false
                affectBalanceToastTask?.cancel()
                affectBalanceToastTask = nil
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
        .premiumUpsellAlert(
            isPresented: $showPremiumAlert,
            titleKey: "monetization.free_plan.title",
            message: premiumAlertMessage,
            onSubscribe: {
                router.push(.subscription)
                dismiss()
            }
        )
    }

    private var introHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                affectBalanceHeaderControl
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let affectBalanceToast {
                affectBalanceToastBanner(affectBalanceToast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 6) {
            ForEach(CashflowBulkExpenseImportMode.allCases) { item in
                Button {
                    handleModeSelection(item)
                } label: {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .lineLimit(1)

                        if item.requiresPremiumAccess && !item.isUnlocked(canImportScreenshots: canImportScreenshotExpenses) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
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
        let status = CashflowBulkExpenseImportLayoutPolicy.controlsStatus(
            balanceText: shouldAffectCardBalance ? selectedCardBalanceText : nil,
            hasCards: !cardsInSelectedCurrency.isEmpty
        )
        let balanceStatus = status?.tone == .neutral ? status : nil
        let warningStatus = status?.tone == .warning ? status : nil

        return VStack(alignment: .leading, spacing: 8) {
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
                        value: selectedCurrency,
                        style: .compact
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
                        title: CashflowBulkExpenseImportLocalization.cardTitle,
                        value: selectedCard?.name ?? CashflowBulkExpenseImportLocalization.pickCard,
                        icon: selectedCard?.cardType.icon ?? "creditcard.fill",
                        usesPlaceholderStyle: selectedCard == nil,
                        style: .expanded
                    )
                }
                .buttonStyle(.plain)
                .disabled(cardsInSelectedCurrency.isEmpty)
                .opacity(cardsInSelectedCurrency.isEmpty ? 0.55 : 1)
                .frame(maxWidth: .infinity)
            }

            if let balanceStatus {
                HStack {
                    Spacer(minLength: 0)
                    controlsStatusBadge(balanceStatus)
                }
                .padding(.top, -2)
            }

            if let warningStatus {
                controlsStatusBadge(warningStatus)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(cardBackground)
    }

    private var affectBalanceHeaderControl: some View {
        HStack(spacing: 7) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.brandPrimary.opacity(0.92))
                .frame(width: 20, height: 20)

            Text(
                CashflowBulkExpenseImportLocalization.affectBalanceCompact
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 6)

            affectBalanceToggleButton
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minWidth: 210, maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .trailing)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(CashflowBulkExpenseImportLocalization.affectBalance))
    }

    private var affectBalanceToggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                shouldAffectCardBalance.toggle()
            }
        } label: {
            ZStack(alignment: shouldAffectCardBalance ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: shouldAffectCardBalance
                                ? [
                                    Color(hex: "2CD56F").opacity(0.96),
                                    Color(hex: "5EFF9A").opacity(0.92)
                                ]
                                : [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.05)
                                ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                shouldAffectCardBalance
                                    ? Color(hex: "7CFFAF").opacity(0.42)
                                    : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: shouldAffectCardBalance
                            ? Color(hex: "39E27D").opacity(0.26)
                            : .clear,
                        radius: 10
                    )

                Circle()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: shouldAffectCardBalance ? "checkmark" : "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(
                                shouldAffectCardBalance
                                    ? Color(hex: "1FA957")
                                    : Color.white.opacity(0.42)
                            )
                    )
                    .padding(3)
                    .shadow(color: Color.black.opacity(0.2), radius: 6, y: 1)
            }
            .frame(width: 60, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(CashflowBulkExpenseImportLocalization.affectBalance))
        .accessibilityValue(Text(CashflowBulkExpenseImportLocalization.toggleState(isEnabled: shouldAffectCardBalance)))
    }

    private func affectBalanceToastBanner(
        _ presentation: CashflowBulkExpenseImportToggleToastPresentation
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(presentation.tint.opacity(0.96))
                .padding(.top, 1)

            Text(
                presentation.message
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppColors.textSecondary.opacity(0.92))
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)

            Button {
                dismissAffectBalanceToast()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.textSecondary.opacity(0.84))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(presentation.tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(presentation.tint.opacity(0.24), lineWidth: 1)
        }
    }

    private func controlsStatusBadge(_ status: CashflowBulkExpenseImportControlsStatusPresentation) -> some View {
        let tint: Color
        switch status.tone {
        case .neutral:
            tint = AppColors.brandPrimary
        case .warning:
            tint = warning
        }

        return HStack(spacing: 6) {
            Image(systemName: status.tone == .neutral ? "creditcard.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
            Text(status.text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint.opacity(0.96))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func presentAffectBalanceToast(isEnabled: Bool) {
        let message = isEnabled
            ? String(
                localized: "cashflow.bulk_expense.affect_balance.toast.enabled",
                defaultValue: "Card balance will now update when you save this import.",
                comment: "Transient toast shown after enabling balance updates in bulk expense import"
            )
            : String(
                localized: "cashflow.bulk_expense.affect_balance.toast.disabled",
                defaultValue: "Card balance will no longer change when you save this import.",
                comment: "Transient toast shown after disabling balance updates in bulk expense import"
            )

        affectBalanceToastTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            affectBalanceToast = CashflowBulkExpenseImportToggleToastPresentation(
                message: message,
                tint: isEnabled ? AppColors.brandPrimary : warning,
                systemImage: isEnabled ? "arrow.triangle.2.circlepath.circle.fill" : "pause.circle.fill"
            )
        }

        affectBalanceToastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissAffectBalanceToast()
            }
        }
    }

    private func dismissAffectBalanceToast() {
        affectBalanceToastTask?.cancel()
        affectBalanceToastTask = nil
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            affectBalanceToast = nil
        }
    }

    private func compactSelectorLabel(
        title: String,
        value: String,
        icon: String? = nil,
        usesPlaceholderStyle: Bool = false,
        style: CashflowBulkExpenseImportSelectorStyle = .expanded
    ) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .textCase(.uppercase)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
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
        .frame(height: 44)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .frame(
            minWidth: style == .compact ? 160 : 210,
            maxWidth: style == .compact ? 180 : .infinity,
            alignment: .leading
        )
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
                        Text(CashflowBulkExpenseImportLocalization.done)
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
            Text(CashflowBulkExpenseImportLocalization.screenshotHint)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.58))

            PhotosPicker(
                selection: $screenshotItems,
                maxSelectionCount: 6,
                matching: .images
            ) {
                rowActionLabel(
                    title: isProcessing
                    ? CashflowBulkExpenseImportLocalization.screenshotProcessing
                    : CashflowBulkExpenseImportLocalization.screenshotPick,
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

    private var screenshotPreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CashflowBulkExpenseImportLocalization.screenshotReviewTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))

                Text(CashflowBulkExpenseImportLocalization.screenshotReviewSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                summaryMetric(title: CashflowBulkExpenseImportLocalization.screenshotReviewRows, value: "\(screenshotPreviewRows.count)")
                Spacer()
                Button {
                    applyScreenshotPreviewRows()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(CashflowBulkExpenseImportLocalization.screenshotReviewApply)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.95))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(accent.opacity(0.34), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            ForEach(screenshotPreviewRows) { row in
                screenshotPreviewRowCard(row)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func screenshotPreviewRowCard(_ row: CashflowBulkExpenseRowDraft) -> some View {
        let selectedOption = expenseCategoryOptions.first(where: { $0.rawValue == row.selectedCategoryRaw })
        let titleBinding = Binding(
            get: { previewRow(for: row.id)?.titleText ?? row.titleText },
            set: { updatePreviewRowTitle(row.id, title: $0) }
        )
        let amountBinding = Binding(
            get: { previewRow(for: row.id)?.amountText ?? row.amountText },
            set: { updatePreviewRowAmount(row.id, amountText: $0) }
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                previewConfidenceBadge(row)

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    removePreviewRow(row.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            TextField(
                CashflowBulkExpenseImportLocalization.rowTitlePlaceholder,
                text: titleBinding,
                prompt: Text(CashflowBulkExpenseImportLocalization.rowTitlePlaceholder).foregroundStyle(Color.white.opacity(0.28))
            )
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.94))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(innerBackground)

            HStack(spacing: 10) {
                TextField(
                    CashflowBulkExpenseImportLocalization.rowAmountPlaceholder,
                    text: amountBinding,
                    prompt: Text("0").foregroundStyle(Color.white.opacity(0.28))
                )
                .keyboardType(.decimalPad)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(warning)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(innerBackground)

                Text(selectedCurrency)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(innerBackground)
            }

            if let selectedOption, selectedOption.rawValue != ExpenseCategory.other.rawValue {
                Text(CashflowBulkExpenseImportLocalization.suggestion(selectedOption.displayName))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.54))
            }

            if !row.suggestedCategoryRaws.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(row.suggestedCategoryRaws, id: \.self) { rawValue in
                            if let option = expenseCategoryOptions.first(where: { $0.rawValue == rawValue }) {
                                previewSuggestionButton(rowID: row.id, option: option)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(expenseCategoryOptions, id: \.rawValue) { option in
                        Button {
                            selectPreviewCategory(row.id, categoryRaw: option.rawValue)
                        } label: {
                            Label(option.displayName, systemImage: option.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .semibold))
                        Text(CashflowBulkExpenseImportLocalization.useCategory)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.white.opacity(0.94))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                Button {
                    pendingCategoryCreationRowID = row.id
                    categoryEditorName = row.normalizedTitle
                    categoryEditorIcon = CashflowCustomCategory.defaultIcon
                    showCategoryEditorSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text(CashflowBulkExpenseImportLocalization.createCategory)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.94))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(accent.opacity(0.32), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(innerBackground)
    }

    private func previewSuggestionButton(rowID: UUID, option: CashflowCategoryOption) -> some View {
        Button {
            selectPreviewCategory(rowID, categoryRaw: option.rawValue)
        } label: {
            HStack(spacing: 6) {
                CashflowCategoryIconView(
                    icon: option.icon,
                    fontSize: 11,
                    fontWeight: .semibold,
                    tint: AnyShapeStyle(Color.white.opacity(0.92))
                )
                Text(option.displayName)
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.94))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func previewConfidenceBadge(_ row: CashflowBulkExpenseRowDraft) -> some View {
        let tint: Color = row.requiresAttention ? warning : positive
        let label = row.requiresAttention ? CashflowBulkExpenseImportLocalization.rowAttention : row.confidence.label

        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(tint.opacity(0.36), lineWidth: 1)
                    )
            )
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                let availableBalance = (selectedCardBalanceSnapshot?.availableAmount ?? selectedCard.balance) + loadedAffectingTotal
                let overflow = totalAmount - availableBalance
                if overflow > 0.009 {
                    noticeCard(
                        text: CashflowBulkExpenseImportLocalization.balanceWarning(
                            amount: overflow,
                            currencyCode: selectedCard.currency
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
        VStack(alignment: .leading, spacing: 12) {
            categoryHeaderCard

            if isCategorySearchVisible {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.42))

                    TextField(
                        CashflowBulkExpenseImportLocalization.searchCategory,
                        text: $categorySearchText
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .focused($isCategorySearchFocused)
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(innerBackground)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let selectedCard, shouldAffectCardBalance {
                let availableBalance = (selectedCardBalanceSnapshot?.availableAmount ?? selectedCard.balance) + loadedAffectingTotal
                let overflow = totalAmount - availableBalance
                if overflow > 0.009 {
                    noticeCard(
                        text: CashflowBulkExpenseImportLocalization.balanceWarning(
                            amount: overflow,
                            currencyCode: selectedCard.currency
                        ),
                        tint: warning,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                }
            }

            LazyVGrid(columns: categoryGridColumns, spacing: 8) {
                ForEach(orderedDraftIndices, id: \.self) { index in
                    categoryTile($categoryDrafts[index])
                }
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.88), value: orderedDraftIndices)

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
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: isCategorySearchVisible)
    }

    private var categoryHeaderCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    CashflowBulkExpenseImportLocalization.categories
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))

                Text("\(filledDrafts.count)/\(categoryDrafts.count)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.97))
            }

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Text(
                    CashflowBulkExpenseImportLocalization.total
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))

                Text(totalAmountLabel)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.98))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    isCategorySearchVisible.toggle()
                }
                if isCategorySearchVisible {
                    isCategorySearchFocused = true
                } else {
                    isCategorySearchFocused = false
                    categorySearchText = ""
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isCategorySearchVisible ? accent : Color.white.opacity(0.78))
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isCategorySearchVisible ? accent.opacity(0.14) : Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isCategorySearchVisible ? accent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(CashflowBulkExpenseImportLocalization.searchCategory))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(innerBackground)
    }

    private func categoryTile(_ draft: Binding<CashflowBulkExpenseCategoryDraft>) -> some View {
        let amountBinding = Binding(
            get: {
                draft.wrappedValue.amountText
            },
            set: { newValue in
                draft.wrappedValue.amountText = formatTileAmountInput(newValue)
                if !draft.wrappedValue.hasValue {
                    importedCategoryRaws.remove(draft.wrappedValue.category.rawValue)
                }
            }
        )
        let isTransferCategory = CashflowBulkExpenseCategorySortPolicy.isTransferCategory(
            draft.wrappedValue.category.rawValue
        )
        let breakdown = categoryBreakdown(for: draft.wrappedValue)
        let presentation = CashflowBulkExpenseImportLayoutPolicy.categoryTilePresentation(
            isTransferCategory: isTransferCategory
        )
        let tileFill = isTransferCategory ? danger.opacity(0.08) : Color.black.opacity(0.88)

        return VStack(spacing: 6) {
            HStack(alignment: .top) {
                CashflowCategoryIconView(
                    icon: draft.wrappedValue.category.icon,
                    fontSize: 18,
                    fontWeight: .semibold,
                    tint: AnyShapeStyle(Color.white.opacity(0.95))
                )
                Spacer(minLength: 6)
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

            if breakdown.importedAmount > 0.0000001 {
                categoryBreakdownLabel(breakdown)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 96)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(tileFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            categoryTileBorderGradient(
                                presentation: presentation,
                                hasValue: draft.wrappedValue.hasValue
                            ),
                            lineWidth: presentation.borderTone == .transfer ? 1.5 : (draft.wrappedValue.hasValue ? 1.4 : 1)
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
                importedCategoryRaws.remove(draft.wrappedValue.category.rawValue)
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

    private func categoryBreakdown(for draft: CashflowBulkExpenseCategoryDraft) -> CashflowBulkExpenseCategoryBreakdown {
        CashflowBulkExpenseCategoryBreakdown.make(
            displayedAmount: draft.amount,
            baselineAmount: baselineCategoryTotals[draft.category.rawValue] ?? 0
        )
    }

    private func categoryTileBorderGradient(
        presentation: CashflowBulkExpenseImportTilePresentation,
        hasValue: Bool
    ) -> LinearGradient {
        switch presentation.borderTone {
        case .expenseDefault:
            let colors = CashflowCategoryTransactionSheetKind.expense.gradientColors.map {
                $0.opacity(hasValue ? 0.9 : 0.5)
            }
            return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        case .transfer:
            return LinearGradient(
                colors: [danger.opacity(0.98), Color(hex: "FF8A5B").opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func categoryBreakdownLabel(_ breakdown: CashflowBulkExpenseCategoryBreakdown) -> some View {
        Text(
            CashflowBulkExpenseImportLocalization.categoryBreakdownLabel(
                baselineAmount: breakdown.baselineAmount,
                importedAmount: breakdown.importedAmount
            )
        )
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.52))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity)
        .padding(.top, -1)
    }

    private var floatingAddCategoryButton: some View {
        Button {
            categoryEditorName = ""
            categoryEditorIcon = CashflowCustomCategory.defaultIcon
            showCategoryEditorSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(
                    width: CashflowBulkExpenseImportLayoutPolicy.floatingAddCategoryButtonSize,
                    height: CashflowBulkExpenseImportLayoutPolicy.floatingAddCategoryButtonSize
                )
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
                                    lineWidth: 1.1
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

        if let rowID = pendingCategoryCreationRowID {
            selectPreviewCategory(rowID, categoryRaw: viewModel.categoryOptions(for: .expense, includeHiddenSystem: true)
                .first(where: { $0.displayName == trimmed && $0.isCustom })?.rawValue)
            pendingCategoryCreationRowID = nil
        }

        showCategoryEditorSheet = false
    }

    private func previewRow(for rowID: UUID) -> CashflowBulkExpenseRowDraft? {
        screenshotPreviewRows.first(where: { $0.id == rowID })
    }

    private func updatePreviewRowTitle(_ rowID: UUID, title: String) {
        guard let index = screenshotPreviewRows.firstIndex(where: { $0.id == rowID }) else { return }
        screenshotPreviewRows[index].titleText = title
        refreshPreviewRow(rowID)
    }

    private func updatePreviewRowAmount(_ rowID: UUID, amountText: String) {
        guard let index = screenshotPreviewRows.firstIndex(where: { $0.id == rowID }) else { return }
        screenshotPreviewRows[index].amountText = formatTileAmountInput(amountText)
    }

    private func selectPreviewCategory(_ rowID: UUID, categoryRaw: String?) {
        guard let categoryRaw,
              let index = screenshotPreviewRows.firstIndex(where: { $0.id == rowID }) else { return }
        screenshotPreviewRows[index].selectedCategoryRaw = categoryRaw
        screenshotPreviewRows[index].usesSuggestedCategory = false
        refreshPreviewRow(rowID)
    }

    private func removePreviewRow(_ rowID: UUID) {
        screenshotPreviewRows.removeAll { $0.id == rowID }
    }

    private func refreshPreviewRow(_ rowID: UUID) {
        guard let index = screenshotPreviewRows.firstIndex(where: { $0.id == rowID }) else { return }
        let existingRow = screenshotPreviewRows[index]
        screenshotPreviewRows[index] = CashflowBulkExpenseScreenshotReviewPolicy.refreshPreviewRow(
            existingRow,
            availableOptions: expenseCategoryOptions,
            preferredRawValue: viewModel.learnedBulkExpenseCategoryRaw(for: existingRow.normalizedTitle)
        )
    }

    private func applyScreenshotPreviewRows() {
        let result = CashflowBulkExpenseScreenshotReviewPolicy.applyPreviewRows(
            screenshotPreviewRows,
            to: categoryDrafts
        )

        categoryDrafts = result.categoryDrafts
        importedCategoryRaws.formUnion(result.importedCategoryRaws)

        for row in result.appliedRows {
            viewModel.rememberBulkExpenseCategory(
                categoryRaw: row.selectedCategoryRaw,
                for: row.normalizedTitle
            )
        }

        screenshotPreviewRows = result.remainingRows

        if result.appliedRows.isEmpty {
            saveMessage = CashflowBulkExpenseImportLocalization.mergeReviewRequiredMessage()
        } else if result.remainingRows.isEmpty {
            saveMessage = CashflowBulkExpenseImportLocalization.mergeCompletedMessage()
            mode = .manual
        } else {
            saveMessage = CashflowBulkExpenseImportLocalization.mergePartialMessage(
                appliedCount: result.appliedRows.count,
                remainingCount: result.remainingRows.count
            )
        }

        errorMessage = nil
        isSaveDismissed = false
        isErrorDismissed = false
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
                            body: CashflowBulkExpenseImportLocalization.screenshotStepBody
                        )
                        screenshotCroppingGuideCard
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
                CashflowBulkExpenseImportLocalization.helpSheetTitle
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(CashflowBulkExpenseImportLocalization.done) {
                        showHelpSheet = false
                    }
                    .foregroundStyle(accent)
                }
            }
        }
    }

    private var helpHeroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CashflowBulkExpenseImportLocalization.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.96))

            Text(
                CashflowBulkExpenseImportLocalization.helpHeroBody
            )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    private var screenshotCroppingGuideCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "crop")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(warning)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(warning.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        CashflowBulkExpenseImportLocalization.cropTitle
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.94))

                    Text(
                        CashflowBulkExpenseImportLocalization.cropSubtitle
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                }
            }

            screenshotCropExample

            helpHintRow(
                systemImage: "checkmark.circle.fill",
                tint: positive,
                text: CashflowBulkExpenseImportLocalization.cropDo
            )
            helpHintRow(
                systemImage: "checkmark.circle.fill",
                tint: positive,
                text: CashflowBulkExpenseImportLocalization.cropDoSecond
            )
            helpHintRow(
                systemImage: "xmark.circle.fill",
                tint: danger,
                text: CashflowBulkExpenseImportLocalization.cropDont
            )
            helpHintRow(
                systemImage: "exclamationmark.triangle.fill",
                tint: warning,
                text: CashflowBulkExpenseImportLocalization.cropWarning
            )
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

    private var screenshotCropExample: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                CashflowBulkExpenseImportLocalization.cropExampleTitle
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.72))

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.07, blue: 0.09))

                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 28)
                        .overlay(alignment: .leading) {
                            Text(CashflowBulkExpenseImportLocalization.cropExampleHistory)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .padding(.leading, 12)
                        }

                    VStack(spacing: 8) {
                        screenshotExampleRow(title: CashflowBulkExpenseImportLocalization.cropExampleMerchantGroceries, amount: "1 240 ₽")
                        screenshotExampleRow(title: CashflowBulkExpenseImportLocalization.cropExampleMerchantTaxi, amount: "870 ₽")
                        screenshotExampleRow(title: CashflowBulkExpenseImportLocalization.cropExampleMerchantCoffee, amount: "340 ₽")
                        screenshotExampleRow(title: CashflowBulkExpenseImportLocalization.cropExampleMerchantTransfer, amount: "5 000 ₽", tint: danger.opacity(0.9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(warning.opacity(0.92), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                            .padding(-6)
                    )

                    HStack(spacing: 8) {
                        cropBadZone(label: CashflowBulkExpenseImportLocalization.cropExampleBalance)
                        cropBadZone(label: CashflowBulkExpenseImportLocalization.cropExampleCards)
                        cropBadZone(label: CashflowBulkExpenseImportLocalization.cropExampleNav)
                    }
                }
                .padding(12)
            }
            .frame(height: 260)
        }
    }

    private func screenshotExampleRow(title: String, amount: String, tint: Color = Color.white.opacity(0.92)) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 18, height: 18)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(amount)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.26))
        )
    }

    private func cropBadZone(label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.58))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(danger.opacity(0.65), lineWidth: 1)
                    )
            )
    }

    private func helpHintRow(systemImage: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
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
            .fill(Color.white.opacity(0.018))
            .overlay(
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
            )
            .background(
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.12))
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

    private var selectedCardBalanceSnapshot: CashflowCardBalanceSnapshot? {
        guard let selectedCardID else { return nil }
        return viewModel.cardBalanceSnapshot(for: selectedCardID)
    }

    private var selectedCardBalanceText: String? {
        guard let selectedCard else { return nil }

        if let snapshot = selectedCardBalanceSnapshot {
            return String(
                format: String(localized: "cashflow.editor.available_format"),
                CashflowBulkExpenseRowDraft.formatAmount(snapshot.availableAmount),
                snapshot.currency
            )
        }

        return String(
            format: String(localized: "cashflow.editor.available_format"),
            CashflowBulkExpenseRowDraft.formatAmount(selectedCard.balance),
            selectedCard.currency
        )
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

    private var expenseCategoryOptions: [CashflowCategoryOption] {
        viewModel.categoryOptions(for: .expense, includeHiddenSystem: true)
    }

    private var filledDrafts: [CashflowBulkExpenseCategoryDraft] {
        categoryDrafts
            .filter(\.hasValue)
            .sorted { $0.sourceOrderIndex < $1.sourceOrderIndex }
    }

    private var orderedDraftIndices: [Int] {
        CashflowBulkExpenseCategorySortPolicy.orderedDraftIndices(
            drafts: categoryDrafts,
            searchText: categorySearchText,
            importedCategoryRaws: importedCategoryRaws
        )
    }

    private var canSave: Bool {
        selectedCardID != nil && !filledDrafts.isEmpty && screenshotPreviewRows.isEmpty
    }

    private var canImportScreenshotExpenses: Bool {
        EntitlementPolicy.canImportCashflowExpensesFromScreenshot(isPro: appState.isPro)
    }

    private var monthTitle: String {
        CashflowBulkExpenseImportLocalization.monthTitle(for: selectedMonth)
    }

    private var periodRangeTitle: String {
        CashflowBulkExpenseImportLocalization.periodRangeTitle(for: selectedMonth)
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
        if !canImportScreenshotExpenses, mode == .screenshot {
            mode = .manual
        }
        syncSelectionWithCurrency()
        if categoryDrafts.isEmpty {
            categoryDrafts = makeEmptyCategoryDrafts()
        }
        importedCategoryRaws = []
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
        viewModel.categoryOptions(for: .expense, includeHiddenSystem: true).enumerated().map { index, option in
            CashflowBulkExpenseCategoryDraft(category: option, sourceOrderIndex: index)
        }
    }

    private func reloadDrafts() async {
        let emptyDrafts = makeEmptyCategoryDrafts()
        categoryDrafts = emptyDrafts
        baselineCategoryTotals = [:]
        importedCategoryRaws = []
        screenshotPreviewRows = []
        loadedAffectingTotal = 0
        errorMessage = nil
        saveMessage = nil
        isErrorDismissed = false
        isSaveDismissed = false

        guard let selectedCardID else { return }
        let storedEntries = viewModel.bulkExpenseImportStoredEntries(
            cardID: selectedCardID,
            month: selectedMonth,
            affectsCardBalance: shouldAffectCardBalance
        )
        baselineCategoryTotals = viewModel.bulkExpenseImportBaselineCategoryTotals(
            cardID: selectedCardID,
            month: selectedMonth,
            affectsCardBalance: shouldAffectCardBalance
        )

        loadedAffectingTotal = storedEntries
            .filter(\.affectsCardBalance)
            .reduce(0) { $0 + $1.amount }

        for (categoryRaw, totalAmount) in baselineCategoryTotals where totalAmount > 0.0000001 {
            guard let index = categoryDrafts.firstIndex(where: { $0.category.rawValue == categoryRaw }) else {
                continue
            }
            categoryDrafts[index].amountText = CashflowBulkExpenseRowDraft.formatAmount(totalAmount)
        }

        for entry in storedEntries {
            guard let index = categoryDrafts.firstIndex(where: { $0.category.rawValue == entry.categoryRaw }) else {
                continue
            }
            let baselineAmount = baselineCategoryTotals[entry.categoryRaw] ?? 0
            categoryDrafts[index].amountText = CashflowBulkExpenseRowDraft.formatAmount(baselineAmount + entry.amount)
            categoryDrafts[index].noteText = entry.note ?? ""
        }
    }

    private func analyzePhotos(items: [PhotosPickerItem]) async {
        guard canImportScreenshotExpenses else {
            await MainActor.run {
                presentScreenshotImportUpsell()
                screenshotItems = []
            }
            return
        }
        errorMessage = nil
        saveMessage = nil
        isErrorDismissed = false
        isSaveDismissed = false
        screenshotPreviewRows = []
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
            prepareScreenshotPreviewRows(parsedRows)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareScreenshotPreviewRows(_ parsedRows: [CashflowBulkExpenseParsedRow]) {
        guard !parsedRows.isEmpty else {
            errorMessage = CashflowBulkExpenseImportLocalization.emptyParse
            return
        }

        screenshotPreviewRows = CashflowBulkExpenseScreenshotReviewPolicy.makePreviewRows(
            parsedRows: parsedRows,
            availableOptions: expenseCategoryOptions,
            preferredRawValueForTitle: { title in
                viewModel.learnedBulkExpenseCategoryRaw(for: title)
            }
        )

        saveMessage = CashflowBulkExpenseImportLocalization.recognizedRowsMessage(screenshotPreviewRows.count)
        errorMessage = nil
        isSaveDismissed = false
        isErrorDismissed = false
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
            guard let amount = draft.amount else { return nil }
            let baselineAmount = baselineCategoryTotals[draft.category.rawValue] ?? 0
            let importAmount = max(0, amount - baselineAmount)
            guard importAmount > 0 else { return nil }
            return CashflowBulkExpensePersistEntry(
                amount: importAmount,
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
            saveMessage = CashflowBulkExpenseImportLocalization.savedMessage(count: savedCount)
            isSaveDismissed = false
            onComplete?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isErrorDismissed = false
        }
    }

    private func handleModeSelection(_ selectedMode: CashflowBulkExpenseImportMode) {
        guard selectedMode.isUnlocked(canImportScreenshots: canImportScreenshotExpenses) else {
            presentScreenshotImportUpsell()
            return
        }
        mode = selectedMode
    }

    private func presentScreenshotImportUpsell() {
        premiumAlertMessage = .key("monetization.cashflow.bulk_expense_screenshot.pro_only")
        showPremiumAlert = true
        if mode == .screenshot {
            mode = .manual
        }
    }
}
