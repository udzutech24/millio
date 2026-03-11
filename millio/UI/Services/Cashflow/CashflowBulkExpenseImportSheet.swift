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
    @State private var selectedCardID: String?
    @State private var manualInput: String = ""
    @State private var rows: [CashflowBulkExpenseRowDraft] = []
    @State private var shouldAffectCardBalance: Bool = true
    @State private var statementTotalText: String = ""
    @State private var screenshotItems: [PhotosPickerItem] = []
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?
    @State private var saveMessage: String?

    private let parser = CashflowBulkExpenseImportParser()
    private let categoryResolver = CashflowBulkExpenseImportCategoryResolver()
    private let outerCornerRadius: CGFloat = 24
    private let innerCornerRadius: CGFloat = 18
    private let accent = Color(hex: "5FD1FF")
    private let positive = Color(hex: "6DFFC7")
    private let warning = Color(hex: "FFB454")

    init(
        viewModel: CashflowViewModel,
        month: Date,
        onComplete: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.month = month
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        introCard
                        controlsCard
                        inputCard
                        summaryCard
                        rowsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
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
                if selectedCardID == nil {
                    selectedCardID = preferredCard?.cardUniqueID
                }
            }
            .onChange(of: screenshotItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await analyzePhotos(items: newItems)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.stack.3d.down.right.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        String(
                            localized: "cashflow.bulk_expense.hero.title",
                            defaultValue: "Import a whole month at once",
                            comment: "Hero title for bulk expense import"
                        )
                    )
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))

                    Text(
                        String(
                            localized: "cashflow.bulk_expense.hero.subtitle",
                            defaultValue: "Choose a card, paste lines or load a bank screenshot, review categories, then save everything in one pass.",
                            comment: "Hero subtitle for bulk expense import"
                        )
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                badge(
                    title: monthTitle,
                    systemImage: "calendar"
                )
                badge(
                    title: selectedCard?.name ?? String(
                        localized: "cashflow.bulk_expense.no_card",
                        defaultValue: "No card",
                        comment: "Placeholder for no selected card"
                    ),
                    systemImage: "creditcard.fill"
                )
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $mode) {
                ForEach(CashflowBulkExpenseImportMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text(
                    String(
                        localized: "cashflow.bulk_expense.card_title",
                        defaultValue: "Card",
                        comment: "Card picker title in bulk expense import"
                    )
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.64))

                Menu {
                    ForEach(viewModel.state.availableCards, id: \.cardUniqueID) { card in
                        Button {
                            selectedCardID = card.cardUniqueID
                        } label: {
                            Label(card.name, systemImage: card.cardType.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selectedCard?.cardType.icon ?? "creditcard.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedCard?.name ?? String(
                                localized: "cashflow.bulk_expense.pick_card",
                                defaultValue: "Choose card",
                                comment: "Placeholder text for picking a card"
                            ))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.94))

                            if let selectedCard {
                                Text("\(CashflowBulkExpenseRowDraft.formatAmount(selectedCard.balance)) \(selectedCard.currency)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.58))
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.54))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .background(innerBackground)
                }
                .buttonStyle(.plain)
            }

            Toggle(
                isOn: $shouldAffectCardBalance,
                label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            String(
                                localized: "cashflow.bulk_expense.affect_balance",
                                defaultValue: "Update card balance",
                                comment: "Toggle title for applying card balance changes"
                            )
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))

                        Text(
                            String(
                                localized: "cashflow.bulk_expense.affect_balance.subtitle",
                                defaultValue: "Turn off if you only want history without touching the current balance.",
                                comment: "Toggle subtitle for applying card balance changes"
                            )
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                    }
                }
            )
            .toggleStyle(.switch)
            .tint(accent)
        }
        .padding(18)
        .background(cardBackground)
    }

    @ViewBuilder
    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode == .manual {
                Text(
                    String(
                        localized: "cashflow.bulk_expense.manual.hint",
                        defaultValue: "One line per expense: `supermarket 5 200`, `taxi 870`, `pharmacy 1 140`.",
                        comment: "Manual import input hint"
                    )
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))

                TextEditor(text: $manualInput)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(12)
                    .background(innerBackground)
                    .overlay(
                        Group {
                            if manualInput.isEmpty {
                                Text(
                                    String(
                                        localized: "cashflow.bulk_expense.manual.placeholder",
                                        defaultValue: "supermarket 12 480\nrestaurant 5 300\ninternet 890",
                                        comment: "Placeholder for manual bulk expense input"
                                    )
                                )
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.28))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(20)
                                .allowsHitTesting(false)
                            }
                        }
                    )

                Button {
                    parseManualInput()
                } label: {
                    rowActionLabel(
                        title: String(
                            localized: "cashflow.bulk_expense.manual.parse",
                            defaultValue: "Parse lines",
                            comment: "Parse manual bulk expense input button"
                        ),
                        systemImage: "wand.and.stars"
                    )
                }
                .buttonStyle(.plain)
                .disabled(manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
            } else {
                Text(
                    String(
                        localized: "cashflow.bulk_expense.screenshot.hint",
                        defaultValue: "Load one or several screenshots from your bank. The parser will extract merchant lines and amounts.",
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
            }

            if let errorMessage {
                inlineMessage(errorMessage, tint: warning)
            }
            if let saveMessage {
                inlineMessage(saveMessage, tint: positive)
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                summaryMetric(
                    title: String(
                        localized: "cashflow.bulk_expense.summary.rows",
                        defaultValue: "Rows",
                        comment: "Summary title for row count"
                    ),
                    value: "\(addableRows.count)/\(rows.count)"
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

            VStack(alignment: .leading, spacing: 8) {
                Text(
                    String(
                        localized: "cashflow.bulk_expense.summary.statement_total",
                        defaultValue: "Statement total (optional)",
                        comment: "Optional statement total field title"
                    )
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.64))

                TextField(
                    "",
                    text: $statementTotalText,
                    prompt: Text(
                        String(
                            localized: "cashflow.bulk_expense.summary.statement_total.placeholder",
                            defaultValue: "For example 101 552",
                            comment: "Placeholder for statement total field"
                        )
                    )
                    .foregroundStyle(Color.white.opacity(0.28))
                )
                .keyboardType(.decimalPad)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.94))
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(innerBackground)
            }

            if let remainingAmount {
                HStack(spacing: 10) {
                    Text(
                        String(
                            localized: "cashflow.bulk_expense.summary.remaining",
                            defaultValue: "Remaining",
                            comment: "Remaining amount label"
                        )
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                    Spacer()
                    Text("\(CashflowBulkExpenseRowDraft.formatAmount(remainingAmount)) \(selectedCard?.currency ?? "RUB")")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(remainingAmount > 0.009 ? warning : positive)
                }

                if remainingAmount > 0.009 {
                    Button {
                        appendRemainderRow(amount: remainingAmount)
                    } label: {
                        rowActionLabel(
                            title: String(
                                localized: "cashflow.bulk_expense.summary.remainder_to_other",
                                defaultValue: "Send remainder to Other",
                                comment: "Button to append remainder to Other category"
                            ),
                            systemImage: "plus.circle.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let selectedCard, shouldAffectCardBalance {
                let overflow = totalAmount - selectedCard.balance
                if overflow > 0.009 {
                    inlineMessage(
                        String(
                            localized: "cashflow.bulk_expense.summary.balance_warning",
                            defaultValue: "This import exceeds the selected card balance by \(CashflowBulkExpenseRowDraft.formatAmount(overflow)) \(selectedCard.currency).",
                            comment: "Warning for bulk expense import when amount exceeds card balance"
                        ),
                        tint: warning
                    )
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var rowsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(
                    String(
                        localized: "cashflow.bulk_expense.rows.title",
                        defaultValue: "Expense rows",
                        comment: "Bulk expense rows card title"
                    )
                )
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))

                Spacer()

                Button {
                    addEmptyRow()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }

            if rows.isEmpty {
                Text(
                    String(
                        localized: "cashflow.bulk_expense.rows.empty",
                        defaultValue: "No rows yet. Paste expenses or import screenshots first.",
                        comment: "Empty state for bulk expense rows"
                    )
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.54))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach($rows) { $row in
                        rowEditor($row)
                    }
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private func rowEditor(_ row: Binding<CashflowBulkExpenseRowDraft>) -> some View {
        let availableOptions = viewModel.categoryOptions(for: .expense)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                TextField(
                    String(
                        localized: "cashflow.bulk_expense.row.title_placeholder",
                        defaultValue: "Merchant or category",
                        comment: "Placeholder for bulk expense row title"
                    ),
                    text: row.titleText
                )
                .textInputAutocapitalization(.sentences)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.94))
                .onChange(of: row.wrappedValue.titleText) { _, _ in
                    reclassifyRow(id: row.wrappedValue.id)
                }

                Button(role: .destructive) {
                    rows.removeAll { $0.id == row.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                TextField(
                    String(
                        localized: "cashflow.bulk_expense.row.amount_placeholder",
                        defaultValue: "Amount",
                        comment: "Placeholder for bulk expense row amount"
                    ),
                    text: row.amountText
                )
                .keyboardType(.decimalPad)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(innerBackground)

                Menu {
                    ForEach(availableOptions, id: \.rawValue) { option in
                        Button {
                            row.wrappedValue.selectedCategoryRaw = option.rawValue
                            row.wrappedValue.usesSuggestedCategory = false
                            row.wrappedValue.confidence = max(row.wrappedValue.confidence, .medium)
                        } label: {
                            Label(option.displayName, systemImage: CashflowCustomCategory.isSFSymbolIcon(option.icon) ? option.icon : "tag.fill")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedCategoryName(for: row.wrappedValue))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(innerBackground)
                }
                .buttonStyle(.plain)
            }

            TextField(
                String(
                    localized: "cashflow.bulk_expense.row.note_placeholder",
                    defaultValue: "Optional note",
                    comment: "Placeholder for bulk expense row note"
                ),
                text: row.noteText
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.84))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(innerBackground)

            HStack(spacing: 8) {
                Text(row.wrappedValue.confidence.label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(confidenceColor(row.wrappedValue.confidence))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(confidenceColor(row.wrappedValue.confidence).opacity(0.12))
                    )

                if row.wrappedValue.requiresAttention {
                    Text(
                        String(
                            localized: "cashflow.bulk_expense.row.attention",
                            defaultValue: "Review category or amount",
                            comment: "Attention label for problematic bulk expense row"
                        )
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(warning)
                } else {
                    Text(
                        String(
                            localized: "cashflow.bulk_expense.row.ready",
                            defaultValue: "Ready to save",
                            comment: "Ready label for valid bulk expense row"
                        )
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(positive)
                }
            }
        }
        .padding(14)
        .background(innerBackground)
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.56))
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.94))
        }
    }

    private func badge(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.74))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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

    private func inlineMessage(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.82))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
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
        let cards = viewModel.state.availableCards
        if let selectedCardID,
           let selected = cards.first(where: { $0.cardUniqueID == selectedCardID }) {
            return selected
        }
        return cards.first(where: \.isFavorite) ?? cards.first
    }

    private var selectedCard: Card? {
        guard let selectedCardID else { return nil }
        return viewModel.state.availableCards.first(where: { $0.cardUniqueID == selectedCardID })
    }

    private var addableRows: [CashflowBulkExpenseRowDraft] {
        rows
            .filter(\.isAddable)
            .sorted { $0.sourceOrderIndex < $1.sourceOrderIndex }
    }

    private var canSave: Bool {
        selectedCardID != nil && !addableRows.isEmpty
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: month).localizedCapitalized
    }

    private var totalAmount: Double {
        addableRows.compactMap(\.amount).reduce(0, +)
    }

    private var totalAmountLabel: String {
        "\(CashflowBulkExpenseRowDraft.formatAmount(totalAmount)) \(selectedCard?.currency ?? "RUB")"
    }

    private var remainingAmount: Double? {
        guard let statementTotal = CashflowBulkExpenseRowDraft.parseAmount(statementTotalText) else { return nil }
        return max(0, statementTotal - totalAmount)
    }

    private func confidenceColor(_ confidence: CashflowBulkExpenseImportMatchConfidence) -> Color {
        switch confidence {
        case .high:
            return positive
        case .medium:
            return accent
        case .low:
            return warning
        }
    }

    private func selectedCategoryName(for row: CashflowBulkExpenseRowDraft) -> String {
        viewModel.categoryOption(for: row.selectedCategoryRaw, kind: .expense).displayName
    }

    private func addEmptyRow() {
        let nextIndex = (rows.map(\.sourceOrderIndex).max() ?? -1) + 1
        rows.append(
            CashflowBulkExpenseRowDraft(
                rawLine: "",
                titleText: "",
                amountText: "",
                sourceOrderIndex: nextIndex,
                confidence: .low
            )
        )
    }

    private func parseManualInput() {
        let parsedRows = CashflowBulkExpenseImportParser.parseManualInput(manualInput)
        rows = makeDrafts(from: parsedRows)
        errorMessage = rows.isEmpty
            ? String(
                localized: "cashflow.bulk_expense.manual.empty_parse",
                defaultValue: "Nothing usable was found in the pasted lines.",
                comment: "Error when manual input parsing finds nothing"
            )
            : nil
        saveMessage = nil
    }

    private func analyzePhotos(items: [PhotosPickerItem]) async {
        errorMessage = nil
        saveMessage = nil
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
            rows = makeDrafts(from: parsedRows)
        } catch {
            errorMessage = error.localizedDescription
            rows = []
        }
    }

    private func makeDrafts(from parsedRows: [CashflowBulkExpenseParsedRow]) -> [CashflowBulkExpenseRowDraft] {
        let availableOptions = viewModel.categoryOptions(for: .expense)

        return parsedRows.map { row in
            let resolution = categoryResolver.resolve(title: row.title, availableOptions: availableOptions)
            return CashflowBulkExpenseRowDraft(
                rawLine: row.rawLine,
                titleText: row.title,
                amountText: CashflowBulkExpenseRowDraft.formatAmount(row.amount),
                selectedCategoryRaw: resolution.option.rawValue,
                noteText: "",
                sourceOrderIndex: row.sourceOrderIndex,
                confidence: resolution.confidence,
                usesSuggestedCategory: true
            )
        }
    }

    private func reclassifyRow(id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        guard rows[index].usesSuggestedCategory else { return }
        let resolution = categoryResolver.resolve(
            title: rows[index].titleText,
            availableOptions: viewModel.categoryOptions(for: .expense)
        )
        rows[index].selectedCategoryRaw = resolution.option.rawValue
        rows[index].confidence = resolution.confidence
    }

    private func appendRemainderRow(amount: Double) {
        let nextIndex = (rows.map(\.sourceOrderIndex).max() ?? -1) + 1
        rows.append(
            CashflowBulkExpenseRowDraft(
                rawLine: "remainder",
                titleText: String(
                    localized: "cashflow.bulk_expense.remainder.title",
                    defaultValue: "Statement remainder",
                    comment: "Auto-generated title for statement remainder row"
                ),
                amountText: CashflowBulkExpenseRowDraft.formatAmount(amount),
                selectedCategoryRaw: ExpenseCategory.other.rawValue,
                noteText: String(
                    localized: "cashflow.bulk_expense.remainder.note",
                    defaultValue: "Auto-filled from statement total",
                    comment: "Auto-generated note for statement remainder row"
                ),
                sourceOrderIndex: nextIndex,
                confidence: .medium,
                usesSuggestedCategory: false
            )
        )
        statementTotalText = ""
    }

    private func saveRows() async {
        errorMessage = nil
        saveMessage = nil

        guard let selectedCardID else {
            errorMessage = CashflowBulkExpenseImportError.cardNotFound.localizedDescription
            return
        }

        let entries = addableRows.compactMap { row -> CashflowBulkExpensePersistEntry? in
            guard let amount = row.amount, amount > 0 else { return nil }
            return CashflowBulkExpensePersistEntry(
                amount: amount,
                expenseCategoryRaw: row.selectedCategoryRaw,
                note: row.normalizedExpenseNote,
                sourceOrderIndex: row.sourceOrderIndex
            )
        }

        let request = CashflowBulkExpensePersistRequest(
            cardID: selectedCardID,
            month: month,
            shouldAffectCardBalance: shouldAffectCardBalance,
            entries: entries
        )

        isProcessing = true
        defer { isProcessing = false }

        do {
            let savedCount = try await viewModel.persistBulkExpenseImport(request)
            saveMessage = String(
                localized: "cashflow.bulk_expense.saved",
                defaultValue: "Saved \(savedCount) expenses.",
                comment: "Success message after saving bulk expense import"
            )
            onComplete?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
